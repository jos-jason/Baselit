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
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isAnimating = false
                            let start = panAtDragStart ?? pan
                            panAtDragStart = start
                            pan = CGSize(
                                width: start.width - value.translation.width,
                                height: start.height - value.translation.height
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

    /// How far the grid can be panned: one ring short of the outermost slot, so
    /// the edge of the grid stays near the edge of the view.
    private var panLimit: Double {
        let farthestSlot = honeycombSlots(count: entries.count)
            .map { slot in
                let point = gridPoint(q: slot.q, r: slot.r)
                return hypot(point.x, point.y)
            }
            .max() ?? 0
        return max(0, farthestSlot - slotSpacing)
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
        velocity = CGSize(width: velocity.width * frictionPerFrame, height: velocity.height * frictionPerFrame)
        var newPan = CGSize(
            width: pan.width + velocity.width * dt,
            height: pan.height + velocity.height * dt
        )

        // Pull back inside the grid when panned past its outer ring
        let limit = panLimit
        let distance = hypot(newPan.width, newPan.height)
        var outOfBounds = false
        if distance > limit {
            outOfBounds = true
            let pull = min(boundsSpring * dt * 60, 1)
            let target = CGSize(width: newPan.width / distance * limit, height: newPan.height / distance * limit)
            newPan.width += (target.width - newPan.width) * pull
            newPan.height += (target.height - newPan.height) * pull
            velocity = CGSize(width: velocity.width * 0.8, height: velocity.height * 0.8)
        }
        pan = newPan

        let speed = hypot(velocity.width, velocity.height)
        if speed < velocityEpsilon && (!outOfBounds || distance - limit < 0.5) {
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
