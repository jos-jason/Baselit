import SwiftUI
import SwiftData

/// A small thumbnail that shows the first photo from an array, or a placeholder icon.
/// Decodes image data asynchronously to avoid freezing the main thread.
struct ThumbnailView: View {
    let photos: [Photo]
    let placeholderIcon: String
    var size: CGFloat = 44

    @State private var thumbnail: UIImage?

    private var firstPhoto: Photo? {
        photos.min(by: { $0.sortOrder < $1.sortOrder })
    }

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: placeholderIcon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(.fill.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .onChange(of: firstPhoto?.persistentModelID) {
            loadThumbnail()
        }
        .onAppear {
            loadThumbnail()
        }
    }

    /// Extracts imageData on the main actor (where SwiftData models are safe to access),
    /// then dispatches heavy image decoding to a background thread.
    private func loadThumbnail() {
        guard let data = firstPhoto?.imageData else {
            thumbnail = nil
            return
        }
        let scale = UIScreen.main.scale  // capture on main thread
        let targetSize = size * scale
        Task.detached {
            let image = downsample(data: data, maxDimension: targetSize)
            await MainActor.run {
                thumbnail = image
            }
        }
    }
}

/// Downsamples image data to a target size without decoding the full image into memory.
nonisolated private func downsample(data: Data, maxDimension: CGFloat) -> UIImage? {
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
        return nil
    }
    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}
