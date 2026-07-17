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
        tagExportIDs = try container.decode([UUID].self, forKey: .tagExportIDs)

        // Try new "colors" array first, fall back to old "color" single string
        if let colorsArray = try container.decodeIfPresent([String].self, forKey: .colors) {
            colors = colorsArray
        } else if let singleColor = try container.decodeIfPresent(String.self, forKey: .legacyColor) {
            colors = [singleColor]
        } else {
            colors = []
        }
    }

    init(exportID: UUID, name: String, itemDescription: String?, category: String?, colors: [String], quantity: Int, brand: String?, model: String?, condition: String?, notes: String?, identifier: String, createdAt: Date, updatedAt: Date, lastLabelPrintedAt: Date?, containerExportID: UUID?, locationExportID: UUID?, houseExportID: UUID?, tagExportIDs: [UUID]) {
        self.exportID = exportID
        self.name = name
        self.itemDescription = itemDescription
        self.category = category
        self.colors = colors
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
        self.tagExportIDs = tagExportIDs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportID, forKey: .exportID)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(itemDescription, forKey: .itemDescription)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(colors, forKey: .colors)
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

struct ExportPhoto: Codable {
    let exportID: UUID
    let filename: String
    let caption: String?
    let createdAt: Date
    let houseExportID: UUID?
    let locationExportID: UUID?
    let containerExportID: UUID?
    let itemExportID: UUID?
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
    var tagsImported: Int = 0
    var photosImported: Int = 0
    var skipped: Int = 0
    var conflicts: Int = 0
}
