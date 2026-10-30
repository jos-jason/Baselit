import Foundation
import SwiftData

@Model
final class Item {
    var name: String
    var itemDescription: String?

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

    /// Append keywords to notes as a comma-separated line, skipping any word
    /// the notes already contain.
    static func notes(_ notes: String?, addingKeywords keywords: [String]) -> String? {
        let existing = notes ?? ""
        var words: [String] = []
        for keyword in keywords where !keyword.isEmpty {
            let alreadyPresent = existing.localizedCaseInsensitiveContains(keyword) ||
                words.contains { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }
            if !alreadyPresent { words.append(keyword) }
        }
        guard !words.isEmpty else { return notes }
        let keywordLine = words.joined(separator: ", ")
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? keywordLine : "\(trimmed)\n\(keywordLine)"
    }
}
