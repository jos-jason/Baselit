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
    private let baseBubbleSize: CGFloat = 78
    /// The smallest a bubble can shrink to at the far edges.
    private let minScale: CGFloat = 0.55
    /// How quickly bubbles shrink toward the edges. Larger = shrinks faster.
    private let falloffRadius: CGFloat = 220
    /// Horizontal distance between adjacent bubble centers.
    private let cellSpacing: CGFloat = 84

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

                    if posX > -baseBubbleSize && posX < geometry.size.width + baseBubbleSize &&
                       posY > -baseBubbleSize && posY < geometry.size.height + baseBubbleSize {
                        BubbleView(
                            entry: entry,
                            size: bubbleSize,
                            maxSize: baseBubbleSize
                        )
                        .position(x: posX, y: posY)
                        .zIndex(Double(1000 - Int(distance)))
                        .onTapGesture {
                            onSelect(entry.destination)
                        }
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
                        offset.width += dragOffset.width
                        offset.height += dragOffset.height
                        dragOffset = .zero
                        isDragging = false

                        // Always spring back to center
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
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

    /// Compute a scale factor (minScale...1.0) based on distance from center.
    /// Uses a cosine curve for a smooth Apple Watch-like falloff.
    private func bubbleScale(distance: CGFloat) -> CGFloat {
        let normalized = min(distance / falloffRadius, 1.0)
        let t = (1.0 + cos(normalized * .pi)) / 2.0
        return minScale + (1.0 - minScale) * t
    }

    /// Generate honeycomb grid positions centered at (0,0).
    /// Fills outward in concentric hexagonal rings so there are never
    /// gaps between placed bubbles — always one tight blob.
    private func honeycombPositions(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }

        let rowHeight = cellSpacing * sqrt(3) / 2

        // Hex directions for traversing each side of a ring.
        // Order: upper-left, left, lower-left, lower-right, right, upper-right
        let directions: [(dx: CGFloat, dy: CGFloat)] = [
            (-cellSpacing * 0.5, -rowHeight),  // upper-left
            (-cellSpacing,        0),           // left
            (-cellSpacing * 0.5,  rowHeight),  // lower-left
            ( cellSpacing * 0.5,  rowHeight),  // lower-right
            ( cellSpacing,        0),           // right
            ( cellSpacing * 0.5, -rowHeight)   // upper-right
        ]

        var positions: [CGPoint] = [.zero]
        if count == 1 { return positions }

        var ring = 1
        while positions.count < count {
            // Start each ring at the position directly to the right of center
            var x = CGFloat(ring) * cellSpacing
            var y: CGFloat = 0

            for (sideIndex, dir) in directions.enumerated() {
                let stepsOnSide = ring
                for step in 0..<stepsOnSide {
                    // Skip the very first position of the first side on step 0
                    // because that's the starting corner we already placed
                    if sideIndex == 0 && step == 0 {
                        positions.append(CGPoint(x: x, y: y))
                        if positions.count >= count {
                            return Array(positions.prefix(count))
                        }
                        // Don't move yet — next iteration will move
                        continue
                    }
                    x += dir.dx
                    y += dir.dy
                    positions.append(CGPoint(x: x, y: y))
                    if positions.count >= count {
                        return Array(positions.prefix(count))
                    }
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
