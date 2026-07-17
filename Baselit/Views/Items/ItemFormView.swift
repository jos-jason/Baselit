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

    @Query(sort: \House.name) private var houses: [House]
    @Query(sort: \Container.name) private var allContainers: [Container]

    @State private var name = ""
    @State private var itemDescription = ""
    @State private var category: ItemCategory?
    @State private var selectedColors: Set<ItemColor> = []
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
    @State private var showMoveSheet = false

    // Location selection state (for create mode)
    @State private var selectedHouse: House?
    @State private var selectedLocation: Location?
    @State private var selectedContainer: Container?

    private var isEditing: Bool { editingItem != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    private var availableContainers: [Container] {
        if let selectedLocation {
            return allContainers.filter {
                $0.resolvedLocation?.persistentModelID == selectedLocation.persistentModelID
            }.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
        }
        if selectedHouse != nil {
            return allContainers.filter {
                $0.resolvedHouse?.persistentModelID == selectedHouse?.persistentModelID
            }.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
        }
        return allContainers.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
    }

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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Colors")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 8) {
                        ForEach(ItemColor.allCases) { color in
                            Button {
                                if selectedColors.contains(color) {
                                    selectedColors.remove(color)
                                } else {
                                    selectedColors.insert(color)
                                }
                            } label: {
                                Text(color.displayName)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(selectedColors.contains(color) ? Color.accentColor : Color(.systemGray5))
                                    .foregroundStyle(selectedColors.contains(color) ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
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

            // Location section — pickers for create mode, move button for edit mode
            if isEditing {
                Section("Location") {
                    if let item = editingItem {
                        LabeledContent("Current Location") {
                            Text(item.breadcrumbPath)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move Item", systemImage: "arrow.right")
                    }
                }
            } else {
                Section("Location") {
                    Picker("House", selection: $selectedHouse) {
                        Text("None").tag(nil as House?)
                        ForEach(houses) { house in
                            Text(house.name).tag(house as House?)
                        }
                    }
                    .onChange(of: selectedHouse) {
                        selectedLocation = nil
                        selectedContainer = nil
                    }

                    if selectedHouse != nil && !availableLocations.isEmpty {
                        Picker("Location", selection: $selectedLocation) {
                            Text("None").tag(nil as Location?)
                            ForEach(availableLocations) { loc in
                                Text(loc.name).tag(loc as Location?)
                            }
                        }
                        .onChange(of: selectedLocation) {
                            selectedContainer = nil
                        }
                    }

                    if !availableContainers.isEmpty {
                        Picker("Container", selection: $selectedContainer) {
                            Text("None (directly in location)").tag(nil as Container?)
                            ForEach(availableContainers) { c in
                                Text(c.name).tag(c as Container?)
                            }
                        }
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
            } else {
                // Pre-populate location selections from passed-in location/container
                if let container {
                    selectedContainer = container
                    selectedLocation = container.resolvedLocation
                    selectedHouse = container.resolvedHouse
                } else if let location {
                    selectedLocation = location
                    selectedHouse = location.resolvedHouse
                }
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            if let item = editingItem {
                NavigationStack {
                    MoveItemView(item: item)
                }
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
        selectedColors = Set(item.colors)
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
            // Set location from pickers
            if let selectedContainer {
                item.container = selectedContainer
                item.location = nil
            } else if let selectedLocation {
                item.location = selectedLocation
                item.container = nil
            }
        }

        item.name = trimmedName
        item.itemDescription = itemDescription.isEmpty ? nil : itemDescription
        item.category = category
        item.colors = Array(selectedColors)
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

/// A simple wrapping flow layout that arranges views horizontally,
/// moving to the next row when content exceeds the available width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}


