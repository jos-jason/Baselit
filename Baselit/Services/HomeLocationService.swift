import Foundation
import SwiftData

enum HomeLocationError: LocalizedError {
    case duplicateHouse

    var errorDescription: String? {
        switch self {
        case .duplicateHouse:
            return "A home location for this house already exists."
        }
    }
}

struct HomeLocationService {

    /// Add a home location for an item, enforcing one-per-house
    static func addHomeLocation(
        for item: Item,
        house: House,
        location: Location?,
        container: Container?,
        context: ModelContext
    ) throws {
        guard !item.homeLocations.contains(where: {
            $0.house?.persistentModelID == house.persistentModelID
        }) else {
            throw HomeLocationError.duplicateHouse
        }

        let hl = HomeLocation(house: house)
        hl.location = location
        hl.container = container
        hl.item = item
        context.insert(hl)
    }

    /// Add a home location for a container, enforcing one-per-house
    static func addHomeLocation(
        for ownerContainer: Container,
        house: House,
        location: Location?,
        targetContainer: Container?,
        context: ModelContext
    ) throws {
        guard !ownerContainer.homeLocations.contains(where: {
            $0.house?.persistentModelID == house.persistentModelID
        }) else {
            throw HomeLocationError.duplicateHouse
        }

        let hl = HomeLocation(house: house)
        hl.location = location
        hl.container = targetContainer
        hl.ownerContainer = ownerContainer
        context.insert(hl)
    }

    /// Remove a home location
    static func removeHomeLocation(_ homeLocation: HomeLocation, context: ModelContext) {
        context.delete(homeLocation)
    }
}
