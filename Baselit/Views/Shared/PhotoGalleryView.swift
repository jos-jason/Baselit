import SwiftUI
import PhotosUI
import SwiftData

/// Displays a horizontal scrollable gallery of photos with the ability to add and delete.
struct PhotoGalleryView: View {
    @Binding var photos: [Photo]
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var fullScreenPhoto: Photo?
    @State private var photoToDelete: Photo?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(photos.sorted(by: { $0.createdAt < $1.createdAt })) { photo in
                            if let data = photo.imageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        fullScreenPhoto = photo
                                    }
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            photoToDelete = photo
                                        } label: {
                                            Label("Delete Photo", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Add Photo", systemImage: "photo.badge.plus")
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        // Downscale to save storage
                        let compressed = compressImage(data: data, maxDimension: 1200)
                        let photo = Photo(imageData: compressed)
                        modelContext.insert(photo)
                        photos.append(photo)
                    }
                    selectedPhotoItem = nil
                }
            }
        }
        .fullScreenCover(item: $fullScreenPhoto) { photo in
            FullScreenPhotoView(photo: photo)
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(
                get: { photoToDelete != nil },
                set: { if !$0 { photoToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let photo = photoToDelete {
                    photos.removeAll { $0.persistentModelID == photo.persistentModelID }
                    modelContext.delete(photo)
                    photoToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                photoToDelete = nil
            }
        }
    }

    private func compressImage(data: Data, maxDimension: CGFloat) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        let scale: CGFloat
        if size.width > maxDimension || size.height > maxDimension {
            scale = maxDimension / max(size.width, size.height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7) ?? data
    }
}

private struct FullScreenPhotoView: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let data = photo.imageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .tint(.white)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}
