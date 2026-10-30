import Foundation
import SwiftData

/// Represents a "home location" — where an item or container belongs (gets put away)
/// at a specific House. Each item/container can have one HomeLocation per House.
@Model
final class HomeLocation {
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Target path (where the thing belongs)

    /// The house this home location is for (always required)
    var house: House?

    /// Optional deeper location within the house
    var location: Location?

    /// Optional target container within the location
    var container: Container?

    // MARK: - Owner (exactly one of these should be set)

    /// The item that owns this home location (nil if owned by a container)
    var item: Item?

    /// The container that owns this home location (nil if owned by an item)
    var ownerContainer: Container?

    init(house: House) {
        self.house = house
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Compute the breadcrumb path for this home location
    var breadcrumbComponents: [String] {
        var components: [String] = []

        if let house {
            components.append(house.name)
        }

        if let location {
            // Build location chain from top-level down to this location
            var locComponents: [String] = [location.name]
            var current = location.parentLocation
            while let parent = current {
                locComponents.insert(parent.name, at: 0)
                current = parent.parentLocation
            }
            components.append(contentsOf: locComponents)
        }

        if let container {
            // Build container chain from top-level down to this container
            var containerComponents: [String] = [container.name]
            var current = container.parentContainer
            while let parent = current {
                containerComponents.insert(parent.name, at: 0)
                current = parent.parentContainer
            }
            components.append(contentsOf: containerComponents)
        }

        return components
    }

    var breadcrumbPath: String {
        breadcrumbComponents.joined(separator: " › ")
    }

    /// Whether this home points at exactly the given location and container
    func matches(location: Location?, container: Container?) -> Bool {
        self.location?.persistentModelID == location?.persistentModelID &&
        self.container?.persistentModelID == container?.persistentModelID
    }
}
