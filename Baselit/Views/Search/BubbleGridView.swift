import SwiftUI
import SwiftData

/// A single entry in the bubble grid, wrapping either an Item or a Container.
struct BubbleEntry: Identifiable {
    let id: String
    let name: String
    let photos: [Photo]
    let placeholderIcon: String

    enum Destination: Hashable {
        case item(Item)
        case container(Container)
    }
    let destination: Destination
}

/// Apple Watch-style honeycomb grid that you can drag around.
/// Bubbles scale dynamically based on distance from the visible center.
/// The grid always drifts back to center after releasing.
struct BubbleGridView: View {
    let entries: [BubbleEntry]
    let onSelect: (BubbleEntry.Destination) -> Void

    /// The full size of each bubble at maximum scale (at the center of view).
    private let baseBubbleSize: CGFloat = 88
    /// The smallest a bubble can shrink to at the far edges.
    private let minScale: CGFloat = 0.55
    /// How quickly bubbles shrink toward the edges. Larger = shrinks faster.
    private let falloffRadius: CGFloat = 220
    /// Horizontal distance between adjacent bubble centers.
    private let cellSpacing: CGFloat = 104

    /// Accumulated drag offset for panning the grid.
    @State private var offset: CGSize = .zero
    /// The live drag translation (while finger is down).
    @State private var dragOffset: CGSize = .zero
    /// Whether the user is actively dragging.
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let viewCenter = CGPoint(x: geometry.size.width / 2,
                                     y: geometry.size.height / 2)
            let gridPositions = honeycombPositions(count: entries.count)
            let totalOffset = CGSize(width: offset.width + dragOffset.width,
                                     height: offset.height + dragOffset.height)

            ZStack {
                ForEach(Array(zip(entries.indices, entries)), id: \.1.id) { index, entry in
                    let gridPos = gridPositions[index]
                    let posX = viewCenter.x + gridPos.x + totalOffset.width
                    let posY = viewCenter.y + gridPos.y + totalOffset.height

                    let dx = posX - viewCenter.x
                    let dy = posY - viewCenter.y
                    let distance = hypot(dx, dy)
                    let scale = bubbleScale(distance: distance)
                    let bubbleSize = baseBubbleSize * scale

                    BubbleView(
                        entry: entry,
                        size: bubbleSize,
                        maxSize: baseBubbleSize
                    )
                    .position(x: posX, y: posY)
                    .zIndex(Double(1000 - Int(distance)))
                    .opacity(bubbleOpacity(distance: distance))
                    .onTapGesture {
                        onSelect(entry.destination)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        // Rubber-band: full movement near center, diminishing far out
                        let proposed = CGSize(
                            width: offset.width + value.translation.width,
                            height: offset.height + value.translation.height
                        )
                        let rubberBandLimit = baseBubbleSize * 3
                        dragOffset = CGSize(
                            width: rubberBand(proposed.width, limit: rubberBandLimit) - offset.width,
                            height: rubberBand(proposed.height, limit: rubberBandLimit) - offset.height
                        )
                    }
                    .onEnded { _ in
                        // Merge drag into offset, then animate back smoothly
                        offset.width += dragOffset.width
                        offset.height += dragOffset.height
                        dragOffset = .zero
                        isDragging = false

                        // Smooth, calm spring back to center
                        withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
                            offset = .zero
                        }
                    }
            )
        }
    }

    /// Rubber-band effect: full movement within limit, diminishing beyond.
    private func rubberBand(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        let absVal = abs(value)
        if absVal <= limit {
            return value
        }
        let overshoot = absVal - limit
        let dampened = limit + overshoot * 0.15
        return value > 0 ? dampened : -dampened
    }

    /// Fade out bubbles that are very far from center so they don't just hard-clip.
    private func bubbleOpacity(distance: CGFloat) -> Double {
        let fadeStart = falloffRadius * 1.3
        let fadeEnd = falloffRadius * 2.0
        if distance <= fadeStart { return 1.0 }
        if distance >= fadeEnd { return 0.0 }
        return Double((fadeEnd - distance) / (fadeEnd - fadeStart))
    }

    /// Compute a scale factor (minScale...1.0) based on distance from center.
    /// Uses a cosine curve for a smooth Apple Watch-like falloff.
    private func bubbleScale(distance: CGFloat) -> CGFloat {
        let normalized = min(distance / falloffRadius, 1.0)
        let t = (1.0 + cos(normalized * .pi)) / 2.0
        return minScale + (1.0 - minScale) * t
    }

    /// Generate honeycomb grid positions centered at (0,0).
    /// Uses axial hex coordinates converted to pixel positions.
    /// Fills outward in concentric rings like flower petals.
    private func honeycombPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }

        // Convert axial hex coordinate (q, r) to pixel position.
        // "Pointy-top" orientation so the first ring of 6 surrounds center like petals.
        let size = cellSpacing / 2
        func hexToPixel(q: Int, r: Int) -> CGPoint {
            let x = size * (sqrt(3) * Double(q) + sqrt(3) / 2 * Double(r))
            let y = size * (3.0 / 2.0 * Double(r))
            return CGPoint(x: x, y: y)
        }

        var positions: [CGPoint] = [.zero] // ring 0: center
        if count == 1 { return positions }

        // Axial direction vectors for the 6 sides of a hex ring
        let axialDirections: [(dq: Int, dr: Int)] = [
            ( 0, -1), // side 0: move up
            (-1,  0), // side 1: move upper-left
            (-1,  1), // side 2: move lower-left
            ( 0,  1), // side 3: move down
            ( 1,  0), // side 4: move lower-right
            ( 1, -1)  // side 5: move upper-right
        ]

        var ring = 1
        while positions.count < count {
            // Start at the hex to the lower-right of center: (ring, 0)
            // then walk ring steps along each of the 6 sides
            var q = ring
            var r = 0

            for side in 0..<6 {
                let dir = axialDirections[side]
                for _ in 0..<ring {
                    positions.append(hexToPixel(q: q, r: r))
                    if positions.count >= count {
                        return Array(positions.prefix(count))
                    }
                    q += dir.dq
                    r += dir.dr
                }
            }

            ring += 1
        }

        return Array(positions.prefix(count))
    }
}

/// A single circular bubble showing a thumbnail or placeholder.
private struct BubbleView: View {
    let entry: BubbleEntry
    let size: CGFloat
    let maxSize: CGFloat

    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(.fill.quaternary)
                    Image(systemName: entry.placeholderIcon)
                        .font(.system(size: size * 0.32))
                        .foregroundStyle(.secondary)
                }
                .frame(width: size, height: size)
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        .contentShape(Circle())
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard let data = entry.photos.first?.imageData else {
            thumbnail = nil
            return
        }
        let scale = UIScreen.main.scale
        let targetSize = maxSize * scale
        Task.detached {
            let image = downsampleBubble(data: data, maxDimension: targetSize)
            await MainActor.run {
                thumbnail = image
            }
        }
    }
}

/// Downsamples image data to a target size without decoding the full image.
nonisolated private func downsampleBubble(data: Data, maxDimension: CGFloat) -> UIImage? {
    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
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

/// Full-screen wrapper for presenting the BubbleGridView with navigation support.
struct BubbleGridFullScreenView: View {
    let title: String
    let entries: [BubbleEntry]
    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            BubbleGridView(entries: entries) { destination in
                switch destination {
                case .item(let item):
                    navigationPath.append(item)
                case .container(let container):
                    navigationPath.append(container)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonBorderShape(.circle)
                }
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container)
            }
        }
    }
}
