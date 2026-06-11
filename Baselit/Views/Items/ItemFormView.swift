import SwiftUI
import SwiftData

struct ItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // If editing an existing item
    var editingItem: Item?

    // If creating a new item in a specific location or container
    var location: Location?
    var container: Container?

    @State private var name = ""
    @State private var itemDescription = ""
    @State private var category: ItemCategory?
    @State private var color: ItemColor?
    @State private var quantity = 1
    @State private var brand = ""
    @State private var model = ""
    @State private var condition = ""
    @State private var notes = ""
    @State private var selectedTags: [Tag] = []
    @State private var showOptionalFields = false

    private var isEditing: Bool { editingItem != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Item name", text: $name)
                TextField("Description", text: $itemDescription)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
            }

            Section("Classification") {
                Picker("Category", selection: $category) {
                    Text("None").tag(nil as ItemCategory?)
                    ForEach(ItemCategory.allCases) { cat in
                        Text(cat.displayName).tag(cat as ItemCategory?)
                    }
                }
                Picker("Color", selection: $color) {
                    Text("None").tag(nil as ItemColor?)
                    ForEach(ItemColor.allCases) { c in
                        Text(c.displayName).tag(c as ItemColor?)
                    }
                }
            }

            Section("Tags") {
                TagPicker(selectedTags: $selectedTags)
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Optional fields behind a disclosure
            Section {
                DisclosureGroup("More Details", isExpanded: $showOptionalFields) {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $model)
                    TextField("Condition", text: $condition)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Item" : "New Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let item = editingItem {
                populateFrom(item)
            }
        }
    }

    private func populateFrom(_ item: Item) {
        name = item.name
        itemDescription = item.itemDescription ?? ""
        category = item.category
        color = item.color
        quantity = item.quantity
        brand = item.brand ?? ""
        model = item.model ?? ""
        condition = item.condition ?? ""
        notes = item.notes ?? ""
        selectedTags = item.tags
        if !brand.isEmpty || !model.isEmpty || !condition.isEmpty {
            showOptionalFields = true
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let item: Item
        if let existing = editingItem {
            item = existing
        } else {
            item = Item(name: trimmedName)
            modelContext.insert(item)
            // Set location
            if let container {
                item.container = container
                item.location = nil
            } else if let location {
                item.location = location
                item.container = nil
            }
        }

        item.name = trimmedName
        item.itemDescription = itemDescription.isEmpty ? nil : itemDescription
        item.category = category
        item.color = color
        item.quantity = quantity
        item.brand = brand.isEmpty ? nil : brand
        item.model = model.isEmpty ? nil : model
        item.condition = condition.isEmpty ? nil : condition
        item.notes = notes.isEmpty ? nil : notes
        item.tags = selectedTags
        item.updatedAt = .now

        dismiss()
    }
}
