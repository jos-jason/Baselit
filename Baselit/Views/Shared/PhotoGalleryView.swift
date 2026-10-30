import SwiftUI
import PhotosUI
import SwiftData

/// Displays a horizontal scrollable gallery of photos with the ability to add, delete, and reorder.
/// Long-press a thumbnail to enter "jiggle mode" where photos can be reordered and deleted,
/// similar to the iOS home screen app editing mode.
/// Uses callbacks instead of @Binding to avoid SwiftData @Relationship mutation crashes.
struct PhotoGalleryView: View {
    var photos: [Photo]
    var onAdd: (Photo) -> Void
    var onDelete: (Photo) -> Void
    @Binding var showCamera: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var fullScreenPhoto: Photo?
    @State private var isProcessing = false
    @State private var isEditingOrder = false
    @State private var orderVersion = 0

    private static let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    private var sortedPhotos: [Photo] {
        photos.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        Group {
            if !photos.isEmpty {
                photoStrip
                .fullScreenCover(item: $fullScreenPhoto) { photo in
                    FullScreenPhotoView(photo: photo)
                }
            }

            PhotosPicker(selection: $selectedPhotoItems, matching: .images) {
                Label(isProcessing ? "Adding…" : "Choose Photos", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderless)
            .disabled(isProcessing)
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let items = newItems
                selectedPhotoItems = []
                addFromPicker(items: items)
            }

            if Self.cameraAvailable {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var photoStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditingOrder {
                HStack {
                    Text("Reorder Photos")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingOrder = false
                        }
                    }
                    .font(.subheadline.bold())
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(sortedPhotos) { photo in
                        if isEditingOrder {
                            editableThumbnail(for: photo)
                        } else {
                            normalThumbnail(for: photo)
                        }
                    }
                }
                .id(orderVersion)
                .padding(.vertical, isEditingOrder ? 6 : 0)
            }
        }
    }

    @ViewBuilder
    private func normalThumbnail(for photo: Photo) -> some View {
        GalleryThumbnail(photo: photo)
            .onTapGesture {
                fullScreenPhoto = photo
            }
            .onLongPressGesture {
                ensureUniqueSortOrders()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isEditingOrder = true
                }
            }
    }

    /// Ensures every photo has a unique sortOrder before entering edit mode.
    /// Photos that were created before sortOrder existed all default to 0.
    private func ensureUniqueSortOrders() {
        let sorted = photos.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
        for (i, photo) in sorted.enumerated() where photo.sortOrder != i {
            photo.sortOrder = i
        }
        orderVersion += 1
    }

    @ViewBuilder
    private func editableThumbnail(for photo: Photo) -> some View {
        let sorted = sortedPhotos
        let index = sorted.firstIndex(where: { $0.persistentModelID == photo.persistentModelID })
        let isFirst = index == sorted.startIndex
        let isLast = index == sorted.index(before: sorted.endIndex)

        GalleryThumbnail(photo: photo)
            .overlay(alignment: .topTrailing) {
                Button {
                    withAnimation {
                        onDelete(photo)
                        modelContext.delete(photo)
                        if photos.count <= 1 {
                            isEditingOrder = false
                        }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .offset(x: 6, y: -6)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 16) {
                    if !isFirst, let index {
                        Button {
                            withAnimation { swapOrder(sorted[index], sorted[index - 1]) }
                        } label: {
                            Image(systemName: "chevron.left.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                    }
                    if !isLast, let index {
                        Button {
                            withAnimation { swapOrder(sorted[index], sorted[index + 1]) }
                        } label: {
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                    }
                }
                .offset(y: -8)
            }
            .jiggleEffect()
    }

    private func swapOrder(_ a: Photo, _ b: Photo) {
        let temp = a.sortOrder
        a.sortOrder = b.sortOrder
        b.sortOrder = temp
        orderVersion += 1
    }

    private func addFromPicker(items: [PhotosPickerItem]) {
        isProcessing = true
        let nextSortOrder = (photos.map(\.sortOrder).max() ?? -1) + 1
        Task {
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    compressAndAdd(data: data, sortOrder: nextSortOrder + index)
                }
            }
            isProcessing = false
        }
    }

    /// Compresses image data on a background thread, then inserts the photo on the main actor.
    private func compressAndAdd(data: Data, sortOrder: Int) {
        let context = modelContext
        let addCallback = onAdd
        Task.detached {
            let compressed = compressImageForGallery(data: data, maxDimension: 1200)
            await MainActor.run {
                let photo = Photo(imageData: compressed, sortOrder: sortOrder)
                context.insert(photo)
                addCallback(photo)
            }
        }
    }
}

/// A jiggle animation modifier that mimics the iOS home screen editing wobble.
struct JiggleModifier: ViewModifier {
    @State private var isJiggling = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isJiggling ? -1.5 : 1.5))
            .animation(
                .easeInOut(duration: 0.12)
                .repeatForever(autoreverses: true),
                value: isJiggling
            )
            .onAppear { isJiggling = true }
    }
}

extension View {
    func jiggleEffect() -> some View {
        modifier(JiggleModifier())
    }
}

/// Compresses image data to a max dimension. Safe to call from any thread.
nonisolated func compressImageForGallery(data: Data, maxDimension: CGFloat) -> Data {
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
nonisolated private func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
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
