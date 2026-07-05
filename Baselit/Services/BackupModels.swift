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
}

struct ExportContainer: Codable {
    let exportID: UUID
    let name: String
    let containerType: String?
    let notes: String?
    let identifier: String
    let createdAt: Date
    let updatedAt: Date
    let parentContainerExportID: UUID?
    let locationExportID: UUID?
}

struct ExportItem: Codable {
    let exportID: UUID
    let name: String
    let itemDescription: String?
    let category: String?
    let color: String?
    let quantity: Int
    let brand: String?
    let model: String?
    let condition: String?
    let notes: String?
    let identifier: String
    let createdAt: Date
    let updatedAt: Date
    let containerExportID: UUID?
    let locationExportID: UUID?
    let tagExportIDs: [UUID]
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
