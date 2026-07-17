import Foundation
import SwiftData

@Model
final class House {
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

    init(name: String, address: String? = nil, notes: String? = nil) {
        self.name = name
        self.address = address
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }
}
