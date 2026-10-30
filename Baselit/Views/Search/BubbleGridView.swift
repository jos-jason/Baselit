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

extension BubbleEntry {
    /// When the underlying item or container was created; sets its slot in the grid.
    var createdAt: Date {
        switch destination {
        case .item(let item): return item.createdAt
        case .container(let container): return container.createdAt
        }
    }
}

// MARK: - Honeycomb layout

/// Axial hex coordinates for the first `count` slots, spiraling outward ring by
/// ring from the center, like the Apple Watch app grid. Slot `i` is always in
/// the same place, so adding entries only fills new slots on the outside.
private func honeycombSlots(count: Int) -> [(q: Int, r: Int)] {
    guard count > 0 else { return [] }
    let directions = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]
    var slots: [(q: Int, r: Int)] = [(0, 0)]
    var ring = 1
    while slots.count < count {
        var q = directions[4].0 * ring
        var r = directions[4].1 * ring
        for direction in directions {
            for _ in 0..<ring where slots.count < count {
                slots.append((q, r))
                q += direction.0
                r += direction.1
            }
        }
        ring += 1
    }
    return slots
}

/// Interactive honeycomb bubble grid inspired by the Apple Watch app grid.
///
/// Entries sit on a flat hexagonal grid with fixed spacing, ordered oldest
/// first from the center outward. Dragging pans the grid with momentum. Bubbles
/// shrink and pull inward near the edges of the view, which gives the grid its
/// rounded look without ever changing the spacing between neighbors.
struct BubbleGridView: View {
    let entries: [BubbleEntry]
    let onSelect: (BubbleEntry.Destination) -> Void

    // MARK: - Layout constants

    /// Bubble diameter in the middle of the view.
    private let baseBubbleSize: CGFloat = 88
    /// Distance between neighboring bubble centers (leaves a 16pt gap).
    private let slotSpacing: CGFloat = 104
    /// Normalized distance from the view center where bubbles start to shrink
    /// (1.0 is the edge of the view along that axis).
    private let fisheyeStart: Double = 0.55
    /// Normalized distance where bubbles reach their smallest size.
    private let fisheyeEnd: Double = 1.15
    /// Smallest scale at the edge; bubbles below `hiddenScale` aren't drawn.
    private let minimumScale: Double = 0.2
    private let hiddenScale: Double = 0.22
    /// How much bubbles past `fisheyeStart` are pulled back toward the center.
    private let edgeCompression: Double = 0.35

    // MARK: - Physics constants

    /// Fraction of velocity retained each frame at 60fps.
    private let friction: Double = 0.93
    /// How strongly the grid is pulled back when panned past its edge.
    private let boundsSpring: Double = 0.15
    /// Where the outermost row stops, as a normalized distance from the view
    /// center. After the edge shrink, 0.9 lands it just inside the view's edge.
    private let edgeReach: Double = 0.9
    /// How far past the edge a drag can stretch, as a fraction of the half view size.
    private let overscrollReach: Double = 0.25
    /// Below this speed (points per second) momentum stops.
    private let velocityEpsilon: Double = 5

    // MARK: - State

    /// How far the grid is panned from its center, in points.
    @State private var pan: CGSize = .zero
    /// Pan at the start of the current drag.
    @State private var panAtDragStart: CGSize? = nil
    /// Momentum velocity in points per second.
    @State private var velocity: CGSize = .zero
    @State private var isAnimating = false
    @State private var lastFrameTime: Date? = nil
    /// Size of the grid's view, used to work out how far it can be panned.
    @State private var viewSize: CGSize = .zero

    /// Entries in slot order: oldest first, with id as a tiebreaker.
    private var orderedEntries: [BubbleEntry] {
        entries.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            GeometryReader { geometry in
                let laidOut = layout(in: geometry.size)

                ZStack {
                    ForEach(laidOut, id: \.entry.id) { bubble in
                        BubbleView(
                            entry: bubble.entry,
                            size: baseBubbleSize * bubble.scale,
                            maxSize: baseBubbleSize
                        )
                        .position(bubble.position)
                        .zIndex(bubble.scale)
                        .allowsHitTesting(bubble.scale > 0.4)
                        .onTapGesture {
                            onSelect(bubble.entry.destination)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .onAppear { viewSize = geometry.size }
                .onChange(of: geometry.size) { _, newSize in viewSize = newSize }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isAnimating = false
                            let start = panAtDragStart ?? pan
                            panAtDragStart = start
                            let bounds = panBounds
                            pan = CGSize(
                                width: rubberBand(start.width - value.translation.width,
                                                  within: bounds.x, stretch: viewSize.width / 2),
                                height: rubberBand(start.height - value.translation.height,
                                                   within: bounds.y, stretch: viewSize.height / 2)
                            )
                        }
                        .onEnded { value in
                            panAtDragStart = nil
                            velocity = CGSize(width: -value.velocity.width, height: -value.velocity.height)
                            lastFrameTime = Date()
                            isAnimating = true
                        }
                )
            }
            .onChange(of: timeline.date) {
                stepAnimation()
            }
        }
        .animation(.spring(duration: 0.35), value: entries.count)
    }

    // MARK: - Layout

    private struct LaidOutBubble {
        let entry: BubbleEntry
        let position: CGPoint
        let scale: CGFloat
    }

    /// Where a slot sits on the flat grid, relative to the center slot.
    private func gridPoint(q: Int, r: Int) -> CGPoint {
        CGPoint(
            x: slotSpacing * (Double(q) + Double(r) / 2),
            y: slotSpacing * (sqrt(3) / 2) * Double(r)
        )
    }

    private func layout(in size: CGSize) -> [LaidOutBubble] {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        guard halfWidth > 0, halfHeight > 0 else { return [] }

        let ordered = orderedEntries
        let slots = honeycombSlots(count: ordered.count)
        var result: [LaidOutBubble] = []
        result.reserveCapacity(ordered.count)

        for (entry, slot) in zip(ordered, slots) {
            let point = gridPoint(q: slot.q, r: slot.r)
            var x = point.x - pan.width
            var y = point.y - pan.height

            // Distance from the view center, normalized per axis so tall and
            // wide views both use their full space
            let distance = hypot(x / halfWidth, y / halfHeight)
            var scale = 1.0
            if distance > fisheyeStart {
                let t = min((distance - fisheyeStart) / (fisheyeEnd - fisheyeStart), 1)
                let eased = t * t * (3 - 2 * t)
                scale = 1 - (1 - minimumScale) * eased
                let compressed = fisheyeStart + (distance - fisheyeStart) * (1 - edgeCompression * eased)
                x *= compressed / distance
                y *= compressed / distance
            }
            guard scale >= hiddenScale else { continue }

            result.append(LaidOutBubble(
                entry: entry,
                position: CGPoint(x: halfWidth + x, y: halfHeight + y),
                scale: scale
            ))
        }
        return result
    }

    // MARK: - Momentum & bounds

    /// How far the grid can be panned along each axis, so scrolling stops when
    /// the outermost row reaches the edge of the view. A grid that already fits
    /// stays centered on its first slot.
    private var panBounds: (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        let points = honeycombSlots(count: entries.count).map { gridPoint(q: $0.q, r: $0.r) }
        guard !points.isEmpty, viewSize.width > 0, viewSize.height > 0 else { return (0...0, 0...0) }

        func range(_ values: [Double], halfSize: Double) -> ClosedRange<Double> {
            let low = (values.min() ?? 0) + edgeReach * halfSize
            let high = (values.max() ?? 0) - edgeReach * halfSize
            return low <= high ? low...high : 0...0
        }
        return (
            range(points.map { Double($0.x) }, halfSize: Double(viewSize.width) / 2),
            range(points.map { Double($0.y) }, halfSize: Double(viewSize.height) / 2)
        )
    }

    /// Lets a drag stretch past `bounds` with growing resistance, like an iOS scroll view.
    private func rubberBand(_ value: Double, within bounds: ClosedRange<Double>, stretch: Double) -> Double {
        let limit = stretch * overscrollReach
        guard limit > 0 else { return min(max(value, bounds.lowerBound), bounds.upperBound) }
        func resist(_ overshoot: Double) -> Double {
            (1 - 1 / (overshoot / limit * 0.55 + 1)) * limit
        }
        if value > bounds.upperBound { return bounds.upperBound + resist(value - bounds.upperBound) }
        if value < bounds.lowerBound { return bounds.lowerBound - resist(bounds.lowerBound - value) }
        return value
    }

    /// Called each animation frame to coast with momentum and settle back
    /// inside the grid's bounds.
    private func stepAnimation() {
        guard isAnimating else { return }
        let now = Date()
        guard let last = lastFrameTime else {
            lastFrameTime = now
            return
        }
        let dt = now.timeIntervalSince(last)
        lastFrameTime = now
        guard dt > 0 && dt < 0.5 else { return }

        let frictionPerFrame = pow(friction, dt * 60)
        let pull = min(boundsSpring * dt * 60, 1)
        let bounds = panBounds

        // Coast along one axis, then pull back inside the bounds if past them.
        // Returns the new position, velocity, and how far it still is outside.
        func step(_ position: Double, _ speed: Double, _ range: ClosedRange<Double>) -> (Double, Double, Double) {
            var speed = speed * frictionPerFrame
            var position = position + speed * dt
            let clamped = min(max(position, range.lowerBound), range.upperBound)
            if position != clamped {
                speed *= 0.6
                position += (clamped - position) * pull
            }
            return (position, speed, abs(position - clamped))
        }

        let (x, velocityX, outsideX) = step(pan.width, velocity.width, bounds.x)
        let (y, velocityY, outsideY) = step(pan.height, velocity.height, bounds.y)
        pan = CGSize(width: x, height: y)
        velocity = CGSize(width: velocityX, height: velocityY)

        if hypot(velocityX, velocityY) < velocityEpsilon && max(outsideX, outsideY) < 0.5 {
            pan = CGSize(
                width: min(max(x, bounds.x.lowerBound), bounds.x.upperBound),
                height: min(max(y, bounds.y.lowerBound), bounds.y.upperBound)
            )
            velocity = .zero
            isAnimating = false
            lastFrameTime = nil
        }
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
        guard let data = entry.photos.min(by: { $0.sortOrder < $1.sortOrder })?.imageData else {
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
