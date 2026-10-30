import Foundation
import SwiftData
import Compression

enum BackupImportService {

    // MARK: - Parse Backup

    /// Extracts a ZIP backup and returns the manifest and path to the extracted directory.
    static func parseBackup(at url: URL) throws -> (manifest: BackupManifest, extractedDir: URL) {
        let fm = FileManager.default
        let extractDir = fm.temporaryDirectory.appendingPathComponent("baselit-import-\(UUID().uuidString)")
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        // Copy ZIP to temp location to avoid security scope issues
        let tempZip = extractDir.appendingPathComponent("backup.zip")
        try fm.copyItem(at: url, to: tempZip)

        // Extract ZIP using NSFileCoordinator reading as directory
        let contentDir = extractDir.appendingPathComponent("content")
        try fm.createDirectory(at: contentDir, withIntermediateDirectories: true)
        try extractZIP(at: tempZip, to: contentDir)

        // Find the JSON file (may be at root or in a subdirectory)
        let jsonURL = try findBackupJSON(in: contentDir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let jsonData = try Data(contentsOf: jsonURL)
        let manifest = try decoder.decode(BackupManifest.self, from: jsonData)

        return (manifest, contentDir)
    }

    // MARK: - Import: Replace All

    static func importReplaceAll(
        manifest: BackupManifest,
        extractedDir: URL,
        context: ModelContext
    ) throws -> ImportResult {
        // Delete all existing data
        try deleteAllData(in: context)

        // Import everything
        return try importAllEntities(manifest: manifest, extractedDir: extractedDir, context: context)
    }

    // MARK: - Import: Non-Duplicates Only

    static func importNonDuplicates(
        manifest: BackupManifest,
        extractedDir: URL,
        context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()

        // Build sets of existing identifiers/names
        let existingHouseNames = Set(try InventoryService.allHouses(in: context).map { $0.name.lowercased() })
        let existingLocations = try fetchAllLocations(in: context)
        let existingLocationKeys = Set(existingLocations.map { locationKey(name: $0.name, houseName: $0.resolvedHouse?.name, parentLocationName: $0.parentLocation?.name) })
        let existingContainerIDs = Set(try InventoryService.allContainers(in: context).map { $0.identifier.lowercased() })
        let existingItemIDs = Set(try InventoryService.allItems(in: context).map { $0.identifier.lowercased() })

        // Determine which entities to import (filter out duplicates)
        let housesToImport = manifest.houses.filter { !existingHouseNames.contains($0.name.lowercased()) }
        let skippedHouseIDs = Set(manifest.houses.filter { existingHouseNames.contains($0.name.lowercased()) }.map(\.exportID))

        let locationsToImport = manifest.locations.filter { loc in
            let houseName = loc.houseExportID.flatMap { hid in manifest.houses.first(where: { $0.exportID == hid })?.name }
                ?? loc.parentLocationExportID.flatMap { pid in
                    // Walk up to find house for sub-locations
                    resolveHouseName(for: pid, in: manifest)
                }
            let parentName = loc.parentLocationExportID.flatMap { pid in manifest.locations.first(where: { $0.exportID == pid })?.name }
            return !existingLocationKeys.contains(locationKey(name: loc.name, houseName: houseName, parentLocationName: parentName))
        }
        let skippedLocationIDs = Set(manifest.locations.map(\.exportID)).subtracting(locationsToImport.map(\.exportID))

        let containersToImport = manifest.containers.filter { !existingContainerIDs.contains($0.identifier.lowercased()) }
        let skippedContainerIDs = Set(manifest.containers.filter { existingContainerIDs.contains($0.identifier.lowercased()) }.map(\.exportID))

        let itemsToImport = manifest.items.filter { !existingItemIDs.contains($0.identifier.lowercased()) }
        let skippedItemIDs = Set(manifest.items.filter { existingItemIDs.contains($0.identifier.lowercased()) }.map(\.exportID))

        // Build a filtered manifest for importing
        // Photos: only import photos whose owner is being imported
        let photosToImport = manifest.photos.filter { photo in
            if let hid = photo.houseExportID { return !skippedHouseIDs.contains(hid) }
            if let lid = photo.locationExportID { return !skippedLocationIDs.contains(lid) }
            if let cid = photo.containerExportID { return !skippedContainerIDs.contains(cid) }
            if let iid = photo.itemExportID { return !skippedItemIDs.contains(iid) }
            return false
        }

        // HomeLocations: only import home locations whose owner is being imported
        let homeLocationsToImport = manifest.homeLocations.filter { hl in
            if let iid = hl.itemExportID { return !skippedItemIDs.contains(iid) }
            if let cid = hl.ownerContainerExportID { return !skippedContainerIDs.contains(cid) }
            return false
        }

        let filteredManifest = BackupManifest(
            version: manifest.version,
            exportDate: manifest.exportDate,
            includesPhotos: manifest.includesPhotos,
            houses: housesToImport,
            locations: locationsToImport,
            containers: containersToImport,
            items: itemsToImport,
            // All tags are kept so item tag names can be folded into notes
            tags: manifest.tags,
            photos: photosToImport,
            homeLocations: homeLocationsToImport
        )

        result = try importAllEntities(
            manifest: filteredManifest,
            extractedDir: extractedDir,
            context: context,
            existingContext: buildExistingEntityMaps(context: context, fullManifest: manifest)
        )
        result.skipped = manifest.houses.count - housesToImport.count
            + manifest.locations.count - locationsToImport.count
            + manifest.containers.count - containersToImport.count
            + manifest.items.count - itemsToImport.count

        return result
    }

    // MARK: - Conflict Detection

    static func detectConflicts(
        manifest: BackupManifest,
        context: ModelContext
    ) throws -> [ImportConflict] {
        var conflicts: [ImportConflict] = []

        // Houses: match by name
        let existingHouses = try InventoryService.allHouses(in: context)
        for exportHouse in manifest.houses {
            if let existing = existingHouses.first(where: { $0.name.lowercased() == exportHouse.name.lowercased() }) {
                let diffs = diffHouse(existing: existing, incoming: exportHouse)
                if !diffs.isEmpty {
                    conflicts.append(ImportConflict(
                        entityType: .house,
                        entityName: exportHouse.name,
                        identifier: exportHouse.name,
                        differences: diffs,
                        existingEntityID: existing.persistentModelID,
                        incomingExportID: exportHouse.exportID
                    ))
                }
                // If diffs is empty, it's identical — auto-skip
            }
        }

        // Locations: match by name + house name + parent location name
        let existingLocations = try fetchAllLocations(in: context)
        for exportLocation in manifest.locations {
            let exportHouseName = exportLocation.houseExportID.flatMap { hid in manifest.houses.first(where: { $0.exportID == hid })?.name }
                ?? resolveHouseName(for: exportLocation.exportID, in: manifest)
            let exportParentName = exportLocation.parentLocationExportID.flatMap { pid in manifest.locations.first(where: { $0.exportID == pid })?.name }
            if let existing = existingLocations.first(where: {
                $0.name.lowercased() == exportLocation.name.lowercased() &&
                $0.resolvedHouse?.name.lowercased() == exportHouseName?.lowercased() &&
                $0.parentLocation?.name.lowercased() == exportParentName?.lowercased()
            }) {
                let diffs = diffLocation(existing: existing, incoming: exportLocation)
                if !diffs.isEmpty {
                    conflicts.append(ImportConflict(
                        entityType: .location,
                        entityName: exportLocation.name,
                        identifier: "\(exportHouseName ?? "?") › \(exportLocation.name)",
                        differences: diffs,
                        existingEntityID: existing.persistentModelID,
                        incomingExportID: exportLocation.exportID
                    ))
                }
            }
        }

        // Containers: match by identifier
        let existingContainers = try InventoryService.allContainers(in: context)
        for exportContainer in manifest.containers {
            if let existing = existingContainers.first(where: {
                $0.identifier.lowercased() == exportContainer.identifier.lowercased()
            }) {
                let diffs = diffContainer(existing: existing, incoming: exportContainer, manifest: manifest)
                if !diffs.isEmpty {
                    conflicts.append(ImportConflict(
                        entityType: .container,
                        entityName: exportContainer.name,
                        identifier: exportContainer.identifier,
                        differences: diffs,
                        existingEntityID: existing.persistentModelID,
                        incomingExportID: exportContainer.exportID
                    ))
                }
            }
        }

        // Items: match by identifier
        let existingItems = try InventoryService.allItems(in: context)
        for exportItem in manifest.items {
            if let existing = existingItems.first(where: {
                $0.identifier.lowercased() == exportItem.identifier.lowercased()
            }) {
                let diffs = diffItem(existing: existing, incoming: exportItem, manifest: manifest)
                if !diffs.isEmpty {
                    conflicts.append(ImportConflict(
                        entityType: .item,
                        entityName: exportItem.name,
                        identifier: exportItem.identifier,
                        differences: diffs,
                        existingEntityID: existing.persistentModelID,
                        incomingExportID: exportItem.exportID
                    ))
                }
            }
        }

        return conflicts
    }

    // MARK: - Apply Conflict Resolutions

    static func importWithResolutions(
        manifest: BackupManifest,
        extractedDir: URL,
        resolutions: [UUID: ConflictResolution],
        conflicts: [ImportConflict],
        context: ModelContext
    ) throws -> ImportResult {
        var result = ImportResult()

        // Build resolution lookup by export ID
        var resolutionByExportID: [UUID: ConflictResolution] = [:]
        for conflict in conflicts {
            if let resolution = resolutions[conflict.id] {
                resolutionByExportID[conflict.incomingExportID] = resolution
            }
        }

        // Build sets of conflicting export IDs
        let conflictExportIDs = Set(conflicts.map(\.incomingExportID))

        // Identify existing entities for matching
        let existingHouses = try InventoryService.allHouses(in: context)
        let existingLocations = try fetchAllLocations(in: context)
        let existingContainers = try InventoryService.allContainers(in: context)
        let existingItems = try InventoryService.allItems(in: context)

        // Maps from export ID to created/existing SwiftData objects
        var houseMap: [UUID: House] = [:]
        var locationMap: [UUID: Location] = [:]
        var containerMap: [UUID: Container] = [:]
        var itemMap: [UUID: Item] = [:]

        // Pre-populate maps with existing entities that match (for relationship resolution)
        for exportHouse in manifest.houses {
            if let existing = existingHouses.first(where: { $0.name.lowercased() == exportHouse.name.lowercased() }) {
                houseMap[exportHouse.exportID] = existing
            }
        }
        for exportLoc in manifest.locations {
            let exportHouseName = exportLoc.houseExportID.flatMap { hid in manifest.houses.first(where: { $0.exportID == hid })?.name }
                ?? resolveHouseName(for: exportLoc.exportID, in: manifest)
            let exportParentName = exportLoc.parentLocationExportID.flatMap { pid in manifest.locations.first(where: { $0.exportID == pid })?.name }
            if let existing = existingLocations.first(where: {
                $0.name.lowercased() == exportLoc.name.lowercased() &&
                $0.resolvedHouse?.name.lowercased() == exportHouseName?.lowercased() &&
                $0.parentLocation?.name.lowercased() == exportParentName?.lowercased()
            }) {
                locationMap[exportLoc.exportID] = existing
            }
        }
        for exportContainer in manifest.containers {
            if let existing = existingContainers.first(where: {
                $0.identifier.lowercased() == exportContainer.identifier.lowercased()
            }) {
                containerMap[exportContainer.exportID] = existing
            }
        }
        for exportItem in manifest.items {
            if let existing = existingItems.first(where: {
                $0.identifier.lowercased() == exportItem.identifier.lowercased()
            }) {
                itemMap[exportItem.exportID] = existing
            }
        }

        // Import Houses
        for exportHouse in manifest.houses {
            if conflictExportIDs.contains(exportHouse.exportID) {
                let resolution = resolutionByExportID[exportHouse.exportID] ?? .keepExisting
                switch resolution {
                case .keepExisting:
                    result.skipped += 1
                case .replaceWithImport:
                    if let existing = houseMap[exportHouse.exportID] {
                        existing.name = exportHouse.name
                        existing.address = exportHouse.address
                        existing.notes = exportHouse.notes
                        existing.updatedAt = .now
                        result.housesImported += 1
                    }
                case .keepBoth:
                    let house = House(name: exportHouse.name + " (Imported)", address: exportHouse.address, notes: exportHouse.notes)
                    house.createdAt = exportHouse.createdAt
                    context.insert(house)
                    houseMap[exportHouse.exportID] = house
                    result.housesImported += 1
                }
            } else if houseMap[exportHouse.exportID] == nil {
                // New house, no conflict
                let house = House(name: exportHouse.name, address: exportHouse.address, notes: exportHouse.notes)
                house.createdAt = exportHouse.createdAt
                context.insert(house)
                houseMap[exportHouse.exportID] = house
                result.housesImported += 1
            } else {
                // Identical match — auto-skipped
                result.skipped += 1
            }
        }

        // Import Locations (topologically sorted)
        let sortedLocations = sortLocationsTopologically(manifest.locations)
        for exportLoc in sortedLocations {
            if conflictExportIDs.contains(exportLoc.exportID) {
                let resolution = resolutionByExportID[exportLoc.exportID] ?? .keepExisting
                switch resolution {
                case .keepExisting:
                    result.skipped += 1
                case .replaceWithImport:
                    if let existing = locationMap[exportLoc.exportID] {
                        existing.name = exportLoc.name
                        existing.notes = exportLoc.notes
                        existing.parentLocation = exportLoc.parentLocationExportID.flatMap { locationMap[$0] }
                        existing.updatedAt = .now
                        result.locationsImported += 1
                    }
                case .keepBoth:
                    let house = exportLoc.houseExportID.flatMap { houseMap[$0] }
                    let parentLocation = exportLoc.parentLocationExportID.flatMap { locationMap[$0] }
                    let location = Location(name: exportLoc.name + " (Imported)", house: house, parentLocation: parentLocation, notes: exportLoc.notes)
                    location.createdAt = exportLoc.createdAt
                    context.insert(location)
                    locationMap[exportLoc.exportID] = location
                    result.locationsImported += 1
                }
            } else if locationMap[exportLoc.exportID] == nil {
                let house = exportLoc.houseExportID.flatMap { houseMap[$0] }
                let parentLocation = exportLoc.parentLocationExportID.flatMap { locationMap[$0] }
                let location = Location(name: exportLoc.name, house: house, parentLocation: parentLocation, notes: exportLoc.notes)
                location.createdAt = exportLoc.createdAt
                context.insert(location)
                locationMap[exportLoc.exportID] = location
                result.locationsImported += 1
            } else {
                result.skipped += 1
            }
        }

        // Import Containers (topologically sorted)
        let sortedContainers = sortContainersTopologically(manifest.containers)
        for exportContainer in sortedContainers {
            if conflictExportIDs.contains(exportContainer.exportID) {
                let resolution = resolutionByExportID[exportContainer.exportID] ?? .keepExisting
                switch resolution {
                case .keepExisting:
                    result.skipped += 1
                case .replaceWithImport:
                    if let existing = containerMap[exportContainer.exportID] {
                        existing.name = exportContainer.name
                        existing.containerType = exportContainer.containerType
                        existing.notes = exportContainer.notes
                        existing.lastLabelPrintedAt = exportContainer.lastLabelPrintedAt
                        existing.parentContainer = exportContainer.parentContainerExportID.flatMap { containerMap[$0] }
                        existing.location = exportContainer.locationExportID.flatMap { locationMap[$0] }
                        existing.house = exportContainer.houseExportID.flatMap { houseMap[$0] }
                        existing.updatedAt = .now
                        result.containersImported += 1
                    }
                case .keepBoth:
                    let container = Container(
                        name: exportContainer.name,
                        containerType: exportContainer.containerType,
                        location: exportContainer.locationExportID.flatMap { locationMap[$0] },
                        parentContainer: exportContainer.parentContainerExportID.flatMap { containerMap[$0] },
                        notes: exportContainer.notes
                    )
                    container.identifier = IdentifierGenerator.generate()
                    container.createdAt = exportContainer.createdAt
                    container.lastLabelPrintedAt = exportContainer.lastLabelPrintedAt
                    container.house = exportContainer.houseExportID.flatMap { houseMap[$0] }
                    context.insert(container)
                    containerMap[exportContainer.exportID] = container
                    result.containersImported += 1
                }
            } else if containerMap[exportContainer.exportID] == nil {
                let container = Container(
                    name: exportContainer.name,
                    containerType: exportContainer.containerType,
                    location: exportContainer.locationExportID.flatMap { locationMap[$0] },
                    parentContainer: exportContainer.parentContainerExportID.flatMap { containerMap[$0] },
                    notes: exportContainer.notes
                )
                container.identifier = exportContainer.identifier
                container.createdAt = exportContainer.createdAt
                container.lastLabelPrintedAt = exportContainer.lastLabelPrintedAt
                container.house = exportContainer.houseExportID.flatMap { houseMap[$0] }
                context.insert(container)
                containerMap[exportContainer.exportID] = container
                result.containersImported += 1
            } else {
                result.skipped += 1
            }
        }

        // Import Items
        for exportItem in manifest.items {
            if conflictExportIDs.contains(exportItem.exportID) {
                let resolution = resolutionByExportID[exportItem.exportID] ?? .keepExisting
                switch resolution {
                case .keepExisting:
                    result.skipped += 1
                case .replaceWithImport:
                    if let existing = itemMap[exportItem.exportID] {
                        existing.name = exportItem.name
                        existing.itemDescription = exportItem.itemDescription
                        existing.quantity = exportItem.quantity
                        existing.brand = exportItem.brand
                        existing.model = exportItem.model
                        existing.condition = exportItem.condition
                        existing.notes = exportItem.notesWithLegacyKeywords(tags: manifest.tags)
                        existing.lastLabelPrintedAt = exportItem.lastLabelPrintedAt
                        existing.container = exportItem.containerExportID.flatMap { containerMap[$0] }
                        existing.location = exportItem.locationExportID.flatMap { locationMap[$0] }
                        existing.house = exportItem.houseExportID.flatMap { houseMap[$0] }
                        existing.updatedAt = .now
                        result.itemsImported += 1
                    }
                case .keepBoth:
                    let item = Item(name: exportItem.name, quantity: exportItem.quantity)
                    item.identifier = IdentifierGenerator.generate()
                    item.itemDescription = exportItem.itemDescription
                    item.brand = exportItem.brand
                    item.model = exportItem.model
                    item.condition = exportItem.condition
                    item.notes = exportItem.notesWithLegacyKeywords(tags: manifest.tags)
                    item.lastLabelPrintedAt = exportItem.lastLabelPrintedAt
                    item.container = exportItem.containerExportID.flatMap { containerMap[$0] }
                    item.location = exportItem.locationExportID.flatMap { locationMap[$0] }
                    item.house = exportItem.houseExportID.flatMap { houseMap[$0] }
                    item.createdAt = exportItem.createdAt
                    context.insert(item)
                    itemMap[exportItem.exportID] = item
                    result.itemsImported += 1
                }
            } else if itemMap[exportItem.exportID] == nil {
                let item = Item(name: exportItem.name, quantity: exportItem.quantity)
                item.identifier = exportItem.identifier
                item.itemDescription = exportItem.itemDescription
                item.brand = exportItem.brand
                item.model = exportItem.model
                item.condition = exportItem.condition
                item.notes = exportItem.notesWithLegacyKeywords(tags: manifest.tags)
                item.lastLabelPrintedAt = exportItem.lastLabelPrintedAt
                item.container = exportItem.containerExportID.flatMap { containerMap[$0] }
                item.location = exportItem.locationExportID.flatMap { locationMap[$0] }
                item.house = exportItem.houseExportID.flatMap { houseMap[$0] }
                item.createdAt = exportItem.createdAt
                context.insert(item)
                itemMap[exportItem.exportID] = item
                result.itemsImported += 1
            } else {
                result.skipped += 1
            }
        }

        // Import Photos
        result.photosImported = try importPhotos(manifest: manifest, extractedDir: extractedDir, context: context,
                                                  houseMap: houseMap, locationMap: locationMap,
                                                  containerMap: containerMap, itemMap: itemMap,
                                                  skipExportIDs: nil)

        // Import Home Locations
        for exportHL in manifest.homeLocations {
            guard let house = houseMap[exportHL.houseExportID] else { continue }
            let hl = HomeLocation(house: house)
            hl.location = exportHL.locationExportID.flatMap { locationMap[$0] }
            hl.container = exportHL.containerExportID.flatMap { containerMap[$0] }
            hl.item = exportHL.itemExportID.flatMap { itemMap[$0] }
            hl.ownerContainer = exportHL.ownerContainerExportID.flatMap { containerMap[$0] }
            hl.createdAt = exportHL.createdAt
            hl.updatedAt = exportHL.updatedAt
            context.insert(hl)
            result.homeLocationsImported += 1
        }

        try context.save()
        return result
    }

    // MARK: - Private: Core Import Logic

    private static func importAllEntities(
        manifest: BackupManifest,
        extractedDir: URL,
        context: ModelContext,
        existingContext: ExistingEntityMaps? = nil
    ) throws -> ImportResult {
        var result = ImportResult()

        var houseMap: [UUID: House] = existingContext?.houseMap ?? [:]
        var locationMap: [UUID: Location] = existingContext?.locationMap ?? [:]
        var containerMap: [UUID: Container] = existingContext?.containerMap ?? [:]
        var itemMap: [UUID: Item] = [:]

        // Houses
        for exportHouse in manifest.houses {
            let house = House(name: exportHouse.name, address: exportHouse.address, notes: exportHouse.notes)
            house.createdAt = exportHouse.createdAt
            context.insert(house)
            houseMap[exportHouse.exportID] = house
            result.housesImported += 1
        }

        // Locations (topologically sorted)
        let sortedLocations = sortLocationsTopologically(manifest.locations)
        for exportLoc in sortedLocations {
            let house = exportLoc.houseExportID.flatMap { houseMap[$0] }
            let parentLocation = exportLoc.parentLocationExportID.flatMap { locationMap[$0] }
            let location = Location(name: exportLoc.name, house: house, parentLocation: parentLocation, notes: exportLoc.notes)
            location.createdAt = exportLoc.createdAt
            context.insert(location)
            locationMap[exportLoc.exportID] = location
            result.locationsImported += 1
        }

        // Containers (topologically sorted)
        let sortedContainers = sortContainersTopologically(manifest.containers)
        for exportContainer in sortedContainers {
            let container = Container(
                name: exportContainer.name,
                containerType: exportContainer.containerType,
                location: exportContainer.locationExportID.flatMap { locationMap[$0] },
                parentContainer: exportContainer.parentContainerExportID.flatMap { containerMap[$0] },
                notes: exportContainer.notes
            )
            // Set identifier from backup (not generating a new one)
            container.identifier = exportContainer.identifier
            container.createdAt = exportContainer.createdAt
            container.lastLabelPrintedAt = exportContainer.lastLabelPrintedAt
            container.house = exportContainer.houseExportID.flatMap { houseMap[$0] }
            context.insert(container)
            containerMap[exportContainer.exportID] = container
            result.containersImported += 1
        }

        // Items
        for exportItem in manifest.items {
            let item = Item(name: exportItem.name, quantity: exportItem.quantity)
            item.identifier = exportItem.identifier
            item.itemDescription = exportItem.itemDescription
            item.brand = exportItem.brand
            item.model = exportItem.model
            item.condition = exportItem.condition
            item.notes = exportItem.notesWithLegacyKeywords(tags: manifest.tags)
            item.lastLabelPrintedAt = exportItem.lastLabelPrintedAt
            item.container = exportItem.containerExportID.flatMap { containerMap[$0] }
            item.location = exportItem.locationExportID.flatMap { locationMap[$0] }
            item.house = exportItem.houseExportID.flatMap { houseMap[$0] }
            item.createdAt = exportItem.createdAt
            context.insert(item)
            itemMap[exportItem.exportID] = item
            result.itemsImported += 1
        }

        // Photos
        result.photosImported = try importPhotos(manifest: manifest, extractedDir: extractedDir, context: context,
                                                  houseMap: houseMap, locationMap: locationMap,
                                                  containerMap: containerMap, itemMap: itemMap,
                                                  skipExportIDs: nil)

        // Home Locations
        for exportHL in manifest.homeLocations {
            guard let house = houseMap[exportHL.houseExportID] else { continue }
            let hl = HomeLocation(house: house)
            hl.location = exportHL.locationExportID.flatMap { locationMap[$0] }
            hl.container = exportHL.containerExportID.flatMap { containerMap[$0] }
            hl.item = exportHL.itemExportID.flatMap { itemMap[$0] }
            hl.ownerContainer = exportHL.ownerContainerExportID.flatMap { containerMap[$0] }
            hl.createdAt = exportHL.createdAt
            hl.updatedAt = exportHL.updatedAt
            context.insert(hl)
            result.homeLocationsImported += 1
        }

        try context.save()
        return result
    }

    // MARK: - Private: Photo Import

    private static func importPhotos(
        manifest: BackupManifest,
        extractedDir: URL,
        context: ModelContext,
        houseMap: [UUID: House],
        locationMap: [UUID: Location],
        containerMap: [UUID: Container],
        itemMap: [UUID: Item],
        skipExportIDs: Set<UUID>?
    ) throws -> Int {
        var count = 0
        let photosDir = findPhotosDirectory(in: extractedDir)

        for exportPhoto in manifest.photos {
            if let skipIDs = skipExportIDs, skipIDs.contains(exportPhoto.exportID) {
                continue
            }

            // Determine owner — skip if owner not in our maps
            let ownerHouse = exportPhoto.houseExportID.flatMap { houseMap[$0] }
            let ownerLocation = exportPhoto.locationExportID.flatMap { locationMap[$0] }
            let ownerContainer = exportPhoto.containerExportID.flatMap { containerMap[$0] }
            let ownerItem = exportPhoto.itemExportID.flatMap { itemMap[$0] }

            guard ownerHouse != nil || ownerLocation != nil || ownerContainer != nil || ownerItem != nil else {
                continue
            }

            // Load image data if available
            var imageData: Data?
            if let photosDir {
                let photoFile = photosDir.appendingPathComponent(exportPhoto.filename)
                if FileManager.default.fileExists(atPath: photoFile.path) {
                    imageData = try? Data(contentsOf: photoFile)
                }
            }

            let photo = Photo(imageData: imageData, caption: exportPhoto.caption, sortOrder: exportPhoto.sortOrder)
            photo.createdAt = exportPhoto.createdAt
            photo.house = ownerHouse
            photo.location = ownerLocation
            photo.container = ownerContainer
            photo.item = ownerItem
            context.insert(photo)
            count += 1
        }

        return count
    }

    // MARK: - Private: Delete All

    private static func deleteAllData(in context: ModelContext) throws {
        // Delete in reverse dependency order
        let homeLocations = try context.fetch(FetchDescriptor<HomeLocation>())
        for hl in homeLocations { context.delete(hl) }

        let photos = try context.fetch(FetchDescriptor<Photo>())
        for photo in photos { context.delete(photo) }

        let items = try InventoryService.allItems(in: context)
        for item in items { context.delete(item) }

        let containers = try InventoryService.allContainers(in: context)
        for container in containers { context.delete(container) }

        let locations = try fetchAllLocations(in: context)
        for location in locations { context.delete(location) }

        let houses = try InventoryService.allHouses(in: context)
        for house in houses { context.delete(house) }

        try context.save()
    }

    // MARK: - Private: Topological Sort

    private static func sortLocationsTopologically(_ locations: [ExportLocation]) -> [ExportLocation] {
        var sorted: [ExportLocation] = []
        var remaining = locations
        var createdIDs: Set<UUID> = []

        while !remaining.isEmpty {
            let batch = remaining.filter { loc in
                loc.parentLocationExportID == nil || createdIDs.contains(loc.parentLocationExportID!)
            }
            guard !batch.isEmpty else {
                // Circular reference — just append remaining
                sorted.append(contentsOf: remaining)
                break
            }
            sorted.append(contentsOf: batch)
            createdIDs.formUnion(batch.map(\.exportID))
            remaining.removeAll { loc in createdIDs.contains(loc.exportID) }
        }
        return sorted
    }

    private static func sortContainersTopologically(_ containers: [ExportContainer]) -> [ExportContainer] {
        var sorted: [ExportContainer] = []
        var remaining = containers
        var createdIDs: Set<UUID> = []

        while !remaining.isEmpty {
            let batch = remaining.filter { c in
                c.parentContainerExportID == nil || createdIDs.contains(c.parentContainerExportID!)
            }
            guard !batch.isEmpty else {
                // Circular reference — just append remaining
                sorted.append(contentsOf: remaining)
                break
            }
            sorted.append(contentsOf: batch)
            createdIDs.formUnion(batch.map(\.exportID))
            remaining.removeAll { c in createdIDs.contains(c.exportID) }
        }
        return sorted
    }

    // MARK: - Private: Diff Helpers

    private static func diffHouse(existing: House, incoming: ExportHouse) -> [PropertyDifference] {
        var diffs: [PropertyDifference] = []
        if existing.name != incoming.name {
            diffs.append(PropertyDifference(propertyName: "Name", existingValue: existing.name, incomingValue: incoming.name))
        }
        if existing.address != incoming.address {
            diffs.append(PropertyDifference(propertyName: "Address", existingValue: existing.address ?? "(none)", incomingValue: incoming.address ?? "(none)"))
        }
        if existing.notes != incoming.notes {
            diffs.append(PropertyDifference(propertyName: "Notes", existingValue: existing.notes ?? "(none)", incomingValue: incoming.notes ?? "(none)"))
        }
        return diffs
    }

    private static func diffLocation(existing: Location, incoming: ExportLocation) -> [PropertyDifference] {
        var diffs: [PropertyDifference] = []
        if existing.name != incoming.name {
            diffs.append(PropertyDifference(propertyName: "Name", existingValue: existing.name, incomingValue: incoming.name))
        }
        if existing.notes != incoming.notes {
            diffs.append(PropertyDifference(propertyName: "Notes", existingValue: existing.notes ?? "(none)", incomingValue: incoming.notes ?? "(none)"))
        }
        return diffs
    }

    private static func diffContainer(existing: Container, incoming: ExportContainer, manifest: BackupManifest) -> [PropertyDifference] {
        var diffs: [PropertyDifference] = []
        if existing.name != incoming.name {
            diffs.append(PropertyDifference(propertyName: "Name", existingValue: existing.name, incomingValue: incoming.name))
        }
        if existing.containerType != incoming.containerType {
            diffs.append(PropertyDifference(propertyName: "Type", existingValue: existing.containerType ?? "(none)", incomingValue: incoming.containerType ?? "(none)"))
        }
        if existing.notes != incoming.notes {
            diffs.append(PropertyDifference(propertyName: "Notes", existingValue: existing.notes ?? "(none)", incomingValue: incoming.notes ?? "(none)"))
        }
        let existingParentID = existing.parentContainer?.identifier ?? "(none)"
        let incomingParentID = incoming.parentContainerExportID.flatMap { pid in
            manifest.containers.first(where: { $0.exportID == pid })?.identifier
        } ?? "(none)"
        if existingParentID != incomingParentID {
            diffs.append(PropertyDifference(propertyName: "Parent Container", existingValue: existingParentID, incomingValue: incomingParentID))
        }
        let existingLocName = existing.location?.name ?? "(none)"
        let incomingLocName = incoming.locationExportID.flatMap { lid in
            manifest.locations.first(where: { $0.exportID == lid })?.name
        } ?? "(none)"
        if existingLocName != incomingLocName {
            diffs.append(PropertyDifference(propertyName: "Location", existingValue: existingLocName, incomingValue: incomingLocName))
        }
        let existingHouseName = existing.house?.name ?? "(none)"
        let incomingHouseName = incoming.houseExportID.flatMap { hid in
            manifest.houses.first(where: { $0.exportID == hid })?.name
        } ?? "(none)"
        if existingHouseName != incomingHouseName {
            diffs.append(PropertyDifference(propertyName: "House", existingValue: existingHouseName, incomingValue: incomingHouseName))
        }
        return diffs
    }

    private static func diffItem(existing: Item, incoming: ExportItem, manifest: BackupManifest) -> [PropertyDifference] {
        var diffs: [PropertyDifference] = []
        if existing.name != incoming.name {
            diffs.append(PropertyDifference(propertyName: "Name", existingValue: existing.name, incomingValue: incoming.name))
        }
        if existing.itemDescription != incoming.itemDescription {
            diffs.append(PropertyDifference(propertyName: "Description", existingValue: existing.itemDescription ?? "(none)", incomingValue: incoming.itemDescription ?? "(none)"))
        }
        if existing.quantity != incoming.quantity {
            diffs.append(PropertyDifference(propertyName: "Quantity", existingValue: "\(existing.quantity)", incomingValue: "\(incoming.quantity)"))
        }
        if existing.brand != incoming.brand {
            diffs.append(PropertyDifference(propertyName: "Brand", existingValue: existing.brand ?? "(none)", incomingValue: incoming.brand ?? "(none)"))
        }
        if existing.model != incoming.model {
            diffs.append(PropertyDifference(propertyName: "Model", existingValue: existing.model ?? "(none)", incomingValue: incoming.model ?? "(none)"))
        }
        if existing.condition != incoming.condition {
            diffs.append(PropertyDifference(propertyName: "Condition", existingValue: existing.condition ?? "(none)", incomingValue: incoming.condition ?? "(none)"))
        }
        let incomingNotes = incoming.notesWithLegacyKeywords(tags: manifest.tags)
        if existing.notes != incomingNotes {
            diffs.append(PropertyDifference(propertyName: "Notes", existingValue: existing.notes ?? "(none)", incomingValue: incomingNotes ?? "(none)"))
        }
        let existingContainerID = existing.container?.identifier ?? "(none)"
        let incomingContainerID = incoming.containerExportID.flatMap { cid in
            manifest.containers.first(where: { $0.exportID == cid })?.identifier
        } ?? "(none)"
        if existingContainerID != incomingContainerID {
            diffs.append(PropertyDifference(propertyName: "Container", existingValue: existingContainerID, incomingValue: incomingContainerID))
        }
        let existingLocName = existing.location?.name ?? "(none)"
        let incomingLocName = incoming.locationExportID.flatMap { lid in
            manifest.locations.first(where: { $0.exportID == lid })?.name
        } ?? "(none)"
        if existingLocName != incomingLocName {
            diffs.append(PropertyDifference(propertyName: "Location", existingValue: existingLocName, incomingValue: incomingLocName))
        }
        let existingHouseName = existing.house?.name ?? "(none)"
        let incomingHouseName = incoming.houseExportID.flatMap { hid in
            manifest.houses.first(where: { $0.exportID == hid })?.name
        } ?? "(none)"
        if existingHouseName != incomingHouseName {
            diffs.append(PropertyDifference(propertyName: "House", existingValue: existingHouseName, incomingValue: incomingHouseName))
        }
        return diffs
    }

    // MARK: - Private: Helpers

    /// Walk up the location parent chain in the manifest to find the house name
    private static func resolveHouseName(for locationExportID: UUID, in manifest: BackupManifest) -> String? {
        var currentID: UUID? = locationExportID
        while let id = currentID {
            guard let loc = manifest.locations.first(where: { $0.exportID == id }) else { return nil }
            if let houseID = loc.houseExportID {
                return manifest.houses.first(where: { $0.exportID == houseID })?.name
            }
            currentID = loc.parentLocationExportID
        }
        return nil
    }

    private static func locationKey(name: String, houseName: String?, parentLocationName: String? = nil) -> String {
        "\(houseName?.lowercased() ?? "")||\(parentLocationName?.lowercased() ?? "")||\(name.lowercased())"
    }

    private static func fetchAllLocations(in context: ModelContext) throws -> [Location] {
        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\Location.name)])
        return try context.fetch(descriptor)
    }

    private struct ExistingEntityMaps {
        var houseMap: [UUID: House] = [:]
        var locationMap: [UUID: Location] = [:]
        var containerMap: [UUID: Container] = [:]
    }

    private static func buildExistingEntityMaps(context: ModelContext, fullManifest: BackupManifest) -> ExistingEntityMaps {
        var maps = ExistingEntityMaps()

        guard let existingHouses = try? InventoryService.allHouses(in: context),
              let existingLocations = try? fetchAllLocations(in: context),
              let existingContainers = try? InventoryService.allContainers(in: context) else {
            return maps
        }

        // Map export IDs to existing entities where they match
        for exportHouse in fullManifest.houses {
            if let existing = existingHouses.first(where: { $0.name.lowercased() == exportHouse.name.lowercased() }) {
                maps.houseMap[exportHouse.exportID] = existing
            }
        }
        for exportLoc in fullManifest.locations {
            let exportHouseName = exportLoc.houseExportID.flatMap { hid in fullManifest.houses.first(where: { $0.exportID == hid })?.name }
                ?? resolveHouseName(for: exportLoc.exportID, in: fullManifest)
            let exportParentName = exportLoc.parentLocationExportID.flatMap { pid in fullManifest.locations.first(where: { $0.exportID == pid })?.name }
            if let existing = existingLocations.first(where: {
                $0.name.lowercased() == exportLoc.name.lowercased() &&
                $0.resolvedHouse?.name.lowercased() == exportHouseName?.lowercased() &&
                $0.parentLocation?.name.lowercased() == exportParentName?.lowercased()
            }) {
                maps.locationMap[exportLoc.exportID] = existing
            }
        }
        for exportContainer in fullManifest.containers {
            if let existing = existingContainers.first(where: {
                $0.identifier.lowercased() == exportContainer.identifier.lowercased()
            }) {
                maps.containerMap[exportContainer.exportID] = existing
            }
        }

        return maps
    }

    // MARK: - Private: ZIP Extraction

    private static func extractZIP(at zipURL: URL, to destination: URL) throws {
        try manualUnzip(zipURL: zipURL, to: destination)
    }

    /// Minimal ZIP extraction implementation using Foundation
    private static func manualUnzip(zipURL: URL, to destination: URL) throws {
        let fm = FileManager.default
        let data = try Data(contentsOf: zipURL)

        // Parse ZIP central directory
        let entries = try parseZIPEntries(data: data)

        for entry in entries {
            let entryPath = destination.appendingPathComponent(entry.filename)

            if entry.filename.hasSuffix("/") {
                // Directory
                try fm.createDirectory(at: entryPath, withIntermediateDirectories: true)
            } else {
                // File
                let parentDir = entryPath.deletingLastPathComponent()
                if !fm.fileExists(atPath: parentDir.path) {
                    try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }
                try entry.data.write(to: entryPath)
            }
        }
    }

    private struct ZIPEntry {
        let filename: String
        let data: Data
    }

    /// Parse ZIP file format to extract entries
    private static func parseZIPEntries(data: Data) throws -> [ZIPEntry] {
        var entries: [ZIPEntry] = []
        var offset = 0

        while offset + 4 <= data.count {
            // Check for local file header signature: 0x04034b50
            let sig = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
            guard sig == 0x04034b50 else { break }

            // Parse local file header
            let compressionMethod = data.subdata(in: (offset+8)..<(offset+10)).withUnsafeBytes { $0.load(as: UInt16.self) }
            let compressedSize = Int(data.subdata(in: (offset+18)..<(offset+22)).withUnsafeBytes { $0.load(as: UInt32.self) })
            let uncompressedSize = Int(data.subdata(in: (offset+22)..<(offset+26)).withUnsafeBytes { $0.load(as: UInt32.self) })
            let filenameLength = Int(data.subdata(in: (offset+26)..<(offset+28)).withUnsafeBytes { $0.load(as: UInt16.self) })
            let extraFieldLength = Int(data.subdata(in: (offset+28)..<(offset+30)).withUnsafeBytes { $0.load(as: UInt16.self) })

            let filenameStart = offset + 30
            let filenameEnd = filenameStart + filenameLength
            guard filenameEnd <= data.count else { break }

            let filenameData = data.subdata(in: filenameStart..<filenameEnd)
            let filename = String(data: filenameData, encoding: .utf8) ?? ""

            let dataStart = filenameEnd + extraFieldLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= data.count else { break }

            // Skip __MACOSX and hidden files
            if filename.hasPrefix("__MACOSX") || filename.contains("/.") {
                offset = dataEnd
                continue
            }

            if compressionMethod == 0 {
                // Stored (no compression)
                let fileData = data.subdata(in: dataStart..<dataEnd)
                entries.append(ZIPEntry(filename: filename, data: fileData))
            } else if compressionMethod == 8 {
                // Deflate — use Compression framework
                let compressedData = data.subdata(in: dataStart..<dataEnd)
                if let decompressed = decompressDeflate(compressedData, expectedSize: uncompressedSize) {
                    entries.append(ZIPEntry(filename: filename, data: decompressed))
                }
            }
            // Skip other compression methods

            offset = dataEnd

            // Check for data descriptor (bit 3 of general purpose flags)
            let flags = data.subdata(in: (offset - compressedSize - extraFieldLength - filenameLength - 24)..<(offset - compressedSize - extraFieldLength - filenameLength - 22))
                .withUnsafeBytes { $0.load(as: UInt16.self) }
            if flags & 0x08 != 0 {
                // Skip data descriptor (12 or 16 bytes)
                if offset + 4 <= data.count {
                    let descSig = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
                    if descSig == 0x08074b50 {
                        offset += 16  // signature + crc32 + compressed + uncompressed
                    } else {
                        offset += 12  // crc32 + compressed + uncompressed (no signature)
                    }
                }
            }
        }

        return entries
    }

    /// Decompress deflate data using the Compression framework
    private static func decompressDeflate(_ data: Data, expectedSize: Int) -> Data? {
        let bufferSize = max(expectedSize, 1024)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { destinationBuffer.deallocate() }

        let decompressedSize = data.withUnsafeBytes { (sourceBytes: UnsafeRawBufferPointer) -> Int in
            guard let baseAddress = sourceBytes.baseAddress else { return 0 }
            let sourcePointer = baseAddress.bindMemory(to: UInt8.self, capacity: data.count)
            return compression_decode_buffer(
                destinationBuffer, bufferSize,
                sourcePointer, data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard decompressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }

    // MARK: - Private: Find Files in Extracted Directory

    private static func findBackupJSON(in directory: URL) throws -> URL {
        let fm = FileManager.default

        // Check root level first
        let rootJSON = directory.appendingPathComponent("baselit_backup.json")
        if fm.fileExists(atPath: rootJSON.path) {
            return rootJSON
        }

        // Check one level deep (ZIP may contain a subdirectory)
        if let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for item in contents {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nestedJSON = item.appendingPathComponent("baselit_backup.json")
                    if fm.fileExists(atPath: nestedJSON.path) {
                        return nestedJSON
                    }
                }
            }
        }

        throw BackupError.jsonNotFound
    }

    private static func findPhotosDirectory(in directory: URL) -> URL? {
        let fm = FileManager.default

        // Check root level
        let rootPhotos = directory.appendingPathComponent("photos")
        if fm.fileExists(atPath: rootPhotos.path) {
            return rootPhotos
        }

        // Check one level deep
        if let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for item in contents {
                let nestedPhotos = item.appendingPathComponent("photos")
                if fm.fileExists(atPath: nestedPhotos.path) {
                    return nestedPhotos
                }
            }
        }

        return nil
    }

    // MARK: - Cleanup

    static func cleanupExtractedFiles(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case jsonNotFound
    case unsupportedVersion(Int)
    case invalidData(String)

    var errorDescription: String? {
        switch self {
        case .jsonNotFound:
            return "Could not find baselit_backup.json in the backup file."
        case .unsupportedVersion(let version):
            return "This backup was created by a newer version of Baselit (version \(version))."
        case .invalidData(let detail):
            return "Invalid backup data: \(detail)"
        }
    }
}
