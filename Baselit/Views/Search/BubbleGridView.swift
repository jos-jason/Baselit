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

// MARK: - Sphere math helpers

/// A 3D point on the unit sphere.
private struct Point3D {
    var x: Double
    var y: Double
    var z: Double
}

/// Rotate a point around an arbitrary axis by `angle` radians (Rodrigues' formula).
/// The axis must be a unit vector.
private func rotateAroundAxis(_ p: Point3D, axis: Point3D, angle: Double) -> Point3D {
    let c = cos(angle)
    let s = sin(angle)
    let dot = axis.x * p.x + axis.y * p.y + axis.z * p.z
    // cross = axis × p
    let crossX = axis.y * p.z - axis.z * p.y
    let crossY = axis.z * p.x - axis.x * p.z
    let crossZ = axis.x * p.y - axis.y * p.x
    return Point3D(
        x: p.x * c + crossX * s + axis.x * dot * (1 - c),
        y: p.y * c + crossY * s + axis.y * dot * (1 - c),
        z: p.z * c + crossZ * s + axis.z * dot * (1 - c)
    )
}

/// Distribute `count` points on a unit sphere using a Fibonacci / golden-angle
/// spiral. For small counts the points are confined to a tight cap around the
/// front pole so they cluster visibly near the center. As count grows the cap
/// opens up to the full sphere.
private func fibonacciSphere(count: Int) -> [Point3D] {
    guard count > 0 else { return [] }
    if count == 1 { return [Point3D(x: 0, y: 0, z: 1)] }

    // Maximum half-angle (in radians) of the spherical cap measured from the
    // front pole. Small counts get a tight cone; the cap stays compact through
    // the mid-range and only opens to the full sphere at higher counts.
    //   2 items  → ~30°   (cosy cluster)
    //   5 items  → ~35°
    //  10 items  → ~45°
    //  20 items  → ~75°
    //  40+ items → 180°  (full sphere)
    let fullSphereCount = 40.0
    let t = min(Double(count) / fullSphereCount, 1.0)
    // Steep ease-in (t³) keeps the cap tight for longer
    let ease = t * t * t
    let maxTheta = (.pi / 6.0) + (.pi * 5.0 / 6.0) * ease  // 30° → 180°

    let goldenRatio = (1.0 + sqrt(5.0)) / 2.0
    var points: [Point3D] = []
    points.reserveCapacity(count)

    for i in 0..<count {
        // Distribute uniformly within the spherical cap [0, maxTheta]
        // Using the area-preserving formula: theta = acos(1 - u*(1-cos(maxTheta)))
        let u = (Double(i) + 0.5) / Double(count)
        let theta = acos(1.0 - u * (1.0 - cos(maxTheta)))
        let phi = 2.0 * .pi * Double(i) / goldenRatio

        points.append(Point3D(
            x: sin(theta) * cos(phi),
            y: sin(theta) * sin(phi),
            z: cos(theta)
        ))
    }
    return points
}

/// Interactive sphere-projected bubble grid.
///
/// Items are distributed across the surface of a virtual sphere. Dragging
/// rotates the sphere so new items sweep into view from the edges while items
/// near the "horizon" shrink and fade out. Only the front hemisphere is shown.
struct BubbleGridView: View {
    let entries: [BubbleEntry]
    let onSelect: (BubbleEntry.Destination) -> Void

    // MARK: - Layout constants

    /// Bubble diameter when an item is right at the front pole.
    private let baseBubbleSize: CGFloat = 88
    /// How much of the view's smallest dimension the projected sphere fills.
    private let sphereRadiusFraction: CGFloat = 0.7
    /// Points with z below this value (behind the horizon) are hidden.
    private let horizonZ: Double = 0.25
    /// How quickly size drops off as items approach the horizon.
    private let depthExponent: Double = 1.8
    /// Drag sensitivity – points of drag per radian of rotation.
    private let dragSensitivity: CGFloat = 400

    // MARK: - Physics constants

    /// Fraction of velocity retained each frame (0 = instant stop, 1 = no friction).
    private let friction: Double = 0.85
    /// Strength of the spring pulling back toward the rest orientation (radians/s²-ish).
    private let springStrength: Double = 0.35
    /// Below this angular velocity the animation stops.
    private let velocityEpsilon: Double = 0.002
    /// Below this total angular offset from rest the spring snaps home.
    private let offsetEpsilon: Double = 0.005

    // MARK: - State

    /// The rotated sphere points (base positions composed with all accumulated rotations).
    @State private var rotatedPoints: [Point3D] = []
    /// Live drag delta while finger is down (screen points).
    @State private var dragTranslation: CGSize = .zero

    /// Pre-computed base sphere positions (regenerated when entry count changes).
    @State private var spherePoints: [Point3D] = []

    // Momentum & spring-back state
    /// Whether the inertia / spring-back animation loop is running.
    @State private var isAnimating: Bool = false
    /// Current angular velocity as a screen-space vector (points per frame equivalent).
    @State private var angularVelocity: CGSize = .zero
    /// Timestamp of the last animation frame, for computing dt.
    @State private var lastFrameTime: Date? = nil
    /// Previous drag translation for computing velocity.
    @State private var previousDragTranslation: CGSize = .zero
    /// Timestamp of the previous drag event.
    @State private var previousDragTime: Date? = nil

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            GeometryReader { geometry in
                let viewCenter = CGPoint(x: geometry.size.width / 2,
                                         y: geometry.size.height / 2)
                let sphereRadius = min(geometry.size.width, geometry.size.height) * sphereRadiusFraction

                // Build the drag rotation from the live drag translation
                let dragAngle = hypot(Double(dragTranslation.width), Double(dragTranslation.height)) / Double(dragSensitivity)
                let dragAxis = dragAxisFromTranslation(dragTranslation)

                // Apply live drag rotation to the already-accumulated rotated points
                let currentPoints: [Point3D] = {
                    if dragAngle < 0.0001 { return rotatedPoints }
                    return rotatedPoints.map { rotateAroundAxis($0, axis: dragAxis, angle: dragAngle) }
                }()

                let projected = projectedEntries(
                    points: currentPoints,
                    sphereRadius: sphereRadius,
                    viewCenter: viewCenter
                )

                ZStack {
                    ForEach(projected, id: \.entry.id) { proj in
                        let bubbleSize = baseBubbleSize * proj.scale

                        BubbleView(
                            entry: proj.entry,
                            size: bubbleSize,
                            maxSize: baseBubbleSize
                        )
                        .position(x: proj.screenX, y: proj.screenY)
                        .zIndex(proj.zIndex)
                        .opacity(proj.opacity)
                        .allowsHitTesting(proj.opacity > 0.3)
                        .onTapGesture {
                            onSelect(proj.entry.destination)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Stop any running animation when the user grabs again
                            isAnimating = false
                            lastFrameTime = nil

                            let now = Date()
                            // Compute instantaneous drag velocity
                            if let prevTime = previousDragTime {
                                let dt = now.timeIntervalSince(prevTime)
                                if dt > 0 && dt < 0.2 {
                                    let vx = (value.translation.width - previousDragTranslation.width) / CGFloat(dt)
                                    let vy = (value.translation.height - previousDragTranslation.height) / CGFloat(dt)
                                    angularVelocity = CGSize(width: vx, height: vy)
                                }
                            }
                            previousDragTranslation = value.translation
                            previousDragTime = now
                            dragTranslation = value.translation
                        }
                        .onEnded { value in
                            // Commit the drag rotation into the stored rotated points
                            let angle = hypot(Double(dragTranslation.width), Double(dragTranslation.height)) / Double(dragSensitivity)
                            if angle > 0.0001 {
                                let axis = dragAxisFromTranslation(dragTranslation)
                                rotatedPoints = rotatedPoints.map { rotateAroundAxis($0, axis: axis, angle: angle) }
                            }
                            dragTranslation = .zero
                            previousDragTranslation = .zero
                            previousDragTime = nil

                            // Kick off momentum + spring-back animation
                            let speed = hypot(angularVelocity.width, angularVelocity.height)
                            if speed > 10 || totalAngularOffset() > offsetEpsilon {
                                lastFrameTime = Date()
                                isAnimating = true
                            }
                        }
                )
            }
            .onChange(of: timeline.date) {
                stepAnimation()
            }
        }
        .onAppear {
            spherePoints = fibonacciSphere(count: entries.count)
            rotatedPoints = spherePoints
        }
        .onChange(of: entries.count) {
            spherePoints = fibonacciSphere(count: entries.count)
            rotatedPoints = spherePoints
        }
    }

    // MARK: - Drag axis

    /// Convert a screen-space drag translation into a rotation axis.
    /// Dragging right → rotate around Y (items move right).
    /// Dragging down → rotate around X (items move down).
    /// No Z-axis component, so no roll ever occurs.
    private func dragAxisFromTranslation(_ t: CGSize) -> Point3D {
        let dx = Double(t.width)
        let dy = Double(t.height)
        let len = hypot(dx, dy)
        guard len > 0.001 else { return Point3D(x: 0, y: 1, z: 0) }
        // Rotation axis is perpendicular to drag direction in screen space:
        // drag right (dx>0) → rotate around Y axis (items shift right)
        // drag down  (dy>0) → rotate around -X axis (items shift down)
        return Point3D(x: dy / len, y: dx / len, z: 0)
    }

    // MARK: - Momentum & spring-back

    /// Measure how far each rotated point has drifted from its rest position.
    /// Returns the average angular distance (in radians) across all points.
    private func totalAngularOffset() -> Double {
        guard rotatedPoints.count == spherePoints.count, !spherePoints.isEmpty else { return 0 }
        var sum = 0.0
        for i in 0..<spherePoints.count {
            let r = rotatedPoints[i]
            let s = spherePoints[i]
            // dot product clamped to [-1,1] → acos gives angle
            let dot = min(1, max(-1, r.x * s.x + r.y * s.y + r.z * s.z))
            sum += acos(dot)
        }
        return sum / Double(spherePoints.count)
    }

    /// Compute a single rotation that moves the current orientation a fraction
    /// back toward the rest orientation, using the average displacement.
    private func springRotation(strength: Double) -> (axis: Point3D, angle: Double)? {
        guard rotatedPoints.count == spherePoints.count, !spherePoints.isEmpty else { return nil }
        // Compute average displacement vector in screen-space-equivalent terms
        // by summing (rest - current) for each point
        var dx = 0.0
        var dy = 0.0
        for i in 0..<spherePoints.count {
            let r = rotatedPoints[i]
            let s = spherePoints[i]
            dx += s.x - r.x
            dy += s.y - r.y
        }
        dx /= Double(spherePoints.count)
        dy /= Double(spherePoints.count)

        let len = hypot(dx, dy)
        guard len > 0.0001 else { return nil }

        // The axis of rotation to go from current toward rest
        // maps the same way as drag: displacement in (dx, dy) → rotation axis
        let axis = Point3D(x: -dy / len, y: dx / len, z: 0)
        let angle = len * strength
        return (axis, angle)
    }

    /// Called each animation frame to apply momentum and spring-back.
    private func stepAnimation() {
        guard isAnimating else { return }
        let now = Date()
        guard let last = lastFrameTime else {
            lastFrameTime = now
            return
        }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 && dt < 0.5 else {
            lastFrameTime = now
            return
        }
        lastFrameTime = now

        // 1. Apply friction to angular velocity
        let frictionPerFrame = pow(friction, dt * 60) // normalize to ~60fps
        angularVelocity = CGSize(
            width: angularVelocity.width * frictionPerFrame,
            height: angularVelocity.height * frictionPerFrame
        )

        // 2. Apply momentum rotation
        let momentumTranslation = CGSize(
            width: angularVelocity.width * dt,
            height: angularVelocity.height * dt
        )
        let momAngle = hypot(Double(momentumTranslation.width), Double(momentumTranslation.height)) / Double(dragSensitivity)
        if momAngle > 0.00001 {
            let axis = dragAxisFromTranslation(momentumTranslation)
            rotatedPoints = rotatedPoints.map { rotateAroundAxis($0, axis: axis, angle: momAngle) }
        }

        // 3. Apply spring-back toward rest orientation
        if let spring = springRotation(strength: springStrength * dt * 60) {
            rotatedPoints = rotatedPoints.map { rotateAroundAxis($0, axis: spring.axis, angle: spring.angle) }
            // The spring also dampens velocity in the direction opposing the spring
            let springDampen = 0.97
            angularVelocity = CGSize(
                width: angularVelocity.width * springDampen,
                height: angularVelocity.height * springDampen
            )
        }

        // 4. Check if we should stop animating
        let speed = hypot(angularVelocity.width, angularVelocity.height)
        let offset = totalAngularOffset()
        if speed < velocityEpsilon * 60 && offset < offsetEpsilon {
            // Snap home
            rotatedPoints = spherePoints
            angularVelocity = .zero
            isAnimating = false
            lastFrameTime = nil
        } else if speed < velocityEpsilon * 10 && offset < offsetEpsilon * 3 {
            // Close enough — snap to avoid lingering micro-drift
            rotatedPoints = spherePoints
            angularVelocity = .zero
            isAnimating = false
            lastFrameTime = nil
        }
    }

    // MARK: - Projection

    private struct ProjectedEntry {
        let entry: BubbleEntry
        let screenX: CGFloat
        let screenY: CGFloat
        let scale: CGFloat
        let opacity: Double
        let zIndex: Double
    }

    private func projectedEntries(
        points: [Point3D],
        sphereRadius: CGFloat,
        viewCenter: CGPoint
    ) -> [ProjectedEntry] {
        guard points.count == entries.count else { return [] }

        var result: [ProjectedEntry] = []
        result.reserveCapacity(entries.count)

        for i in 0..<entries.count {
            let p = points[i]

            // Skip points behind the horizon
            guard p.z > horizonZ else { continue }

            // Depth factor: 0 at horizon, 1 at front pole
            let depthNorm = (p.z - horizonZ) / (1.0 - horizonZ)
            let depthFactor = pow(depthNorm, depthExponent)

            // Project to screen (orthographic with depth-based scaling)
            let screenX = viewCenter.x + CGFloat(p.x) * sphereRadius
            let screenY = viewCenter.y - CGFloat(p.y) * sphereRadius

            // Scale driven by depth, opacity is always full (hard cutoff at horizon)
            let scale = CGFloat(0.25 + 0.75 * depthFactor)
            let opacity = 1.0

            result.append(ProjectedEntry(
                entry: entries[i],
                screenX: screenX,
                screenY: screenY,
                scale: scale,
                opacity: opacity,
                zIndex: p.z * 1000
            ))
        }

        return result
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
