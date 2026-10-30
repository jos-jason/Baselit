import Foundation
import SwiftData

@Model
final class Item {
    var name: String
    var itemDescription: String?

    // Legacy: category and colors are no longer shown or edited. Existing values
    // are moved into notes at launch (see moveLegacyCategoryAndColorsToNotes).
    // Remove these two properties once every device has run that migration.
    var category: ItemCategory?
    var colors: [ItemColor] = []
    var quantity: Int
    var brand: String?
    var model: String?
    var condition: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    var lastLabelPrintedAt: Date?

    /// A persistent two-word identifier (e.g. "Calm River") assigned at creation.
    /// This never changes, even when other item data is edited.
    @Attribute(originalName: "identifier")
    var identifier: String = ""

    // Storage location: either directly in a house, location, or inside a container
    var container: Container?
    var location: Location?
    var house: House?

    @Relationship(deleteRule: .nullify, inverse: \Tag.items)
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \Photo.item)
    var photos: [Photo] = []

    @Relationship(deleteRule: .cascade, inverse: \HomeLocation.item)
    var homeLocations: [HomeLocation] = []

    init(name: String, quantity: Int = 1) {
        self.name = name
        self.quantity = quantity
        self.identifier = IdentifierGenerator.generate()
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Resolve the house this item is in
    var resolvedHouse: House? {
        if let house { return house }
        if let container { return container.resolvedHouse }
        return location?.resolvedHouse
    }

    /// Compute the breadcrumb path components
    var breadcrumbComponents: [String] {
        if let container {
            return container.breadcrumbComponents
        }
        if let location {
            return location.breadcrumbComponents
        }
        if let house {
            return [house.name]
        }
        return ["Unassigned"]
    }

    /// Full breadcrumb path as a string
    var breadcrumbPath: String {
        breadcrumbComponents.joined(separator: " › ")
    }

    /// Move any legacy category and colors into notes as searchable keywords,
    /// then clear them. Returns true if the item changed.
    @discardableResult
    func moveLegacyCategoryAndColorsToNotes() -> Bool {
        guard category != nil || !colors.isEmpty else { return false }
        notes = Item.notes(notes, addingKeywordsFor: category, colors: colors)
        category = nil
        colors = []
        return true
    }

    /// Append a category and colors to notes as a comma-separated keyword line,
    /// skipping any word the notes already contain.
    static func notes(_ notes: String?, addingKeywordsFor category: ItemCategory?, colors: [ItemColor]) -> String? {
        let existing = notes ?? ""
        let words = ([category?.displayName] + colors.map(\.displayName))
            .compactMap { $0 }
            .filter { !existing.localizedCaseInsensitiveContains($0) }
        guard !words.isEmpty else { return notes }
        let keywordLine = words.joined(separator: ", ")
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? keywordLine : "\(trimmed)\n\(keywordLine)"
    }
}
