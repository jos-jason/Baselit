import SwiftUI
import PhotosUI
import SwiftData

/// Displays a horizontal scrollable gallery of photos with the ability to add and delete.
/// Uses callbacks instead of @Binding to avoid SwiftData @Relationship mutation crashes.
struct PhotoGalleryView: View {
    var photos: [Photo]
    var onAdd: (Photo) -> Void
    var onDelete: (Photo) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var fullScreenPhoto: Photo?
    @State private var photoToDelete: Photo?
    @State private var showCamera = false
    @State private var isProcessing = false

    private static let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(photos.sorted(by: { $0.createdAt < $1.createdAt })) { photo in
                            GalleryThumbnail(photo: photo)
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

            // PhotosPicker as an inline button — manages its own presentation,
            // so no isPresented binding or .photosPicker() modifier needed.
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label(isProcessing ? "Adding…" : "Choose Photo", systemImage: "photo.badge.plus")
            }
            .disabled(isProcessing)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                selectedPhotoItem = nil
                addFromPicker(item: newItem)
            }

            if Self.cameraAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                // Camera sheet attached to this button specifically
                .sheet(isPresented: $showCamera) {
                    CameraView { capturedImage in
                        let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                        compressAndAdd(data: data)
                    }
                }
            }
        }
        // fullScreenCover on the outer VStack — no conflict since PhotosPicker
        // manages its own presentation and camera sheet is on the button.
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
                    onDelete(photo)
                    modelContext.delete(photo)
                    photoToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                photoToDelete = nil
            }
        }
    }

    private func addFromPicker(item: PhotosPickerItem) {
        isProcessing = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                compressAndAdd(data: data)
            }
            isProcessing = false
        }
    }

    /// Compresses image data on a background thread, then inserts the photo on the main actor.
    private func compressAndAdd(data: Data) {
        let context = modelContext
        let addCallback = onAdd
        Task.detached {
            let compressed = compressImage(data: data, maxDimension: 1200)
            await MainActor.run {
                let photo = Photo(imageData: compressed)
                context.insert(photo)
                addCallback(photo)
            }
        }
    }
}

/// Compresses image data to a max dimension. Safe to call from any thread.
private func compressImage(data: Data, maxDimension: CGFloat) -> Data {
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
    let uiImage = UIImage(cgImage: cgImage)
    return uiImage.jpegData(compressionQuality: 0.7) ?? data
}

/// Downsamples image data to a target pixel size. Safe to call from any thread.
private func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
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

/// Loads a 120×120 gallery thumbnail asynchronously to avoid decoding full images on the main thread.
private struct GalleryThumbnail: View {
    let photo: Photo
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
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear { loadImage() }
    }

    private func loadImage() {
        guard let data = photo.imageData else { return }
        let scale = UIScreen.main.scale
        Task.detached {
            let img = downsample(data: data, maxPixelSize: 120 * scale)
            await MainActor.run { image = img }
        }
    }
}

private struct FullScreenPhotoView: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                        .tint(.white)
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
        .onAppear { loadFullImage() }
    }

    private func loadFullImage() {
        guard let data = photo.imageData else { return }
        Task.detached {
            let img = UIImage(data: data)
            await MainActor.run { image = img }
        }
    }
}
