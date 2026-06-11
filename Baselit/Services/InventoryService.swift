import Foundation
import SwiftData

struct InventoryService {

    // MARK: - Search

    static func searchItems(
        query: String,
        house: House? = nil,
        category: ItemCategory? = nil,
        color: ItemColor? = nil,
        tags: [Tag] = [],
        in context: ModelContext
    ) throws -> [Item] {
        var descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\Item.name)]
        )

        if !query.isEmpty {
            let search = query
            descriptor.predicate = #Predicate<Item> { item in
                item.name.localizedStandardContains(search) ||
                (item.itemDescription ?? "").localizedStandardContains(search) ||
                (item.notes ?? "").localizedStandardContains(search) ||
                (item.brand ?? "").localizedStandardContains(search) ||
                (item.model ?? "").localizedStandardContains(search)
            }
        }

        var results = try context.fetch(descriptor)

        // Post-filter for structured filters
        if let house {
            results = results.filter { $0.resolvedHouse?.persistentModelID == house.persistentModelID }
        }
        if let category {
            results = results.filter { $0.category == category }
        }
        if let color {
            results = results.filter { $0.color == color }
        }
        if !tags.isEmpty {
            let tagNames = Set(tags.map(\.name))
            results = results.filter { item in
                !Set(item.tags.map(\.name)).isDisjoint(with: tagNames)
            }
        }

        return results
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

    static func topLevelContainers(in context: ModelContext) throws -> [Container] {
        let descriptor = FetchDescriptor<Container>(
            predicate: #Predicate<Container> { container in
                container.parentContainer == nil
            },
            sortBy: [SortDescriptor(\Container.name)]
        )
        return try context.fetch(descriptor)
    }
}
