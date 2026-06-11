import Foundation
import SwiftData

@Model
final class Item {
    var name: String
    var itemDescription: String?
    var category: ItemCategory?
    var color: ItemColor?
    var quantity: Int
    var brand: String?
    var model: String?
    var condition: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    // Storage location: either directly in a location or inside a container
    var container: Container?
    var location: Location?

    @Relationship(deleteRule: .nullify, inverse: \Tag.items)
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \ItemPhoto.item)
    var photos: [ItemPhoto] = []

    init(name: String, quantity: Int = 1) {
        self.name = name
        self.quantity = quantity
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Resolve the house this item is in
    var resolvedHouse: House? {
        if let container { return container.resolvedHouse }
        return location?.house
    }

    /// Compute the breadcrumb path components
    var breadcrumbComponents: [String] {
        if let container {
            return container.breadcrumbComponents
        }
        if let location {
            var path = [location.name]
            if let house = location.house {
                path.insert(house.name, at: 0)
            }
            return path
        }
        return ["Unassigned"]
    }

    /// Full breadcrumb path as a string
    var breadcrumbPath: String {
        breadcrumbComponents.joined(separator: " › ")
    }
}
