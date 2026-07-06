import SwiftUI
import SwiftData
import PhotosUI

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
    @State private var selectedPhotos: [Photo] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isProcessingPhoto = false
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

            Section("Photos") {
                if !selectedPhotos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedPhotos) { photo in
                                FormPhotoThumbnail(photo: photo) {
                                    selectedPhotos.removeAll { $0.persistentModelID == photo.persistentModelID }
                                    modelContext.delete(photo)
                                }
                            }
                        }
                    }
                }

                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label(isProcessingPhoto ? "Adding…" : "Choose Photo", systemImage: "photo.badge.plus")
                }
                .disabled(isProcessingPhoto)
                .onChange(of: photoPickerItem) { _, newItem in
                    guard let newItem else { return }
                    photoPickerItem = nil
                    addFromPicker(item: newItem)
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                compressAndAddPhoto(data: data)
            }
            .ignoresSafeArea()
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
        selectedPhotos = item.photos
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
        item.photos = selectedPhotos
        item.updatedAt = .now

        dismiss()
    }

    private func addFromPicker(item: PhotosPickerItem) {
        isProcessingPhoto = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                compressAndAddPhoto(data: data)
            }
            isProcessingPhoto = false
        }
    }

    /// Compresses image data on a background thread, then adds the photo on the main actor.
    private func compressAndAddPhoto(data: Data) {
        let context = modelContext
        Task.detached {
            let compressed = compressImageData(data: data, maxDimension: 1200)
            await MainActor.run {
                let photo = Photo(imageData: compressed)
                context.insert(photo)
                selectedPhotos.append(photo)
            }
        }
    }
}
/// Compresses image data to a max dimension. Safe to call from any thread.
nonisolated private func compressImageData(data: Data, maxDimension: CGFloat) -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return data
    }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) ?? data
}

/// Downsamples image data to a target pixel size. Safe to call from any thread.
nonisolated private func downsampleForForm(data: Data, maxPixelSize: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: cgImage)
}

/// Async thumbnail for the item form photo strip — avoids decoding full images on the main thread.
private struct FormPhotoThumbnail: View {
    let photo: Photo
    var onDelete: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.fill.quaternary)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.caption)
            }
            .offset(x: 4, y: -4)
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        guard let data = photo.imageData else { return }
        let scale = UIScreen.main.scale  // capture on main thread
        Task.detached {
            let img = downsampleForForm(data: data, maxPixelSize: 80 * scale)
            await MainActor.run { image = img }
        }
    }
}

