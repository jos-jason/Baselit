import Foundation

struct PathService {

    /// Build a full breadcrumb path for an item
    static func breadcrumb(for item: Item) -> [String] {
        if let container = item.container {
            return breadcrumb(for: container)
        }
        if let location = item.location {
            var path = [location.name]
            if let house = location.house {
                path.insert(house.name, at: 0)
            }
            return path
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
        let location = container.resolvedLocation
        if let location {
            components.insert(location.name, at: 0)
            if let house = location.house {
                components.insert(house.name, at: 0)
            }
        }
        return components
    }

    /// Format breadcrumb components into a display string
    static func formatPath(_ components: [String]) -> String {
        components.joined(separator: " › ")
    }
}
