import Foundation

// MARK: - Top-Level Backup Envelope

struct BackupManifest: Codable {
    let version: Int
    let exportDate: Date
    let includesPhotos: Bool
    let houses: [ExportHouse]
    let locations: [ExportLocation]
    let containers: [ExportContainer]
    let items: [ExportItem]
    let tags: [ExportTag]
    let photos: [ExportPhoto]
    let homeLocations: [ExportHomeLocation]

    /// Backward-compatible decoding: older backups without homeLocations decode to empty array.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportDate = try container.decode(Date.self, forKey: .exportDate)
        includesPhotos = try container.decode(Bool.self, forKey: .includesPhotos)
        houses = try container.decode([ExportHouse].self, forKey: .houses)
        locations = try container.decode([ExportLocation].self, forKey: .locations)
        containers = try container.decode([ExportContainer].self, forKey: .containers)
        items = try container.decode([ExportItem].self, forKey: .items)
        tags = try container.decodeIfPresent([ExportTag].self, forKey: .tags) ?? []
        photos = try container.decode([ExportPhoto].self, forKey: .photos)
        homeLocations = try container.decodeIfPresent([ExportHomeLocation].self, forKey: .homeLocations) ?? []
    }

    init(version: Int, exportDate: Date, includesPhotos: Bool, houses: [ExportHouse], locations: [ExportLocation], containers: [ExportContainer], items: [ExportItem], tags: [ExportTag], photos: [ExportPhoto], homeLocations: [ExportHomeLocation]) {
        self.version = version
        self.exportDate = exportDate
        self.includesPhotos = includesPhotos
        self.houses = houses
        self.locations = locations
        self.containers = containers
        self.items = items
        self.tags = tags
        self.photos = photos
        self.homeLocations = homeLocations
    }
}

// MARK: - Entity DTOs

struct ExportHouse: Codable {
    let exportID: UUID
    let name: String
    let address: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct ExportLocation: Codable {
    let exportID: UUID
    let name: String
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let houseExportID: UUID?
    let parentLocationExportID: UUID?
}

struct ExportContainer: Codable {
    let exportID: UUID
    let name: String
    let containerType: String?
    let notes: String?
    let identifier: String
    let createdAt: Date
    let updatedAt: Date
    let lastLabelPrintedAt: Date?
    let parentContainerExportID: UUID?
    let locationExportID: UUID?
    let houseExportID: UUID?
}

struct ExportItem: Codable {
    let exportID: UUID
    let name: String
    let itemDescription: String?
    /// Legacy: only read from older backups, never written. See `notesWithLegacyKeywords`.
    let category: String?
    let colors: [String]
    let quantity: Int
    let brand: String?
    let model: String?
    let condition: String?
    let notes: String?
    let identifier: String
    let createdAt: Date
    let updatedAt: Date
    let lastLabelPrintedAt: Date?
    let containerExportID: UUID?
    let locationExportID: UUID?
    let houseExportID: UUID?
    /// Legacy: always written empty. Older backups' tags are folded into notes on import.
    let tagExportIDs: [UUID]

    /// Backward-compatible decoding: reads new `colors` array or falls back to old `color` string.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportID = try container.decode(UUID.self, forKey: .exportID)
        name = try container.decode(String.self, forKey: .name)
        itemDescription = try container.decodeIfPresent(String.self, forKey: .itemDescription)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        quantity = try container.decode(Int.self, forKey: .quantity)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        condition = try container.decodeIfPresent(String.self, forKey: .condition)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        identifier = try container.decode(String.self, forKey: .identifier)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastLabelPrintedAt = try container.decodeIfPresent(Date.self, forKey: .lastLabelPrintedAt)
        containerExportID = try container.decodeIfPresent(UUID.self, forKey: .containerExportID)
        locationExportID = try container.decodeIfPresent(UUID.self, forKey: .locationExportID)
        houseExportID = try container.decodeIfPresent(UUID.self, forKey: .houseExportID)
        tagExportIDs = try container.decodeIfPresent([UUID].self, forKey: .tagExportIDs) ?? []

        // Try new "colors" array first, fall back to old "color" single string
        if let colorsArray = try container.decodeIfPresent([String].self, forKey: .colors) {
            colors = colorsArray
        } else if let singleColor = try container.decodeIfPresent(String.self, forKey: .legacyColor) {
            colors = [singleColor]
        } else {
            colors = []
        }
    }

    init(exportID: UUID, name: String, itemDescription: String?, quantity: Int, brand: String?, model: String?, condition: String?, notes: String?, identifier: String, createdAt: Date, updatedAt: Date, lastLabelPrintedAt: Date?, containerExportID: UUID?, locationExportID: UUID?, houseExportID: UUID?) {
        self.exportID = exportID
        self.name = name
        self.itemDescription = itemDescription
        self.category = nil
        self.colors = []
        self.quantity = quantity
        self.brand = brand
        self.model = model
        self.condition = condition
        self.notes = notes
        self.identifier = identifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastLabelPrintedAt = lastLabelPrintedAt
        self.containerExportID = containerExportID
        self.locationExportID = locationExportID
        self.houseExportID = houseExportID
        self.tagExportIDs = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportID, forKey: .exportID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(itemDescription, forKey: .itemDescription)
        try container.encode(quantity, forKey: .quantity)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(identifier, forKey: .identifier)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(lastLabelPrintedAt, forKey: .lastLabelPrintedAt)
        try container.encodeIfPresent(containerExportID, forKey: .containerExportID)
        try container.encodeIfPresent(locationExportID, forKey: .locationExportID)
        try container.encodeIfPresent(houseExportID, forKey: .houseExportID)
        try container.encode(tagExportIDs, forKey: .tagExportIDs)
    }

    /// Notes with any category, colors, and tags from an older backup appended as keywords
    func notesWithLegacyKeywords(tags: [ExportTag]) -> String? {
        let tagNames = tagExportIDs.compactMap { id in tags.first(where: { $0.exportID == id })?.name }
        let keywords = [category].compactMap { $0 } + colors
        return Item.notes(notes, addingKeywords: keywords.map(\.capitalized) + tagNames)
    }

    private enum CodingKeys: String, CodingKey {
        case exportID, name, itemDescription, category, colors
        case quantity, brand, model, condition, notes, identifier
        case createdAt, updatedAt, lastLabelPrintedAt, containerExportID, locationExportID
        case houseExportID, tagExportIDs
        case legacyColor = "color"
    }
}

struct ExportTag: Codable {
    let exportID: UUID
    let name: String
}

struct ExportHomeLocation: Codable {
    let exportID: UUID
    let createdAt: Date
    let updatedAt: Date
    let houseExportID: UUID
    let locationExportID: UUID?
    let containerExportID: UUID?
    let itemExportID: UUID?
    let ownerContainerExportID: UUID?
}

struct ExportPhoto: Codable {
    let exportID: UUID
    let filename: String
    let caption: String?
    let createdAt: Date
    let sortOrder: Int
    let houseExportID: UUID?
    let locationExportID: UUID?
    let containerExportID: UUID?
    let itemExportID: UUID?

    /// Backward-compatible decoding: older backups without sortOrder decode to 0.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exportID = try container.decode(UUID.self, forKey: .exportID)
        filename = try container.decode(String.self, forKey: .filename)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        houseExportID = try container.decodeIfPresent(UUID.self, forKey: .houseExportID)
        locationExportID = try container.decodeIfPresent(UUID.self, forKey: .locationExportID)
        containerExportID = try container.decodeIfPresent(UUID.self, forKey: .containerExportID)
        itemExportID = try container.decodeIfPresent(UUID.self, forKey: .itemExportID)
    }

    init(exportID: UUID, filename: String, caption: String?, createdAt: Date, sortOrder: Int, houseExportID: UUID?, locationExportID: UUID?, containerExportID: UUID?, itemExportID: UUID?) {
        self.exportID = exportID
        self.filename = filename
        self.caption = caption
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.houseExportID = houseExportID
        self.locationExportID = locationExportID
        self.containerExportID = containerExportID
        self.itemExportID = itemExportID
    }
}

// MARK: - Import Support Types

enum ImportMode {
    case replaceAll
    case importNonDuplicates
    case reviewConflicts
}

enum ConflictEntityType: String, Codable {
    case house, location, container, item
}

struct PropertyDifference: Identifiable {
    let id = UUID()
    let propertyName: String
    let existingValue: String
    let incomingValue: String
}

struct ImportConflict: Identifiable {
    let id = UUID()
    let entityType: ConflictEntityType
    let entityName: String
    let identifier: String
    let differences: [PropertyDifference]
    let existingEntityID: Any
    let incomingExportID: UUID
}

enum ConflictResolution {
    case keepExisting
    case replaceWithImport
    case keepBoth
}

struct ImportResult {
    var housesImported: Int = 0
    var locationsImported: Int = 0
    var containersImported: Int = 0
    var itemsImported: Int = 0
    var photosImported: Int = 0
    var homeLocationsImported: Int = 0
    var skipped: Int = 0
    var conflicts: Int = 0
}
