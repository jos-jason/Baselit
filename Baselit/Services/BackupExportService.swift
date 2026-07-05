import Foundation
import SwiftData

enum BackupExportService {

    struct ExportOptions {
        var includePhotos: Bool = true
    }

    // MARK: - Public API

    /// Exports all data to a ZIP file. Returns the URL of the created ZIP.
    static func exportBackup(
        options: ExportOptions,
        context: ModelContext
    ) throws -> URL {
        // 1. Fetch all entities
        let houses = try InventoryService.allHouses(in: context)
        let allLocations = try fetchAllLocations(in: context)
        let containers = try InventoryService.allContainers(in: context)
        let items = try InventoryService.allItems(in: context)
        let tags = try InventoryService.allTags(in: context)
        let photos = try fetchAllPhotos(in: context)

        // 2. Build export ID maps
        var houseIDMap: [ObjectIdentifier: UUID] = [:]
        var locationIDMap: [ObjectIdentifier: UUID] = [:]
        var containerIDMap: [ObjectIdentifier: UUID] = [:]
        var itemIDMap: [ObjectIdentifier: UUID] = [:]
        var tagIDMap: [ObjectIdentifier: UUID] = [:]
        var photoIDMap: [ObjectIdentifier: UUID] = [:]

        for house in houses { houseIDMap[ObjectIdentifier(house)] = UUID() }
        for location in allLocations { locationIDMap[ObjectIdentifier(location)] = UUID() }
        for container in containers { containerIDMap[ObjectIdentifier(container)] = UUID() }
        for item in items { itemIDMap[ObjectIdentifier(item)] = UUID() }
        for tag in tags { tagIDMap[ObjectIdentifier(tag)] = UUID() }
        for photo in photos { photoIDMap[ObjectIdentifier(photo)] = UUID() }

        // 3. Convert to DTOs
        let exportHouses = houses.map { house in
            ExportHouse(
                exportID: houseIDMap[ObjectIdentifier(house)]!,
                name: house.name,
                address: house.address,
                notes: house.notes,
                createdAt: house.createdAt,
                updatedAt: house.updatedAt
            )
        }

        let exportLocations = allLocations.map { location in
            ExportLocation(
                exportID: locationIDMap[ObjectIdentifier(location)]!,
                name: location.name,
                notes: location.notes,
                createdAt: location.createdAt,
                updatedAt: location.updatedAt,
                houseExportID: location.house.map { houseIDMap[ObjectIdentifier($0)] } ?? nil
            )
        }

        let exportContainers = containers.map { container in
            ExportContainer(
                exportID: containerIDMap[ObjectIdentifier(container)]!,
                name: container.name,
                containerType: container.containerType,
                notes: container.notes,
                identifier: container.identifier,
                createdAt: container.createdAt,
                updatedAt: container.updatedAt,
                parentContainerExportID: container.parentContainer.map { containerIDMap[ObjectIdentifier($0)] } ?? nil,
                locationExportID: container.location.map { locationIDMap[ObjectIdentifier($0)] } ?? nil
            )
        }

        let exportItems = items.map { item in
            ExportItem(
                exportID: itemIDMap[ObjectIdentifier(item)]!,
                name: item.name,
                itemDescription: item.itemDescription,
                category: item.category?.rawValue,
                color: item.color?.rawValue,
                quantity: item.quantity,
                brand: item.brand,
                model: item.model,
                condition: item.condition,
                notes: item.notes,
                identifier: item.identifier,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                containerExportID: item.container.map { containerIDMap[ObjectIdentifier($0)] } ?? nil,
                locationExportID: item.location.map { locationIDMap[ObjectIdentifier($0)] } ?? nil,
                tagExportIDs: item.tags.compactMap { tagIDMap[ObjectIdentifier($0)] }
            )
        }

        let exportTags = tags.map { tag in
            ExportTag(
                exportID: tagIDMap[ObjectIdentifier(tag)]!,
                name: tag.name
            )
        }

        let exportPhotos = photos.map { photo in
            let eid = photoIDMap[ObjectIdentifier(photo)]!
            return ExportPhoto(
                exportID: eid,
                filename: "photo_\(eid.uuidString).jpg",
                caption: photo.caption,
                createdAt: photo.createdAt,
                houseExportID: photo.house.map { houseIDMap[ObjectIdentifier($0)] } ?? nil,
                locationExportID: photo.location.map { locationIDMap[ObjectIdentifier($0)] } ?? nil,
                containerExportID: photo.container.map { containerIDMap[ObjectIdentifier($0)] } ?? nil,
                itemExportID: photo.item.map { itemIDMap[ObjectIdentifier($0)] } ?? nil
            )
        }

        // 4. Build manifest
        let manifest = BackupManifest(
            version: 1,
            exportDate: .now,
            includesPhotos: options.includePhotos,
            houses: exportHouses,
            locations: exportLocations,
            containers: exportContainers,
            items: exportItems,
            tags: exportTags,
            photos: exportPhotos
        )

        // 5. Create temp directory
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = dateFormatter.string(from: .now)
        let exportDirName = "baselit-export-\(dateString)"
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(exportDirName)

        // Clean up any existing directory with same name
        try? FileManager.default.removeItem(at: tempDir)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 6. Write photos if included
        if options.includePhotos {
            let photosDir = tempDir.appendingPathComponent("photos")
            try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

            for photo in photos {
                if let imageData = photo.imageData {
                    let eid = photoIDMap[ObjectIdentifier(photo)]!
                    let photoFile = photosDir.appendingPathComponent("photo_\(eid.uuidString).jpg")
                    try imageData.write(to: photoFile)
                }
            }
        }

        // 7. Encode and write JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(manifest)
        try jsonData.write(to: tempDir.appendingPathComponent("baselit_backup.json"))

        // 8. Create ZIP using NSFileCoordinator
        let zipFilename = "Baselit Backup \(dateString).zip"
        let zipDestination = FileManager.default.temporaryDirectory.appendingPathComponent(zipFilename)
        try? FileManager.default.removeItem(at: zipDestination)

        var coordinatorError: NSError?
        var zipError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: tempDir,
            options: .forUploading,
            error: &coordinatorError
        ) { tempZipURL in
            do {
                try FileManager.default.copyItem(at: tempZipURL, to: zipDestination)
            } catch {
                zipError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }
        if let zipError {
            throw zipError
        }

        // 9. Clean up temp directory
        try? FileManager.default.removeItem(at: tempDir)

        return zipDestination
    }

    // MARK: - Entity Counts

    static func entityCounts(in context: ModelContext) throws -> (houses: Int, locations: Int, containers: Int, items: Int, photos: Int) {
        let houses = try InventoryService.allHouses(in: context).count
        let locations = try fetchAllLocations(in: context).count
        let containers = try InventoryService.allContainers(in: context).count
        let items = try InventoryService.allItems(in: context).count
        let photos = try fetchAllPhotos(in: context).count
        return (houses, locations, containers, items, photos)
    }

    // MARK: - Private Helpers

    private static func fetchAllLocations(in context: ModelContext) throws -> [Location] {
        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\Location.name)])
        return try context.fetch(descriptor)
    }

    private static func fetchAllPhotos(in context: ModelContext) throws -> [Photo] {
        let descriptor = FetchDescriptor<Photo>(sortBy: [SortDescriptor(\Photo.createdAt)])
        return try context.fetch(descriptor)
    }
}
