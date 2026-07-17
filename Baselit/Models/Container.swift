import Foundation
import SwiftData

@Model
final class Container {
    var name: String
    var containerType: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastLabelPrintedAt: Date?

    /// A persistent two-word identifier (e.g. "Bright Falcon") assigned at creation.
    /// This never changes, even when other container data is edited.
    @Attribute(originalName: "identifier")
    var identifier: String = ""

    // Self-referential: parent container (nil = top-level)
    var parentContainer: Container?

    @Relationship(deleteRule: .nullify, inverse: \Container.parentContainer)
    var subContainers: [Container] = []

    // Location this container is directly in (only for top-level containers)
    var location: Location?

    // House this container is directly in (when no specific location is assigned)
    var house: House?

    @Relationship(deleteRule: .nullify, inverse: \Item.container)
    var items: [Item] = []

    @Relationship(deleteRule: .cascade, inverse: \Photo.container)
    var photos: [Photo] = []

    init(name: String, containerType: String? = nil, location: Location? = nil, parentContainer: Container? = nil, notes: String? = nil) {
        self.name = name
        self.containerType = containerType
        self.location = location
        self.parentContainer = parentContainer
        self.notes = notes
        self.identifier = IdentifierGenerator.generate()
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Walk up the parent chain to find the location (for nested containers)
    var resolvedLocation: Location? {
        if let location { return location }
        return parentContainer?.resolvedLocation
    }

    /// Walk up to find the house
    var resolvedHouse: House? {
        if let house { return house }
        return resolvedLocation?.resolvedHouse ?? parentContainer?.resolvedHouse
    }

    /// Compute the breadcrumb path components
    var breadcrumbComponents: [String] {
        var components: [String] = [name]
        var current = parentContainer
        while let parent = current {
            components.insert(parent.name, at: 0)
            current = parent.parentContainer
        }
        if let loc = resolvedLocation {
            let locComponents = loc.breadcrumbComponents
            components.insert(contentsOf: locComponents, at: 0)
        } else if let house = resolvedHouse {
            components.insert(house.name, at: 0)
        }
        return components
    }

    /// Full breadcrumb path as a string
    var breadcrumbPath: String {
        breadcrumbComponents.joined(separator: " › ")
    }
}
