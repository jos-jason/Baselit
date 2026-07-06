import Foundation

struct PathService {

    /// Build a full breadcrumb path for an item
    static func breadcrumb(for item: Item) -> [String] {
        if let container = item.container {
            return breadcrumb(for: container)
        }
        if let location = item.location {
            return location.breadcrumbComponents
        }
        return ["Unassigned"]
    }

    /// Build a full breadcrumb path for a container
    static func breadcrumb(for container: Container) -> [String] {
        var components: [String] = [container.name]
        var current = container.parentContainer
        while let parent = current {
            components.insert(parent.name, at: 0)
            current = parent.parentContainer
        }
        if let location = container.resolvedLocation {
            let locComponents = location.breadcrumbComponents
            components.insert(contentsOf: locComponents, at: 0)
        }
        return components
    }

    /// Format breadcrumb components into a display string
    static func formatPath(_ components: [String]) -> String {
        components.joined(separator: " › ")
    }
}
