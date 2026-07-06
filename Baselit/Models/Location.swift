import Foundation
import SwiftData

@Model
final class Location {
    var name: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    /// Direct house reference (only set for top-level locations)
    var house: House?

    /// Self-referential: parent location (nil = top-level)
    var parentLocation: Location?

    @Relationship(deleteRule: .nullify, inverse: \Location.parentLocation)
    var subLocations: [Location] = []

    @Relationship(deleteRule: .nullify, inverse: \Container.location)
    var containers: [Container] = []

    @Relationship(deleteRule: .nullify, inverse: \Item.location)
    var items: [Item] = []

    @Relationship(deleteRule: .cascade, inverse: \Photo.location)
    var photos: [Photo] = []

    init(name: String, house: House? = nil, parentLocation: Location? = nil, notes: String? = nil) {
        self.name = name
        self.house = house
        self.parentLocation = parentLocation
        self.notes = notes
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Walk up the parent chain to find the house
    var resolvedHouse: House? {
        if let house { return house }
        return parentLocation?.resolvedHouse
    }

    /// Compute the breadcrumb path components (including house)
    var breadcrumbComponents: [String] {
        var components: [String] = [name]
        var current = parentLocation
        while let parent = current {
            components.insert(parent.name, at: 0)
            current = parent.parentLocation
        }
        if let house = resolvedHouse {
            components.insert(house.name, at: 0)
        }
        return components
    }

    /// Full breadcrumb path as a string
    var breadcrumbPath: String {
        breadcrumbComponents.joined(separator: " › ")
    }
}
