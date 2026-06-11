import Foundation
import SwiftData

@Model
final class Location {
    var name: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    var house: House?

    @Relationship(deleteRule: .nullify, inverse: \Container.location)
    var containers: [Container] = []

    @Relationship(deleteRule: .nullify, inverse: \Item.location)
    var items: [Item] = []

    init(name: String, house: House, notes: String? = nil) {
        self.name = name
        self.house = house
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }
}
