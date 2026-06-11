import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            // Breadcrumb
            Section {
                BreadcrumbView(components: item.breadcrumbComponents)
            }

            // Main info
            Section("Details") {
                if let description = item.itemDescription, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                if let category = item.category {
                    LabeledContent("Category", value: category.displayName)
                }
                if let color = item.color {
                    LabeledContent("Color", value: color.displayName)
                }
                if item.quantity > 1 {
                    LabeledContent("Quantity", value: "\(item.quantity)")
                }
                if let brand = item.brand, !brand.isEmpty {
                    LabeledContent("Brand", value: brand)
                }
                if let model = item.model, !model.isEmpty {
                    LabeledContent("Model", value: model)
                }
                if let condition = item.condition, !condition.isEmpty {
                    LabeledContent("Condition", value: condition)
                }
            }

            // Tags
            if !item.tags.isEmpty {
                Section("Tags") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(item.tags.sorted(by: { $0.name < $1.name })) { tag in
                                Text(tag.name)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.fill.tertiary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            // Notes
            if let notes = item.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            // Stored in
            Section("Stored In") {
                Text(item.breadcrumbPath)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Actions
            Section {
                Button {
                    showMoveSheet = true
                } label: {
                    Label("Move Item", systemImage: "arrow.right")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            }
        }
        .navigationTitle(item.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                ItemFormView(editingItem: item)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            NavigationStack {
                MoveItemView(item: item)
            }
        }
        .confirmationDialog(
            "Delete \(item.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this item.")
        }
    }
}
