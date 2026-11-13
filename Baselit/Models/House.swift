import Foundation
import SwiftData

@Model
final class House {
    /// Permanent UUID string shared by every device this record syncs to,
    /// and used as its exportID in backups.
    var syncID: String = UUID().uuidString

    var name: String
    var address: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Location.house)
    var locations: [Location] = []

    @Relationship(deleteRule: .nullify, inverse: \Item.house)
    var items: [Item] = []

    @Relationship(deleteRule: .nullify, inverse: \Container.house)
    var containers: [Container] = []

    @Relationship(deleteRule: .cascade, inverse: \Photo.house)
    var photos: [Photo] = []

    @Relationship(deleteRule: .cascade, inverse: \HomeLocation.house)
    var homeLocations: [HomeLocation] = []

    init(name: String, address: String? = nil, notes: String? = nil) {
        self.name = name
        self.address = address
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }
}
