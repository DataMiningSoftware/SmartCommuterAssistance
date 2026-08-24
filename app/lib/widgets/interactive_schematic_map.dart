import 'package:flutter/material.dart';

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
  State<InteractiveSchematicMap> createState() => _InteractiveSchematicMapState();
}

class _InteractiveSchematicMapState extends State<InteractiveSchematicMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink;
  static const double _hitRadius = 18.0;
  static const double _padding = 24;

  double _canvasWidth = 800;
  double _canvasHeight = 1120;

  Map<String, String>? _nameToSchematicId;

  Map<String, String> _getNameToSchematicId() {
    if (_nameToSchematicId == null) {
      _nameToSchematicId = {};
      final matcher = StationNameMatcher.instance;
      for (final entry in widget.layout.stations.entries) {
        _nameToSchematicId![matcher.normalize(entry.value.name)] = entry.key;
      }
    }
    return _nameToSchematicId!;
  }

  double _displayOffsetX = 24;
  double _displayOffsetY = 24;
  double _displayWidth = 752;
  double _displayHeight = 1072;

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
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _updateDisplayMetrics() {
    _displayOffsetX = _padding;
    _displayOffsetY = _padding;
    _displayWidth = _canvasWidth - _padding * 2;
    _displayHeight = _canvasHeight - _padding * 2;
  }

  Offset _toPixel(double nx, double ny) {
    return Offset(
      _displayOffsetX + nx * _displayWidth,
      _displayOffsetY + ny * _displayHeight,
    );
  }

  MapStation? _stationAt(Offset localPos) {
    for (final station in widget.layout.stations.values) {
      if (_isStationHidden(station.id)) continue;
      final p = _toPixel(station.x, station.y);
      if ((localPos - p).distance <= _hitRadius) {
        return MapStation(
          stationId: station.id,
          name: station.name,
          x: station.x,
          y: station.y,
          lines: station.lines,
        );
      }
    }
    return null;
  }

  bool _isStationHidden(String stationId) {
    final station = widget.layout.stations[stationId];
    if (station == null) return true;
    return station.lines.every((l) => widget.hiddenLineIds.contains(l));
  }

  Set<String> get _routeStationIds {
    final route = widget.controller.confirmedRoute ?? widget.controller.candidateRoute;
    if (route == null) return {};
    final nameMap = _getNameToSchematicId();
    final matcher = StationNameMatcher.instance;
    return route.steps
        .map((s) => nameMap[matcher.normalize(s.station)])
        .where((id) => id != null && id.isNotEmpty)
        .map((id) => id!)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasWidth = constraints.maxWidth;
        _canvasHeight = constraints.maxHeight;
        _updateDisplayMetrics();

        return GestureDetector(
          onTapUp: (details) {
            final station = _stationAt(details.localPosition);
            if (station != null) {
              widget.onStationTap(station);
            }
          },
          child: AnimatedBuilder(
            animation: _blink,
            builder: (context, _) {
              return CustomPaint(
                size: Size(_canvasWidth, _canvasHeight),
                painter: _SchematicPainter(
                  layout: widget.layout,
                  controller: widget.controller,
                  routeStationIds: _routeStationIds,
                  blinkValue: _blink.value,
                  toPixel: _toPixel,
                  hiddenLineIds: widget.hiddenLineIds,
                ),
              );
            },
          ),
        );
      },
    );
  }

}

class _SchematicPainter extends CustomPainter {
  _SchematicPainter({
    required this.layout,
    required this.controller,
    required this.routeStationIds,
    required this.blinkValue,
    required this.toPixel,
    this.hiddenLineIds = const {},
  });

  final SchematicLayout layout;
  final MapSelectionController controller;
  final Set<String> routeStationIds;
  final double blinkValue;
  final Offset Function(double, double) toPixel;
  final Set<String> hiddenLineIds;

  bool get _hasRoute =>
      controller.candidateRoute != null || controller.confirmedRoute != null;

  @override
  void paint(Canvas canvas, Size size) {
    final fromId = controller.from?.stationId;
    final toId = controller.to?.stationId;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF5F5F5),
    );

    final visibleLines = layout.lines.values
        .where((l) => !hiddenLineIds.contains(l.id))
        .toList();

    // Draw ALL transit lines (always visible, dim when route is active)
    for (final line in visibleLines) {
      final stationIds = line.stationIds;
      if (stationIds.length < 2) continue;

      final idsOnRoute = stationIds.where(routeStationIds.contains).toSet();
      final isOnRoute = _hasRoute && idsOnRoute.length >= 2;

      final paint = Paint()
        ..color = line.color.withValues(alpha: isOnRoute ? 0.3 : 0.6)
        ..strokeWidth = isOnRoute ? 5.0 : 2.5
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < stationIds.length - 1; i++) {
        final a = layout.stations[stationIds[i]];
        final b = layout.stations[stationIds[i + 1]];
        if (a == null || b == null) continue;
        canvas.drawLine(toPixel(a.x, a.y), toPixel(b.x, b.y), paint);
      }
    }

    // Draw route highlight polylines on top (brighter, thicker, blinking)
    if (_hasRoute) {
      for (final line in visibleLines) {
        final stationIds = line.stationIds;
        final idsOnRoute = stationIds.where(routeStationIds.contains).toSet();
        if (idsOnRoute.length < 2) continue;

        for (int i = 0; i < stationIds.length - 1; i++) {
          final aId = stationIds[i];
          final bId = stationIds[i + 1];
          if (!routeStationIds.contains(aId) || !routeStationIds.contains(bId)) {
            continue;
          }
          final a = layout.stations[aId];
          final b = layout.stations[bId];
          if (a == null || b == null) continue;

          final alpha = 0.6 + 0.4 * blinkValue;
          final paint = Paint()
            ..color = line.color.withValues(alpha: alpha)
            ..strokeWidth = 6.0
            ..strokeCap = StrokeCap.round;
          canvas.drawLine(toPixel(a.x, a.y), toPixel(b.x, b.y), paint);
        }
      }
    }

    // Draw station markers
    for (final station in layout.stations.values) {
      if (station.lines.every((l) => hiddenLineIds.contains(l))) continue;

      final isInterchange = station.lines.length > 1;
      final isSelected = station.id == fromId ||
          station.id == toId ||
          routeStationIds.contains(station.id);

      final baseRadius = isInterchange ? 5.0 : 3.5;
      final radius = isSelected ? baseRadius + 2.0 * blinkValue : baseRadius;

      final center = toPixel(station.x, station.y);

      final fill = Paint()
        ..color = isSelected
            ? Color.lerp(Colors.amber, Colors.orangeAccent, blinkValue)!
                .withValues(alpha: 0.5 + 0.5 * blinkValue)
            : Colors.white;
      final stroke = Paint()
        ..color = Colors.black87
        ..style = PaintingStyle.stroke
        ..strokeWidth = isInterchange ? 2.0 : 1.2;

      canvas.drawCircle(center, radius, fill);
      canvas.drawCircle(center, radius, stroke);

      // Only show label if selected or when there's room
      if (isSelected || radius > 4) {
        final tp = TextPainter(
          text: TextSpan(
            text: StationNameMatcher.instance.displayName(station.name),
            style: TextStyle(
              fontSize: 9,
              color: Colors.black87,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
