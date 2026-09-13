import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../models/map_station.dart';
import '../models/schematic_layout.dart';
import '../models/transit_graph.dart';
import '../services/map_selection_controller.dart';
import '../services/station_name_matcher.dart';

class InteractiveSchematicMap extends StatefulWidget {
  const InteractiveSchematicMap({
    super.key,
    required this.layout,
    required this.graph,
    required this.controller,
    required this.onStationTap,
    this.hiddenLineIds = const {},
  });

  final SchematicLayout layout;
  final TransitGraph graph;
  final MapSelectionController controller;
  final ValueChanged<MapStation> onStationTap;
  final Set<String> hiddenLineIds;

  @override
  State<InteractiveSchematicMap> createState() =>
      _InteractiveSchematicMapState();
}

class _InteractiveSchematicMapState extends State<InteractiveSchematicMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  final TransformationController _transform = TransformationController();

  static const double _minTapTargetRadius = 22.0;
  static const double _padding = 24.0;
  static const Size _canvasSize = Size(640, 896);
  static const double _minScale = 0.5;
  static const double _maxScale = 5.0;

  bool _transformInitialized = false;

  Size _viewportSize = Size.zero;

  double get _displayWidth => _canvasSize.width - _padding * 2;
  double get _displayHeight => _canvasSize.height - _padding * 2;

  double get _hitRadius {
    final scale = _transform.value.getMaxScaleOnAxis();
    final effectiveScale = scale <= 0 ? 1.0 : scale;
    return _minTapTargetRadius / effectiveScale;
  }

  Offset _toPixel(double nx, double ny) {
    return Offset(
      _padding + nx * _displayWidth,
      _padding + ny * _displayHeight,
    );
  }

  MapStation? _stationAt(Offset localPos) {
    MapStation? closest;
    var closestDistance = _hitRadius;
    for (final station in widget.layout.stations.values) {
      if (_isStationHidden(station.id)) continue;
      final p = _toPixel(station.x, station.y);
      final distance = (localPos - p).distance;
      if (distance <= closestDistance) {
        closestDistance = distance;
        closest = MapStation(
          stationId: station.id,
          name: station.name,
          x: station.x,
          y: station.y,
          lines: station.lines,
        );
      }
    }
    return closest;
  }

  bool _isStationHidden(String stationId) {
    final station = widget.layout.stations[stationId];
    if (station == null) return true;
    return station.lines.every((l) => widget.hiddenLineIds.contains(l));
  }

  @override
  void initState() {
    super.initState();
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _blink.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _ensureInitialTransform(Size viewport) {
    if (_transformInitialized || viewport.isEmpty) return;
    _transformInitialized = true;
    final sx = viewport.width / _canvasSize.width;
    final sy = viewport.height / _canvasSize.height;
    final scale = math.min(sx, sy) * 0.94;
    final dx = (viewport.width - _canvasSize.width * scale) / 2;
    final dy = (viewport.height - _canvasSize.height * scale) / 2;
    _transform.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }

  void _zoomBy(double factor) {
    final current = _transform.value.getMaxScaleOnAxis();
    final target = (current * factor).clamp(_minScale, _maxScale);
    if (target == current) return;
    final s = target / current;
    final cx = _viewportSize.width / 2;
    final cy = _viewportSize.height / 2;
    final m = Matrix4.identity()
      ..setEntry(0, 0, s)
      ..setEntry(1, 1, s)
      ..setEntry(0, 3, cx - cx * s)
      ..setEntry(1, 3, cy - cy * s);
    _transform.value = m * _transform.value;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final segments = widget.controller.routeSegments;
    final hasRoute = widget.controller.isRouteActive;
    final fromId = widget.controller.from?.stationId;
    final toId = widget.controller.to?.stationId;
    final routeStationIds = <String>{};
    for (final segment in segments) {
      routeStationIds.add(segment.fromStationId);
      routeStationIds.add(segment.toStationId);
    }

    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewportSize = constraints.biggest;
              _ensureInitialTransform(constraints.biggest);
              return ClipRect(
                child: InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  minScale: _minScale,
                  maxScale: _maxScale,
                  boundaryMargin: const EdgeInsets.all(160),
                  child: GestureDetector(
                    onTapUp: (details) {
                      final station = _stationAt(details.localPosition);
                      if (station != null) widget.onStationTap(station);
                    },
                    child: SizedBox(
                      width: _canvasSize.width,
                      height: _canvasSize.height,
                      child: AnimatedBuilder(
                        animation: _blink,
                        builder: (context, _) => CustomPaint(
                          size: _canvasSize,
                          painter: _SchematicPainter(
                            layout: widget.layout,
                            segments: segments,
                            hasRoute: hasRoute,
                            routeStationIds: routeStationIds,
                            fromId: fromId,
                            toId: toId,
                            blinkValue: _blink.value,
                            toPixel: _toPixel,
                            hiddenLineIds: widget.hiddenLineIds,
                            backgroundColor: scheme.surface,
                            gridColor: scheme.onSurface.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: _LineLegend(
            lines: widget.layout.lines.values
                .where((l) => !widget.hiddenLineIds.contains(l.id))
                .toList(),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(icon: Icons.add_rounded, onTap: () => _zoomBy(1.3)),
              const SizedBox(height: 8),
              _ZoomButton(icon: Icons.remove_rounded, onTap: () => _zoomBy(0.75)),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineLegend extends StatelessWidget {
  const _LineLegend({required this.lines});

  final List<SchematicLayoutLine> lines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.9),
      elevation: 2,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'LINES',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 4,
                      decoration: BoxDecoration(
                        color: line.color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      line.label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: scheme.onSurface),
        ),
      ),
    );
  }
}

class _SchematicPainter extends CustomPainter {
  _SchematicPainter({
    required this.layout,
    required this.segments,
    required this.hasRoute,
    required this.routeStationIds,
    required this.fromId,
    required this.toId,
    required this.blinkValue,
    required this.toPixel,
    required this.backgroundColor,
    required this.gridColor,
    this.hiddenLineIds = const {},
  });

  final SchematicLayout layout;
  final List<RouteSegment> segments;
  final bool hasRoute;
  final Set<String> routeStationIds;
  final String? fromId;
  final String? toId;
  final double blinkValue;
  final Offset Function(double, double) toPixel;
  final Color backgroundColor;
  final Color gridColor;
  final Set<String> hiddenLineIds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = backgroundColor,
    );

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final visibleLines = layout.lines.values
        .where((l) => !hiddenLineIds.contains(l.id))
        .toList();

    // Background network: full colour when no route, greyed out when a route
    // is selected so only the route keeps its colour.
    for (final line in visibleLines) {
      final stationIds = line.stationIds;
      if (stationIds.length < 2) continue;

      final color = hasRoute ? kMapDisabledGrey : line.color;
      final paint = Paint()
        ..color = color.withValues(alpha: hasRoute ? 0.35 : 0.85)
        ..strokeWidth = hasRoute ? 2.0 : 2.5
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < stationIds.length - 1; i++) {
        final a = layout.stations[stationIds[i]];
        final b = layout.stations[stationIds[i + 1]];
        if (a == null || b == null) continue;
        canvas.drawLine(toPixel(a.x, a.y), toPixel(b.x, b.y), paint);
      }
    }

    // Route overlay: each hop drawn in its own line colour, so the colour
    // switches at interchanges and follows the actual physical path.
    if (hasRoute) {
      for (final segment in segments) {
        if (segment.isTransfer) continue;
        final a = layout.stations[segment.fromStationId];
        final b = layout.stations[segment.toStationId];
        if (a == null || b == null) continue;

        final alpha = 0.65 + 0.35 * blinkValue;
        final paint = Paint()
          ..color = getRouteColor(segment.line).withValues(alpha: alpha)
          ..strokeWidth = 6.0
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(toPixel(a.x, a.y), toPixel(b.x, b.y), paint);
      }
    }

    // Stations.
    for (final station in layout.stations.values) {
      if (station.lines.every((l) => hiddenLineIds.contains(l))) continue;

      final isInterchange = station.lines.length > 1;
      final isCurrent = station.id == fromId;
      final isDestination = station.id == toId;
      final onRoute = routeStationIds.contains(station.id);

      final center = toPixel(station.x, station.y);

      final baseRadius = isInterchange ? 5.0 : 3.5;
      double radius;
      Paint fill;
      Paint stroke;

      if (hasRoute && !onRoute) {
        radius = baseRadius;
        fill = Paint()..color = kMapDisabledGrey;
        stroke = Paint()
          ..color = kMapDisabledGrey
          ..style = PaintingStyle.stroke
          ..strokeWidth = isInterchange ? 2.0 : 1.2;
      } else if (isCurrent) {
        radius = baseRadius + 2.0 + 2.5 * blinkValue;
        fill = Paint()
          ..color = Color.lerp(Colors.amber, Colors.deepOrangeAccent, blinkValue)!
              .withValues(alpha: 0.55 + 0.45 * blinkValue);
        stroke = Paint()
          ..color = Colors.amber.shade800
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
      } else if (isDestination) {
        radius = baseRadius + 1.5;
        fill = Paint()..color = Colors.amber;
        stroke = Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
      } else {
        radius = baseRadius + (onRoute ? 1.0 : 0.0);
        fill = Paint()..color = Colors.white;
        stroke = Paint()
          ..color = Colors.black87
          ..style = PaintingStyle.stroke
          ..strokeWidth = isInterchange ? 2.0 : 1.2;
      }

      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);

      final showLabel = isCurrent || isDestination;
      if (showLabel) {
        final tp = TextPainter(
          text: TextSpan(
            text: StationNameMatcher.instance.displayName(station.name),
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, center + const Offset(7, -5));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SchematicPainter oldDelegate) => true;
}
