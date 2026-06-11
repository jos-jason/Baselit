import SwiftUI

/// A small thumbnail that shows the first photo from an array, or a placeholder icon.
struct ThumbnailView: View {
    let photos: [Photo]
    let placeholderIcon: String
    var size: CGFloat = 44

    var body: some View {
        if let data = photos.first?.imageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
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
}
