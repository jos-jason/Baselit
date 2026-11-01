// Honeycomb bubble grid, ported from the iOS BubbleGridView (inspired by the
// Apple Watch app grid). Entries sit on a flat hex grid, oldest in the center;
// bubbles shrink and pull inward near the edges, and dragging pans with momentum.

import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';

class BubbleEntry {
  BubbleEntry({
    required this.id,
    required this.createdAt,
    required this.icon,
    this.photo,
    required this.onTap,
  });

  final String id;
  final DateTime createdAt;
  final IconData icon;
  final Photo? photo;
  final VoidCallback onTap;
}

/// Axial hex coordinates spiraling outward ring by ring from the center.
/// Slot `i` never moves, so new entries only fill slots on the outside.
List<(int, int)> honeycombSlots(int count) {
  if (count <= 0) return [];
  const directions = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];
  final slots = <(int, int)>[(0, 0)];
  var ring = 1;
  while (slots.length < count) {
    var q = directions[4].$1 * ring;
    var r = directions[4].$2 * ring;
    for (final d in directions) {
      for (var i = 0; i < ring && slots.length < count; i++) {
        slots.add((q, r));
        q += d.$1;
        r += d.$2;
      }
    }
    ring++;
  }
  return slots;
}

class BubbleGrid extends StatefulWidget {
  const BubbleGrid({super.key, required this.store, required this.entries});

  final InventoryStore store;
  final List<BubbleEntry> entries;

  @override
  State<BubbleGrid> createState() => _BubbleGridState();
}

class _BubbleGridState extends State<BubbleGrid>
    with SingleTickerProviderStateMixin {
  // Layout, same values as iOS
  static const baseBubbleSize = 88.0;
  static const slotSpacing = 104.0;
  static const fisheyeStart = 0.55;
  static const fisheyeEnd = 1.15;
  static const minimumScale = 0.2;
  static const hiddenScale = 0.22;
  static const edgeCompression = 0.35;

  // Physics
  static const friction = 0.93;
  static const boundsSpring = 0.15;
  static const edgeReach = 0.9;
  static const overscrollReach = 0.25;
  static const velocityEpsilon = 5.0;

  Offset _pan = Offset.zero;
  Offset _panAtDragStart = Offset.zero;
  Offset _dragTotal = Offset.zero;
  Offset _velocity = Offset.zero;
  Size _size = Size.zero;
  late final Ticker _ticker = createTicker(_step);
  Duration? _lastTick;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  List<BubbleEntry> get _ordered => [...widget.entries]
    ..sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });

  static Offset _gridPoint((int, int) slot) => Offset(
    slotSpacing * (slot.$1 + slot.$2 / 2),
    slotSpacing * (sqrt(3) / 2) * slot.$2,
  );

  /// How far the grid can pan per axis, so it stops when the outermost row reaches the edge.
  (double, double, double, double) get _bounds {
    final points = honeycombSlots(widget.entries.length)
        .map(_gridPoint)
        .toList();
    if (points.isEmpty || _size.isEmpty) return (0, 0, 0, 0);
    (double, double) range(Iterable<double> values, double half) {
      final low = values.reduce(min) + edgeReach * half;
      final high = values.reduce(max) - edgeReach * half;
      return low <= high ? (low, high) : (0, 0);
    }

    final x = range(points.map((p) => p.dx), _size.width / 2);
    final y = range(points.map((p) => p.dy), _size.height / 2);
    return (x.$1, x.$2, y.$1, y.$2);
  }

  /// Lets a drag stretch past the bounds with growing resistance, like iOS.
  double _rubberBand(double value, double low, double high, double stretch) {
    final limit = stretch * overscrollReach;
    double resist(double over) => (1 - 1 / (over / limit * 0.55 + 1)) * limit;
    if (value > high) return high + resist(value - high);
    if (value < low) return low - resist(low - value);
    return value;
  }

  void _onDragStart(DragStartDetails _) {
    _ticker.stop();
    _panAtDragStart = _pan;
    _dragTotal = Offset.zero;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragTotal += details.delta;
    final b = _bounds;
    setState(() {
      _pan = Offset(
        _rubberBand(
          _panAtDragStart.dx - _dragTotal.dx,
          b.$1,
          b.$2,
          _size.width / 2,
        ),
        _rubberBand(
          _panAtDragStart.dy - _dragTotal.dy,
          b.$3,
          b.$4,
          _size.height / 2,
        ),
      );
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _velocity = -details.velocity.pixelsPerSecond;
    _lastTick = null;
    _ticker.start();
  }

  /// Coasts with momentum each frame and settles back inside the bounds.
  void _step(Duration elapsed) {
    final last = _lastTick;
    _lastTick = elapsed;
    if (last == null) return;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0 || dt >= 0.5) return;

    final frictionPerFrame = pow(friction, dt * 60).toDouble();
    final pull = min(boundsSpring * dt * 60, 1.0);
    final b = _bounds;

    (double, double, double) axis(
      double position,
      double speed,
      double low,
      double high,
    ) {
      speed *= frictionPerFrame;
      position += speed * dt;
      final clamped = position.clamp(low, high);
      if (position != clamped) {
        speed *= 0.6;
        position += (clamped - position) * pull;
      }
      return (position, speed, (position - clamped).abs());
    }

    final x = axis(_pan.dx, _velocity.dx, b.$1, b.$2);
    final y = axis(_pan.dy, _velocity.dy, b.$3, b.$4);
    setState(() {
      _pan = Offset(x.$1, y.$1);
      _velocity = Offset(x.$2, y.$2);
      if (_velocity.distance < velocityEpsilon && max(x.$3, y.$3) < 0.5) {
        _pan = Offset(x.$1.clamp(b.$1, b.$2), y.$1.clamp(b.$3, b.$4));
        _ticker.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _size = constraints.biggest;
      final halfW = _size.width / 2;
      final halfH = _size.height / 2;
      final bubbles = <(BubbleEntry, Offset, double)>[];
      final ordered = _ordered;
      final slots = honeycombSlots(ordered.length);
      for (var i = 0; i < ordered.length; i++) {
        final point = _gridPoint(slots[i]);
        var x = point.dx - _pan.dx;
        var y = point.dy - _pan.dy;
        // Distance normalized per axis so tall and wide views both use their space
        final distance = sqrt(pow(x / halfW, 2) + pow(y / halfH, 2));
        var scale = 1.0;
        if (distance > fisheyeStart) {
          final t = min(
            (distance - fisheyeStart) / (fisheyeEnd - fisheyeStart),
            1.0,
          );
          final eased = t * t * (3 - 2 * t);
          scale = 1 - (1 - minimumScale) * eased;
          final compressed =
              fisheyeStart +
              (distance - fisheyeStart) * (1 - edgeCompression * eased);
          x *= compressed / distance;
          y *= compressed / distance;
        }
        if (scale < hiddenScale) continue;
        bubbles.add((ordered[i], Offset(halfW + x, halfH + y), scale));
      }
      // Larger bubbles draw on top, like iOS zIndex(scale)
      bubbles.sort((a, b) => a.$3.compareTo(b.$3));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onDragStart,
        onPanUpdate: _onDragUpdate,
        onPanEnd: _onDragEnd,
        child: ClipRect(
          child: Stack(
            children: [
              for (final (entry, center, scale) in bubbles)
                Positioned(
                  key: ValueKey(entry.id),
                  left: center.dx - baseBubbleSize * scale / 2,
                  top: center.dy - baseBubbleSize * scale / 2,
                  child: IgnorePointer(
                    ignoring: scale <= 0.4,
                    child: GestureDetector(
                      onTap: entry.onTap,
                      child: _Bubble(
                        store: widget.store,
                        entry: entry,
                        size: baseBubbleSize * scale,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// One round bubble: the first photo, or a gray circle with the item or container icon.
class _Bubble extends StatelessWidget {
  const _Bubble({required this.store, required this.entry, required this.size});

  final InventoryStore store;
  final BubbleEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final placeholder = Container(
      color: colors.bubbleFill,
      alignment: Alignment.center,
      child: Icon(entry.icon, size: size * 0.32, color: colors.secondaryLabel),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: entry.photo == null
            ? placeholder
            : Image.file(
                store.photoFile(entry.photo!),
                fit: BoxFit.cover,
                cacheWidth: (baseSizeForCache * 3).round(),
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }

  static const baseSizeForCache = _BubbleGridState.baseBubbleSize;
}

/// Bubbles for the given items and containers.
List<BubbleEntry> bubbleEntries(
  InventoryStore store, {
  required Iterable<Item> items,
  required Iterable<StorageContainer> containers,
  required void Function(Item) openItem,
  required void Function(StorageContainer) openContainer,
}) {
  Photo? first(List<Photo> photos) => photos.isEmpty ? null : photos.first;
  return [
    for (final item in items)
      BubbleEntry(
        id: 'item-${item.exportID}',
        createdAt: item.createdAt,
        icon: CupertinoIcons.cube_box,
        photo: first(store.photosFor(itemID: item.exportID)),
        onTap: () => openItem(item),
      ),
    for (final container in containers)
      BubbleEntry(
        id: 'container-${container.exportID}',
        createdAt: container.createdAt,
        icon: CupertinoIcons.archivebox,
        photo: first(store.photosFor(containerID: container.exportID)),
        onTap: () => openContainer(container),
      ),
  ];
}
