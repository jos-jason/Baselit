import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showCamera = false
    @State private var showShareSheet = false

    var body: some View {
        List {
            // Title
            Section {
                Text(item.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Photos
            Section("Photos") {
                PhotoGalleryView(
                    photos: item.photos,
                    onAdd: { photo in
                        item.photos.append(photo)
                    },
                    onDelete: { photo in
                        item.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
                    },
                    showCamera: $showCamera
                )
            }

            // Breadcrumb & ID
            Section {
                LabeledContent("ID") {
                    Text(item.identifier)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                BreadcrumbView(components: item.breadcrumbComponents)
                if let printedAt = item.lastLabelPrintedAt {
                    LabeledContent("Label Printed") {
                        Text(printedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Main info
            Section("Details") {
                if let description = item.itemDescription, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                if let category = item.category {
                    LabeledContent("Category", value: category.displayName)
                }
                if !item.colors.isEmpty {
                    LabeledContent("Colors") {
                        Text(item.colors.map(\.displayName).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
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
                    showShareSheet = true
                } label: {
                    Label("Print Label", systemImage: "qrcode")
                }

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
        .navigationBarTitleDisplayMode(.inline)
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                let context = modelContext
                Task.detached {
                    let compressed = compressImageForGallery(data: data, maxDimension: 1200)
                    await MainActor.run {
                        let photo = Photo(imageData: compressed)
                        context.insert(photo)
                        item.photos.append(photo)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [
                LabelGenerator.generateLabel(
                    name: item.name,
                    identifier: item.identifier,
                    type: "item"
                )
            ])
            .onAppear {
                item.lastLabelPrintedAt = .now
            }
        }
    }
}
