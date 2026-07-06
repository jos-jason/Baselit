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
    @State private var selectedLocation: Location?
    @State private var selectedParentContainer: Container?
    @State private var selectedPhotos: [Photo] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isProcessingPhoto = false

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    /// Containers available as parents — filtered to the selected location when one is chosen
    private var availableParentContainers: [Container] {
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedPhotos) { photo in
                                AddContainerPhotoThumbnail(photo: photo) {
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

            Section("Location") {
                Picker("House", selection: $selectedHouse) {
                    Text("None").tag(nil as House?)
                    ForEach(houses) { house in
                        Text(house.name).tag(house as House?)
                    }
                }
                .onChange(of: selectedHouse) {
                    selectedLocation = nil
                    selectedParentContainer = nil
                }

                if selectedHouse != nil && !availableLocations.isEmpty {
                    Picker("Location", selection: $selectedLocation) {
                        Text("None").tag(nil as Location?)
                        ForEach(availableLocations) { loc in
                            Text(loc.name).tag(loc as Location?)
                        }
                    }
                    .onChange(of: selectedLocation) {
                        selectedParentContainer = nil
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

    private func addContainer() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let container = Container(
            name: trimmed,
            containerType: containerType.isEmpty ? nil : containerType,
            location: selectedParentContainer != nil ? nil : selectedLocation,
            parentContainer: selectedParentContainer,
            notes: notes.isEmpty ? nil : notes
        )
        container.photos = selectedPhotos
        modelContext.insert(container)
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

    private func compressAndAddPhoto(data: Data) {
        let context = modelContext
        Task.detached {
            let compressed = Self.compressImageData(data: data, maxDimension: 1200)
            await MainActor.run {
                let photo = Photo(imageData: compressed)
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
