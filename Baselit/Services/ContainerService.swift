import Foundation
import SwiftData

enum ContainerError: LocalizedError {
    case circularReference

    var errorDescription: String? {
        switch self {
        case .circularReference:
            return "Cannot move a container into itself or one of its children."
        }
    }
}

struct ContainerService {

    /// Checks if making `container` a child of `newParent` would create a cycle
    static func wouldCreateCycle(container: Container, newParent: Container?) -> Bool {
        guard let newParent else { return false }
        var current: Container? = newParent
        while let c = current {
            if c.persistentModelID == container.persistentModelID { return true }
            current = c.parentContainer
        }
        return false
    }

    /// Move a container to a new parent container
    static func moveContainer(
        _ container: Container,
        toParent newParent: Container?,
        inLocation location: Location?
    ) throws {
        if let newParent {
            guard !wouldCreateCycle(container: container, newParent: newParent) else {
                throw ContainerError.circularReference
            }
            container.parentContainer = newParent
            container.location = nil
        } else {
            container.parentContainer = nil
            container.location = location
        }
        container.updatedAt = .now
    }

    /// Move an item to a different container or location
    static func moveItem(
        _ item: Item,
        toContainer container: Container?,
        toLocation location: Location?
    ) {
        item.container = container
        item.location = container == nil ? location : nil
        item.updatedAt = .now
    }
}
