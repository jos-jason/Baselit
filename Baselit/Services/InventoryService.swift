import Foundation
import SwiftData

struct InventoryService {

    // MARK: - Search

    static func searchItems(
        query: String,
        house: House? = nil,
        tags: [Tag] = [],
        in context: ModelContext
    ) throws -> [Item] {
        let descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\Item.name)]
        )

        var results = try context.fetch(descriptor)

        // Filter by keyword across multiple text fields (in-memory to avoid
        // SwiftData #Predicate crashes with optional string fields)
        if !query.isEmpty {
            results = results.filter { item in
                item.name.localizedCaseInsensitiveContains(query) ||
                (item.itemDescription?.localizedCaseInsensitiveContains(query) ?? false) ||
                (item.notes?.localizedCaseInsensitiveContains(query) ?? false) ||
                (item.brand?.localizedCaseInsensitiveContains(query) ?? false) ||
                (item.model?.localizedCaseInsensitiveContains(query) ?? false) ||
                item.tags.contains(where: { $0.name.localizedCaseInsensitiveContains(query) })
            }
        }

        // Post-filter for structured filters
        if let house {
            results = results.filter { $0.resolvedHouse?.persistentModelID == house.persistentModelID }
        }
        if !tags.isEmpty {
            let tagNames = Set(tags.map(\.name))
            results = results.filter { item in
                !Set(item.tags.map(\.name)).isDisjoint(with: tagNames)
            }
        }

        return results
    }

    // MARK: - Search Houses

    static func searchHouses(query: String, house: House? = nil, in context: ModelContext) throws -> [House] {
        let descriptor = FetchDescriptor<House>(sortBy: [SortDescriptor(\House.name)])
        let all = try context.fetch(descriptor)
        guard !query.isEmpty else { return [] }
        return all.filter { candidate in
            (candidate.name.localizedCaseInsensitiveContains(query) ||
            (candidate.address?.localizedCaseInsensitiveContains(query) ?? false) ||
            (candidate.notes?.localizedCaseInsensitiveContains(query) ?? false)) &&
            (house == nil || candidate.persistentModelID == house?.persistentModelID)
        }
    }

    // MARK: - Search Locations

    static func searchLocations(query: String, house: House? = nil, in context: ModelContext) throws -> [Location] {
        let descriptor = FetchDescriptor<Location>(sortBy: [SortDescriptor(\Location.name)])
        let all = try context.fetch(descriptor)
        guard !query.isEmpty else { return [] }
        return all.filter { location in
            (location.name.localizedCaseInsensitiveContains(query) ||
            (location.notes?.localizedCaseInsensitiveContains(query) ?? false)) &&
            (house == nil || location.resolvedHouse?.persistentModelID == house?.persistentModelID)
        }
    }

    // MARK: - Search Containers

    static func searchContainers(query: String, house: House? = nil, in context: ModelContext) throws -> [Container] {
        let descriptor = FetchDescriptor<Container>(sortBy: [SortDescriptor(\Container.name)])
        let all = try context.fetch(descriptor)
        guard !query.isEmpty else { return [] }
        return all.filter { container in
            (container.name.localizedCaseInsensitiveContains(query) ||
            (container.containerType?.localizedCaseInsensitiveContains(query) ?? false) ||
            (container.notes?.localizedCaseInsensitiveContains(query) ?? false)) &&
            (house == nil || container.resolvedHouse?.persistentModelID == house?.persistentModelID)
        }
    }

    // MARK: - Tag Helpers

    static func findOrCreateTag(name: String, in context: ModelContext) throws -> Tag {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { tag in
                tag.name == trimmed
            }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let tag = Tag(name: trimmed)
        context.insert(tag)
        return tag
    }

    // MARK: - Fetch Helpers

    static func allHouses(in context: ModelContext) throws -> [House] {
        let descriptor = FetchDescriptor<House>(sortBy: [SortDescriptor(\House.name)])
        return try context.fetch(descriptor)
    }

    static func allTags(in context: ModelContext) throws -> [Tag] {
        let descriptor = FetchDescriptor<Tag>(sortBy: [SortDescriptor(\Tag.name)])
        return try context.fetch(descriptor)
    }

    static func allContainers(in context: ModelContext) throws -> [Container] {
        let descriptor = FetchDescriptor<Container>(sortBy: [SortDescriptor(\Container.name)])
        return try context.fetch(descriptor)
    }

    static func allItems(in context: ModelContext) throws -> [Item] {
        let descriptor = FetchDescriptor<Item>(sortBy: [SortDescriptor(\Item.name)])
        return try context.fetch(descriptor)
    }

    static func topLevelContainers(in context: ModelContext) throws -> [Container] {
        let descriptor = FetchDescriptor<Container>(
            predicate: #Predicate<Container> { container in
                container.parentContainer == nil
            },
            sortBy: [SortDescriptor(\Container.name)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: - QR Code Lookup

    /// The result of parsing and looking up a QR code payload.
    enum QRLookupResult {
        case container(Container)
        case item(Item)
        case notFound
        case invalidFormat
    }

    /// Parses a "baselit:type:slug" QR payload and looks up the matching entity.
    static func lookupByQRPayload(
        _ payload: String,
        in context: ModelContext
    ) throws -> QRLookupResult {
        let parts = payload.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0] == "baselit" else {
            return .invalidFormat
        }

        let type = parts[1]
        let slug = parts[2]
        let identifierQuery = slug.replacingOccurrences(of: "-", with: " ")

        switch type {
        case "container":
            let descriptor = FetchDescriptor<Container>()
            let all = try context.fetch(descriptor)
            if let match = all.first(where: {
                $0.identifier.caseInsensitiveCompare(identifierQuery) == .orderedSame
            }) {
                return .container(match)
            }
            return .notFound

        case "item":
            let descriptor = FetchDescriptor<Item>()
            let all = try context.fetch(descriptor)
            if let match = all.first(where: {
                $0.identifier.caseInsensitiveCompare(identifierQuery) == .orderedSame
            }) {
                return .item(match)
            }
            return .notFound

        default:
            return .invalidFormat
        }
    }
}
