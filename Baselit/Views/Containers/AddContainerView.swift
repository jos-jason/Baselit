import SwiftUI
import SwiftData
import PhotosUI

struct AddContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \House.name) private var houses: [House]

    @Query(sort: \Container.name) private var allContainers: [Container]

    @State private var name = ""
    @State private var containerType = ""
    @State private var notes = ""
    @State private var selectedHouse: House?
    /// Cascading location selections: index 0 = top-level, index 1 = sub-location, etc.
    @State private var locationSelections: [Location?] = [nil]
    @State private var selectedParentContainer: Container?
    @State private var selectedPhotos: [Photo] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isProcessingPhoto = false
    @State private var isEditingPhotoOrder = false
    @State private var photoOrderVersion = 0

    /// The deepest selected location across all cascading pickers
    private var deepestSelectedLocation: Location? {
        locationSelections.compactMap { $0 }.last
    }

    /// Top-level locations for the selected house
    private var topLevelLocations: [Location] {
        selectedHouse?.locations
            .filter { $0.parentLocation == nil }
            .sorted(by: { $0.name < $1.name }) ?? []
    }

    /// Sub-locations available at a given depth (children of the selection at depth-1)
    private func subLocations(atDepth depth: Int) -> [Location] {
        guard depth > 0, depth <= locationSelections.count,
              let parent = locationSelections[depth - 1] else { return [] }
        return parent.subLocations.sorted(by: { $0.name < $1.name })
    }

    /// Containers available as parents — filtered to the selected location when one is chosen
    private var availableParentContainers: [Container] {
        if let deepestSelectedLocation {
            return allContainers.filter {
                $0.resolvedLocation?.persistentModelID == deepestSelectedLocation.persistentModelID
            }.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
        }
        if selectedHouse != nil {
            return allContainers.filter {
                $0.resolvedHouse?.persistentModelID == selectedHouse?.persistentModelID
            }.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
        }
        return allContainers.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Container name", text: $name)
            }

            Section("Photos") {
                if !selectedPhotos.isEmpty {
                    if isEditingPhotoOrder {
                        HStack {
                            Text("Reorder Photos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Done") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingPhotoOrder = false
                                }
                            }
                            .font(.subheadline.bold())
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedPhotos.sorted(by: { $0.sortOrder < $1.sortOrder })) { photo in
                                if isEditingPhotoOrder {
                                    editableContainerThumbnail(for: photo)
                                } else {
                                    normalContainerThumbnail(for: photo)
                                }
                            }
                        }
                        .id(photoOrderVersion)
                        .padding(.vertical, isEditingPhotoOrder ? 6 : 0)
                    }
                }

                PhotosPicker(selection: $photoPickerItems, matching: .images) {
                    Label(isProcessingPhoto ? "Adding…" : "Choose Photos", systemImage: "photo.badge.plus")
                }
                .disabled(isProcessingPhoto)
                .onChange(of: photoPickerItems) { _, newItems in
                    guard !newItems.isEmpty else { return }
                    let items = newItems
                    photoPickerItems = []
                    addFromPicker(items: items)
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }
            }

            Section("Location") {
                Picker("House", selection: $selectedHouse) {
                    Text("None").tag(nil as House?)
                    ForEach(houses) { house in
                        Text(house.name).tag(house as House?)
                    }
                }
                .onChange(of: selectedHouse) {
                    locationSelections = [nil]
                    selectedParentContainer = nil
                }

                // Cascading location pickers
                if selectedHouse != nil {
                    locationPicker(atDepth: 0, label: "Location", locations: topLevelLocations)

                    ForEach(1..<locationSelections.count, id: \.self) { depth in
                        let subs = subLocations(atDepth: depth)
                        if !subs.isEmpty {
                            locationPicker(atDepth: depth, label: subLocationLabel(depth: depth), locations: subs)
                        }
                    }
                }

                if !availableParentContainers.isEmpty {
                    Picker("Inside Container", selection: $selectedParentContainer) {
                        Text("None (top level)").tag(nil as Container?)
                        ForEach(availableParentContainers) { container in
                            Text(container.name)
                                .tag(container as Container?)
                        }
                    }
                }
            }

            Section("Details") {
                TextField("Type (e.g. Box, Shelf, Drawer)", text: $containerType)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("New Container")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    addContainer()
                }
                .disabled(!isValid)
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

    /// Build a picker for a specific depth in the location hierarchy
    private func locationPicker(atDepth depth: Int, label: String, locations: [Location]) -> some View {
        let binding = Binding<Location?>(
            get: {
                guard depth < locationSelections.count else { return nil }
                return locationSelections[depth]
            },
            set: { newValue in
                if depth < locationSelections.count {
                    locationSelections[depth] = newValue
                }
                if locationSelections.count > depth + 1 {
                    locationSelections.removeSubrange((depth + 1)...)
                }
                if let loc = newValue, !loc.subLocations.isEmpty {
                    locationSelections.append(nil)
                }
                selectedParentContainer = nil
            }
        )

        return Picker(label, selection: binding) {
            Text(depth == 0 ? "Select location..." : "None").tag(nil as Location?)
            ForEach(locations) { loc in
                Text(loc.name).tag(loc as Location?)
            }
        }
    }

    /// Returns a label like "Sub-location" or "Sub-sub-location" based on depth
    private func subLocationLabel(depth: Int) -> String {
        let prefix = String(repeating: "Sub-", count: depth)
        return prefix + "location"
    }

    private func addContainer() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let container = Container(
            name: trimmed,
            containerType: containerType.isEmpty ? nil : containerType,
            location: selectedParentContainer != nil ? nil : deepestSelectedLocation,
            parentContainer: selectedParentContainer,
            notes: notes.isEmpty ? nil : notes
        )
        // Set house when no location or parent container is selected
        if selectedParentContainer == nil && deepestSelectedLocation == nil {
            container.house = selectedHouse
        }
        container.photos = selectedPhotos
        modelContext.insert(container)
        dismiss()
    }

    @ViewBuilder
    private func normalContainerThumbnail(for photo: Photo) -> some View {
        AddContainerPhotoThumbnail(photo: photo) {
            withAnimation {
                selectedPhotos.removeAll { $0.persistentModelID == photo.persistentModelID }
                modelContext.delete(photo)
            }
        }
        .onLongPressGesture {
            ensureUniquePhotoSortOrders()
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditingPhotoOrder = true
            }
        }
    }

    private func ensureUniquePhotoSortOrders() {
        let sorted = selectedPhotos.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
        for (i, photo) in sorted.enumerated() where photo.sortOrder != i {
            photo.sortOrder = i
        }
        photoOrderVersion += 1
    }

    @ViewBuilder
    private func editableContainerThumbnail(for photo: Photo) -> some View {
        let sorted = selectedPhotos.sorted(by: { $0.sortOrder < $1.sortOrder })
        let index = sorted.firstIndex(where: { $0.persistentModelID == photo.persistentModelID })
        let isFirst = index == sorted.startIndex
        let isLast = index == sorted.index(before: sorted.endIndex)

        AddContainerPhotoThumbnail(photo: photo) {
            withAnimation {
                selectedPhotos.removeAll { $0.persistentModelID == photo.persistentModelID }
                modelContext.delete(photo)
                if selectedPhotos.isEmpty { isEditingPhotoOrder = false }
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                if !isFirst, let index {
                    Button {
                        withAnimation { swapPhotoOrder(sorted[index], sorted[index - 1]) }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                }
                if !isLast, let index {
                    Button {
                        withAnimation { swapPhotoOrder(sorted[index], sorted[index + 1]) }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                }
            }
            .offset(y: -6)
        }
        .jiggleEffect()
    }

    private func swapPhotoOrder(_ a: Photo, _ b: Photo) {
        let temp = a.sortOrder
        a.sortOrder = b.sortOrder
        b.sortOrder = temp
        photoOrderVersion += 1
    }

    private func addFromPicker(items: [PhotosPickerItem]) {
        isProcessingPhoto = true
        let nextSortOrder = (selectedPhotos.map(\.sortOrder).max() ?? -1) + 1
        Task {
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    compressAndAddPhoto(data: data, sortOrder: nextSortOrder + index)
                }
            }
            isProcessingPhoto = false
        }
    }

    private func compressAndAddPhoto(data: Data, sortOrder: Int? = nil) {
        let context = modelContext
        let order = sortOrder ?? ((selectedPhotos.map(\.sortOrder).max() ?? -1) + 1)
        Task.detached {
            let compressed = Self.compressImageData(data: data, maxDimension: 1200)
            await MainActor.run {
                let photo = Photo(imageData: compressed, sortOrder: order)
                context.insert(photo)
                selectedPhotos.append(photo)
            }
        }
    }

    private static nonisolated func compressImageData(data: Data, maxDimension: CGFloat) -> Data {
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

    fileprivate static nonisolated func downsampleImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
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
}

private struct AddContainerPhotoThumbnail: View {
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
        let scale = UIScreen.main.scale
        Task.detached {
            let img = AddContainerView.downsampleImage(data: data, maxPixelSize: 80 * scale)
            await MainActor.run { image = img }
        }
    }
}
