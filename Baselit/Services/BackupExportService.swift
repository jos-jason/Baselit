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
                houseExportID: location.house.map { houseIDMap[ObjectIdentifier($0)] } ?? nil,
                parentLocationExportID: location.parentLocation.map { locationIDMap[ObjectIdentifier($0)] } ?? nil
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
                lastLabelPrintedAt: container.lastLabelPrintedAt,
                parentContainerExportID: container.parentContainer.map { containerIDMap[ObjectIdentifier($0)] } ?? nil,
                locationExportID: container.location.map { locationIDMap[ObjectIdentifier($0)] } ?? nil,
                houseExportID: container.house.map { houseIDMap[ObjectIdentifier($0)] } ?? nil
            )
        }

        let exportItems = items.map { item in
            ExportItem(
                exportID: itemIDMap[ObjectIdentifier(item)]!,
                name: item.name,
                itemDescription: item.itemDescription,
                category: item.category?.rawValue,
                colors: item.colors.map(\.rawValue),
                quantity: item.quantity,
                brand: item.brand,
                model: item.model,
                condition: item.condition,
                notes: item.notes,
                identifier: item.identifier,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                lastLabelPrintedAt: item.lastLabelPrintedAt,
                containerExportID: item.container.map { containerIDMap[ObjectIdentifier($0)] } ?? nil,
                locationExportID: item.location.map { locationIDMap[ObjectIdentifier($0)] } ?? nil,
                houseExportID: item.house.map { houseIDMap[ObjectIdentifier($0)] } ?? nil,
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

        // 7b. Write schema readme for data portability
        let readme = generateSchemaReadme(manifest: manifest)
        try readme.write(to: tempDir.appendingPathComponent("SCHEMA_README.md"), atomically: true, encoding: .utf8)

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

    // MARK: - Schema Readme

    private static func generateSchemaReadme(manifest: BackupManifest) -> String {
        """
        # Baselit Backup — Data Schema Reference
        
        This file describes the structure of the data in `baselit_backup.json` so that
        a human programmer or AI coding assistant can rebuild a compatible application
        from scratch, even without access to the original Baselit source code.
        
        **Backup version:** \(manifest.version)
        **Export date:** \(ISO8601DateFormatter().string(from: manifest.exportDate))
        **Photos included:** \(manifest.includesPhotos ? "Yes" : "No")
        
        ---
        
        ## Overview
        
        Baselit is a home inventory management app. It organizes physical belongings in a
        hierarchy:
        
            House → Location → Container → Item
        
        - A **House** is a top-level place (e.g. "Home", "Storage Unit").
        - A **Location** is a room or area within a house (e.g. "Kitchen", "Garage").
          Locations can nest inside other locations to arbitrary depth (e.g. a pantry
          inside a kitchen).
        - A **Container** is a box, shelf, drawer, etc. Containers can nest inside other
          containers to arbitrary depth (e.g. a box inside a closet inside a room).
        - An **Item** is a physical object stored in a container or directly in a location.
        - **Tags** provide cross-cutting labels for items (many-to-many relationship).
        - **Photos** can be attached to any entity (house, location, container, or item).
        
        ---
        
        ## File Structure
        
        The ZIP archive contains:
        
        ```
        baselit_backup.json    — All structured data (this is the critical file)
        SCHEMA_README.md       — This file (human/AI-readable schema documentation)
        photos/                — Directory of image files (if photos were included)
            photo_<UUID>.jpg   — Individual photo files referenced by the JSON
        ```
        
        ---
        
        ## JSON Structure
        
        The root object in `baselit_backup.json` is a **BackupManifest** with these fields:
        
        ```json
        {
            "version": 1,
            "exportDate": "2024-01-15T10:30:00Z",
            "includesPhotos": true,
            "houses": [...],
            "locations": [...],
            "containers": [...],
            "items": [...],
            "tags": [...],
            "photos": [...]
        }
        ```
        
        All dates use ISO 8601 format. All relationship references use UUID strings
        (`exportID` fields) that are unique within this backup file. These UUIDs are
        generated fresh for each export — they are NOT persistent database IDs.
        
        ---
        
        ## Entity Schemas
        
        ### House
        
        ```json
        {
            "exportID": "UUID — unique identifier for this export",
            "name": "string — required, the name of the house/property",
            "address": "string? — optional street address",
            "notes": "string? — optional freeform notes",
            "createdAt": "ISO8601 date",
            "updatedAt": "ISO8601 date"
        }
        ```
        
        ### Location
        
        ```json
        {
            "exportID": "UUID",
            "name": "string — required, e.g. 'Kitchen', 'Garage'",
            "notes": "string? — optional",
            "createdAt": "ISO8601 date",
            "updatedAt": "ISO8601 date",
            "houseExportID": "UUID? — references a House.exportID. Only set for top-level locations",
            "parentLocationExportID": "UUID? — references another Location.exportID for nesting. null = top-level"
        }
        ```
        
        **Nesting:** Locations can form a tree via `parentLocationExportID`. A location's
        effective house is determined by walking up the parent chain until you find one
        with a non-null `houseExportID`. When rebuilding, create locations in topological
        order (parents before children).
        
        ### Container
        
        ```json
        {
            "exportID": "UUID",
            "name": "string — required, e.g. 'Big Blue Box'",
            "containerType": "string? — optional, e.g. 'box', 'shelf', 'drawer', 'bin', 'closet'",
            "notes": "string? — optional",
            "identifier": "string — a permanent two-word label like 'Bright Falcon' (see Identifiers section)",
            "createdAt": "ISO8601 date",
            "updatedAt": "ISO8601 date",
            "parentContainerExportID": "UUID? — references another Container.exportID for nesting. null = top-level",
            "locationExportID": "UUID? — references a Location.exportID. Only set for top-level containers"
        }
        ```
        
        **Nesting:** Containers form a tree via `parentContainerExportID`. A container's
        effective location is determined by walking up the parent chain until you find one
        with a non-null `locationExportID`. When rebuilding, create containers in topological
        order (parents before children).
        
        ### Item
        
        ```json
        {
            "exportID": "UUID",
            "name": "string — required",
            "itemDescription": "string? — optional longer description",
            "category": "string? — one of the ItemCategory values listed below, or null",
            "colors": "[string] — array of ItemColor values listed below (may be empty)",
            "quantity": "integer — how many of this item (minimum 1)",
            "brand": "string? — optional brand name",
            "model": "string? — optional model number/name",
            "condition": "string? — optional condition description",
            "notes": "string? — optional freeform notes",
            "identifier": "string — permanent two-word label like 'Calm River'",
            "createdAt": "ISO8601 date",
            "updatedAt": "ISO8601 date",
            "containerExportID": "UUID? — references a Container.exportID",
            "locationExportID": "UUID? — references a Location.exportID (used when item is directly in a location, not in a container)",
            "tagExportIDs": ["UUID — array of Tag.exportID references"]
        }
        ```
        
        **Placement:** An item is either in a container (`containerExportID`) or directly
        in a location (`locationExportID`), but not both simultaneously.
        
        ### Tag
        
        ```json
        {
            "exportID": "UUID",
            "name": "string — unique, lowercase, trimmed. e.g. 'fragile', 'sentimental'"
        }
        ```
        
        Tags have a many-to-many relationship with items via the `tagExportIDs` array on
        each Item. Tag names are normalized to lowercase with whitespace trimmed.
        
        ### Photo
        
        ```json
        {
            "exportID": "UUID",
            "filename": "string — e.g. 'photo_<UUID>.jpg', the filename in the photos/ directory",
            "caption": "string? — optional caption",
            "createdAt": "ISO8601 date",
            "houseExportID": "UUID? — if this photo belongs to a house",
            "locationExportID": "UUID? — if this photo belongs to a location",
            "containerExportID": "UUID? — if this photo belongs to a container",
            "itemExportID": "UUID? — if this photo belongs to an item"
        }
        ```
        
        **Ownership:** Exactly one of the four `*ExportID` fields will be non-null,
        indicating which entity the photo is attached to. If `includesPhotos` is false in
        the manifest, the photo metadata is still present in the JSON but the actual image
        files will not exist in the `photos/` directory — the data can still be fully
        restored without images.
        
        ---
        
        ## Enum Values
        
        ### ItemCategory
        
        Valid values for the `category` field on Item:
        
        ```
        electronics, clothing, tools, kitchenware, documents, books, toys,
        sports, seasonal, medical, crafts, furniture, decor, outdoor, art, wellness, jewelry, other
        ```
        
        ### ItemColor
        
        Valid values for entries in the `colors` array on Item:
        
        ```
        red, orange, yellow, green, blue, teal, turquoise, purple, pink, black, white, gray,
        brown, silver, gold, multicolor, clear, other
        ```
        
        Unknown values should be treated as null/unset rather than causing errors.
        Future versions may add new enum cases.
        
        ---
        
        ## Identifiers
        
        Containers and Items each have a permanent two-word `identifier` field (e.g.
        "Bright Falcon", "Calm River"). These are generated from a list of 100 adjectives
        and 100 nouns, giving 10,000 possible combinations. Identifiers:
        
        - Are assigned at creation and never change, even when other data is edited.
        - Are used as stable, human-readable references for QR code labels.
        - Should be treated as case-insensitive for matching purposes.
        - Are unique within their entity type (no two containers share an identifier,
          no two items share an identifier, but a container and an item may share one).
        
        The QR code format used by the app is: `baselit:<type>:<slug>` where `<type>`
        is either `container` or `item`, and `<slug>` is the identifier with the space
        replaced by a hyphen and lowercased. Example: `baselit:container:bright-falcon`.
        
        ---
        
        ## Relationship Summary
        
        ```
        House (1)
          └─► Location (many)        — houseExportID → House.exportID (top-level only)
                ├─► Location (many)  — parentLocationExportID → Location.exportID (nested)
                ├─► Container (many)  — locationExportID → Location.exportID (top-level only)
                │     ├─► Container   — parentContainerExportID → Container.exportID (nested)
                │     ├─► Item        — containerExportID → Container.exportID
                │     └─► Photo       — containerExportID → Container.exportID
                ├─► Item (many)       — locationExportID → Location.exportID (direct placement)
                │     ├─► Tag         — tagExportIDs → [Tag.exportID] (many-to-many)
                │     └─► Photo       — itemExportID → Item.exportID
                └─► Photo             — locationExportID → Location.exportID
          └─► Photo                   — houseExportID → House.exportID
        ```
        
        ---
        
        ## Rebuilding an App from This Data
        
        To create a new application that can read and display this data:
        
        1. **Parse the JSON** — Deserialize `baselit_backup.json` using any JSON parser.
           All fields use standard JSON types (string, number, boolean, null, array, object).
        
        2. **Build entity lookup tables** — Create a dictionary from `exportID` to each
           parsed entity. This lets you resolve all relationship references.
        
        3. **Reconstruct the hierarchy** in dependency order:
           a. Tags (no dependencies)
           b. Houses (no dependencies)
           c. Locations — sort topologically by `parentLocationExportID`:
              create locations with null parent first, then children. Each location
              depends on its parent location (if nested) and its house (if top-level).
           d. Containers — sort topologically by `parentContainerExportID`:
              create containers with null parent first, then children. Each container
              depends on its parent container (if nested) and its location (if top-level).
           e. Items (depend on Containers, Locations, and Tags)
           f. Photos (depend on their owner entity)
        
        4. **Load photos** — Read image files from the `photos/` directory using the
           `filename` field. Handle missing files gracefully (the data is still valid
           without images).
        
        5. **Persist to your database** — Map the entities to your app's data model
           and store them. Preserve the `identifier` field on Containers and Items
           exactly as-is (do not regenerate) so that existing QR code labels remain
           functional.
        
        6. **Minimum viable UI** — At minimum, provide:
           - A hierarchical browser: Houses → Locations → Containers → Items
           - A search function across item names, descriptions, brands, and tags
           - The ability to view photos attached to each entity
           - The ability to export data back to this same format for future portability
        
        ---
        
        ## Data Statistics for This Backup
        
        - Houses: \(manifest.houses.count)
        - Locations: \(manifest.locations.count)
        - Containers: \(manifest.containers.count)
        - Items: \(manifest.items.count)
        - Tags: \(manifest.tags.count)
        - Photos: \(manifest.photos.count)
        
        ---
        
        *Generated by Baselit. This document is intended to make your data permanently
        accessible regardless of whether the original app remains available.*
        """
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
