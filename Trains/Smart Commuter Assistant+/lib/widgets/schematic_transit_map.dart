import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../models/transit_graph.dart';
import '../screens/station_details.dart';
import '../services/route_selection_service.dart';

const double _cornerRadius = 5.0;
const double _gridPixels = 5.27;
const double _margin = 24;

String _lineDisplayName(String line) {
  switch (line.toUpperCase()) {
    case 'KJ':
      return 'KJ';
    case 'MRT':
    case 'KG':
      return 'MRT';
    case 'PYL':
    case 'PY':
      return 'PY';
    case 'AG':
      return 'AG';
    case 'PH':
    case 'SP':
      return 'SP';
    case 'MR':
      return 'MR';
    case 'BRT':
      return 'BRT';
    default:
      return line;
  }
}

class SchematicTransitMap extends StatefulWidget {
  final TransitGraph graph;
  final String? selectedOriginId;
  final String? selectedDestinationId;
  final TransitPath? activeRoute;
  final ValueChanged<TransitStation>? onOriginSelected;
  final ValueChanged<TransitStation>? onDestinationSelected;
  final bool debugMode;

  const SchematicTransitMap({
    super.key,
    required this.graph,
    this.selectedOriginId,
    this.selectedDestinationId,
    this.activeRoute,
    this.onOriginSelected,
    this.onDestinationSelected,
    this.debugMode = false,
  });

  @override
  State<SchematicTransitMap> createState() => _SchematicTransitMapState();
}

class _SchematicTransitMapState extends State<SchematicTransitMap> {
  final TransformationController _transformController =
      TransformationController();

  static late double _canvasWidth;
  static late double _canvasHeight;
  double _zoom = 1.0;
  ui.Rect? _gridBounds;

  @override
  void initState() {
    super.initState();
    _computeGridBounds();
    _canvasWidth = (_gridBounds!.width * _gridPixels) + _margin * 2;
    _canvasHeight = (_gridBounds!.height * _gridPixels) + _margin * 2;
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final matrix = _transformController.value;
    final newZoom = matrix.getMaxScaleOnAxis();
    if ((newZoom - _zoom).abs() > 0.01) {
      setState(() => _zoom = newZoom);
    }
  }

  double _nodeScale() => _zoom.clamp(0.6, 2.0);

  void _computeGridBounds() {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final s in widget.graph.stations.values) {
      if (s.gridX < minX) minX = s.gridX;
      if (s.gridX > maxX) maxX = s.gridX;
      if (s.gridY < minY) minY = s.gridY;
      if (s.gridY > maxY) maxY = s.gridY;
    }
    if (maxX < minX) {
      minX = 0;
      maxX = 100;
    }
    if (maxY < minY) {
      minY = 0;
      maxY = 100;
    }
    _gridBounds = ui.Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Offset _gridToPixel(TransitStation s) {
    final gx = (s.gridX - _gridBounds!.left) * _gridPixels + _margin;
    final gy = (s.gridY - _gridBounds!.top) * _gridPixels + _margin;
    return Offset(gx, gy);
  }

  Set<String> _activeLines() {
    final lines = <String>{};
    if (widget.activeRoute != null) {
      for (final edge in widget.activeRoute!.edges) {
        if (edge.line.isNotEmpty && edge.line != 'INTERCHANGE') {
          lines.add(edge.line);
        }
      }
      return lines;
    }
    for (final station in widget.graph.stations.values) {
      if (station.id == widget.selectedOriginId ||
          station.id == widget.selectedDestinationId) {
        lines.addAll(station.lines);
      }
    }
    return lines;
  }

  List<String> _topologicalOrder(String line, Set<String> stationsOnLine) {
    if (stationsOnLine.length < 2) return stationsOnLine.toList();
    final adj = <String, List<String>>{};
    for (final sid in stationsOnLine) {
      for (final edge in (widget.graph.adjacency[sid] ?? [])) {
        if (edge.line == line && stationsOnLine.contains(edge.to)) {
          adj.putIfAbsent(sid, () => []).add(edge.to);
        }
      }
    }
    String? findTerminal() {
      for (final sid in stationsOnLine) {
        var outDeg = adj[sid]?.length ?? 0;
        var inDeg = 0;
        for (final other in stationsOnLine) {
          if (adj[other]?.contains(sid) == true) inDeg++;
        }
        if (outDeg + inDeg == 1) return sid;
      }
      return null;
    }

    final start = findTerminal() ?? stationsOnLine.first;
    final ordered = <String>[start];
    final visited = <String>{start};
    var current = start;
    while (true) {
      final next = (adj[current] ?? []).where((n) => !visited.contains(n));
      if (next.isEmpty) {
        final back = (stationsOnLine.where((s) =>
            (adj[s]?.contains(current) == true) && !visited.contains(s)));
        if (back.isEmpty) break;
        current = back.first;
      } else {
        current = next.first;
      }
      visited.add(current);
      ordered.add(current);
      if (ordered.length >= stationsOnLine.length) break;
    }
    return ordered;
  }

  List<Offset> _octilinearPath(Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final adx = dx.abs();
    final ady = dy.abs();
    if (adx < 0.001 && ady < 0.001) return [a];
    if (adx < 0.001 || ady < 0.001 || (adx - ady).abs() < 0.001) {
      return [a, b];
    }
    if (adx > ady) {
      final midX = b.dx - dy.sign * ady;
      return [a, Offset(midX, a.dy), b];
    } else {
      final midY = b.dy - dx.sign * adx;
      return [a, Offset(a.dx, midY), b];
    }
  }

  List<_LineSegment> _buildLineSegments() {
    final activeLines = _activeLines();
    final segments = <_LineSegment>[];
    final byLine = <String, Set<String>>{};
    for (final station in widget.graph.stations.values) {
      for (final line in station.lines) {
        byLine.putIfAbsent(line, () => {}).add(station.id);
      }
    }
    for (final entry in byLine.entries) {
      final line = entry.key;
      if (line == 'INTERCHANGE') continue;
      final order = _topologicalOrder(line, entry.value);
      for (var i = 0; i < order.length - 1; i++) {
        final fromS = widget.graph.stations[order[i]]!;
        final toS = widget.graph.stations[order[i + 1]]!;
        final fromP = _gridToPixel(fromS);
        final toP = _gridToPixel(toS);
        segments.add(_LineSegment(
          pathPoints: _octilinearPath(fromP, toP),
          line: line,
          isActiveLine: activeLines.isEmpty || activeLines.contains(line),
          isRoutePath: _isOnRoutePath(order[i], order[i + 1], line),
          isTransfer: false,
        ));
      }
    }
    _addInterchangeSegments(segments, activeLines);
    return segments;
  }

  bool _isOnRoutePath(String fromId, String toId, String line) {
    if (widget.activeRoute == null) return false;
    for (var i = 0; i < widget.activeRoute!.stationIds.length - 1; i++) {
      if (widget.activeRoute!.stationIds[i] == fromId &&
          widget.activeRoute!.stationIds[i + 1] == toId) {
        return true;
      }
    }
    return false;
  }

  void _addInterchangeSegments(
    List<_LineSegment> segments,
    Set<String> activeLines,
  ) {
    final byName = <String, List<TransitStation>>{};
    for (final station in widget.graph.stations.values) {
      final key = station.name.toUpperCase().trim();
      byName.putIfAbsent(key, () => []).add(station);
    }
    for (final group in byName.values) {
      if (group.length < 2) continue;
      final seen = <String>{};
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          final linesKey = <String>[group[i].lines.first, group[j].lines.first]
            ..sort();
          final pairKey = '${linesKey[0]}|${linesKey[1]}';
          if (!seen.add(pairKey)) continue;
          final fromP = _gridToPixel(group[i]);
          final toP = _gridToPixel(group[j]);
          segments.add(_LineSegment(
            pathPoints: [fromP, toP],
            line: group[j].lines.first,
            isActiveLine: activeLines.isEmpty ||
                activeLines.contains(group[i].lines.first) ||
                activeLines.contains(group[j].lines.first),
            isRoutePath: false,
            isTransfer: true,
          ));
        }
      }
    }
  }

  TransitStation? _hitTestStation(Offset localPos) {
    const hitRadius = 14.0;
    for (final station in widget.graph.stations.values) {
      final p = _gridToPixel(station);
      final dx = localPos.dx - p.dx;
      final dy = localPos.dy - p.dy;
      if (dx * dx + dy * dy < hitRadius * hitRadius) {
        return station;
      }
    }
    return null;
  }

  void _onStationTap(TransitStation station) {
    RouteSelectionService.instance.handleStationTap(
      stationId: station.id,
      stationName: station.name,
    );
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _StationActionSheet(
        station: station,
        onViewDetails: () {
          Navigator.pop(ctx);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StationDetails(
                stopId: station.id,
                stopName: station.name,
              ),
            ),
          );
        },
        onSetOrigin: widget.onOriginSelected != null
            ? () {
                Navigator.pop(ctx);
                RouteSelectionService.instance.setOrigin(
                  station.id,
                  station.name,
                );
                widget.onOriginSelected!(station);
              }
            : null,
        onSetDestination: widget.onDestinationSelected != null
            ? () {
                Navigator.pop(ctx);
                RouteSelectionService.instance.setDestination(
                  station.id,
                  station.name,
                );
                widget.onDestinationSelected!(station);
              }
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segments = _buildLineSegments();
    final activeLines = _activeLines();
    final hasSelection =
        widget.selectedOriginId != null || widget.selectedDestinationId != null;

    return Scaffold(
      body: InteractiveViewer(
        transformationController: _transformController,
        minScale: 0.3,
        maxScale: 4.0,
        constrained: false,
        child: GestureDetector(
          onTapUp: (details) {
            final hit = _hitTestStation(details.localPosition);
            if (hit != null) {
              _onStationTap(hit);
            }
          },
          child: SizedBox(
            width: _canvasWidth,
            height: _canvasHeight,
            child: Stack(
              children: [
                // Transit map image as background
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/klang_valley_map.jpeg',
                    fit: BoxFit.fill,
                    alignment: Alignment.topLeft,
                  ),
                ),
                CustomPaint(
                  size: Size(_canvasWidth, _canvasHeight),
                  painter: _SchematicMapPainter(
                    segments: segments,
                    graph: widget.graph,
                    selectedOriginId: widget.selectedOriginId,
                    selectedDestinationId: widget.selectedDestinationId,
                    activeRoute: widget.activeRoute,
                    gridToPixel: _gridToPixel,
                  ),
                ),
                ...widget.graph.stations.values.map((station) {
                  final isOrigin = station.id == widget.selectedOriginId;
                  final isDest = station.id == widget.selectedDestinationId;
                  final isOnRoute = widget.activeRoute != null &&
                      widget.activeRoute!.stationIds.contains(station.id);
                  final isActive = activeLines.isEmpty ||
                      station.lines.any((l) => activeLines.contains(l));
                  final isDimmed = hasSelection &&
                      !isActive &&
                      !isOnRoute &&
                      !isOrigin &&
                      !isDest;

                  if (isDimmed && !station.isInterchange)
                    return const SizedBox.shrink();

                  final s = _nodeScale();
                  double size = (station.isInterchange ? 11 : 8) * s;
                  Color color;
                  if (isOrigin) {
                    color = const Color(0xFF0F6FFF);
                    size = 22 * s;
                  } else if (isDest) {
                    color = const Color(0xFFD7263D);
                    size = 22 * s;
                  } else if (isOnRoute) {
                    color = getRouteColor(station.lines.first);
                    size = 12 * s;
                  } else if (isActive || !hasSelection) {
                    color = getRouteColor(station.lines.first);
                  } else {
                    color = Colors.grey;
                  }

                  final opacity = isDimmed
                      ? 0.3
                      : (isOnRoute || isOrigin || isDest ? 1.0 : 0.85);
                  final p = _gridToPixel(station);

                  return Positioned(
                    left: p.dx - size / 2,
                    top: p.dy - size / 2,
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isOrigin || isDest
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.8),
                            width:
                                isOrigin || isDest ? 3 : (isOnRoute ? 2.5 : 2),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(
                                  alpha: isOrigin || isDest ? 0.5 : 0.3),
                              blurRadius: isOrigin || isDest ? 8 : 3,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: isOrigin || isDest
                            ? Icon(
                                isOrigin
                                    ? Icons.trip_origin_rounded
                                    : Icons.location_on_rounded,
                                color: Colors.white,
                                size: size * 0.55,
                              )
                            : null,
                      ),
                    ),
                  );
                }),
                if (widget.selectedOriginId != null &&
                    widget.selectedDestinationId != null)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(18),
                      color: Colors.white.withValues(alpha: 0.95),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFDCE6F5)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.trip_origin_rounded,
                                              size: 14,
                                              color: Color(0xFF0F6FFF)),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              widget
                                                      .graph
                                                      .stations[widget
                                                          .selectedOriginId]
                                                      ?.name ??
                                                  '',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded,
                                              size: 14,
                                              color: Color(0xFFD7263D)),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              widget
                                                      .graph
                                                      .stations[widget
                                                          .selectedDestinationId]
                                                      ?.name ??
                                                  '',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                if (widget.activeRoute != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0A3A8B)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      widget.activeRoute!.summary,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: Color(0xFF0A3A8B),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabelRect {
  final TransitStation station;
  final TextPainter painter;
  final Rect rect;
  final bool isOnRoute;
  final int priority;
  const _LabelRect({
    required this.station,
    required this.painter,
    required this.rect,
    required this.isOnRoute,
    required this.priority,
  });
}

class _LineSegment {
  final List<Offset> pathPoints;
  final String line;
  final bool isActiveLine;
  final bool isRoutePath;
  final bool isTransfer;

  const _LineSegment({
    required this.pathPoints,
    required this.line,
    required this.isActiveLine,
    required this.isRoutePath,
    this.isTransfer = false,
  });
}

class _SchematicMapPainter extends CustomPainter {
  final List<_LineSegment> segments;
  final TransitGraph graph;
  final String? selectedOriginId;
  final String? selectedDestinationId;
  final TransitPath? activeRoute;
  final Offset Function(TransitStation) gridToPixel;

  _SchematicMapPainter({
    required this.segments,
    required this.graph,
    this.selectedOriginId,
    this.selectedDestinationId,
    this.activeRoute,
    required this.gridToPixel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawLineSegments(canvas, size);
    _drawStationLabels(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    // Background is now the transit map image beneath the CustomPaint
  }

  void _drawLineSegments(Canvas canvas, Size size) {
    for (final segment in segments) {
      if (segment.pathPoints.length < 2) continue;
      final color = segment.isRoutePath
          ? getRouteColor(segment.line)
          : (segment.isActiveLine ? getRouteColor(segment.line) : Colors.grey);

      if (segment.isTransfer) {
        final paint = Paint()
          ..color = color.withValues(
              alpha: segment.isRoutePath
                  ? 0.6
                  : (segment.isActiveLine ? 0.35 : 0.08))
          ..strokeWidth = segment.isRoutePath ? 2.5 : 1.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        final a = segment.pathPoints[0];
        final b = segment.pathPoints[1];
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        canvas.drawLine(a, mid, paint);
        canvas.drawLine(mid, b, paint);
        continue;
      }

      final paint = Paint()
        ..color = color.withValues(
          alpha:
              segment.isRoutePath ? 1.0 : (segment.isActiveLine ? 0.6 : 0.08),
        )
        ..strokeWidth =
            segment.isRoutePath ? 6.0 : (segment.isActiveLine ? 3.0 : 1.5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      canvas.drawPath(_buildRoundedPath(segment.pathPoints), paint);
    }
  }

  Path _buildRoundedPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points[0].dx, points[0].dy);
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return path;
    }
    for (var i = 0; i < points.length - 2; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final p2 = points[i + 2];
      final r = math.min(_cornerRadius,
          math.min((p0 - p1).distance, (p1 - p2).distance) * 0.45);
      if (r < 0.5) {
        path.lineTo(p2.dx, p2.dy);
        i++;
        continue;
      }
      final t1 = _along(p1, p0, r);
      final t2 = _along(p1, p2, r);
      path.lineTo(t1.dx, t1.dy);
      path.quadraticBezierTo(p1.dx, p1.dy, t2.dx, t2.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  Offset _along(Offset from, Offset toward, double dist) {
    final d = (from - toward).distance;
    if (d < 0.001) return from;
    final f = dist / d;
    return Offset(
      from.dx + (toward.dx - from.dx) * f,
      from.dy + (toward.dy - from.dy) * f,
    );
  }

  void _drawStationLabels(Canvas canvas, Size size) {
    final routeStations =
        activeRoute != null ? activeRoute!.stationIds.toSet() : <String>{};

    final labels = <_LabelRect>[];
    for (final station in graph.stations.values) {
      final isOnRoute = routeStations.contains(station.id);
      if (!isOnRoute && !station.isInterchange) continue;

      final p = gridToPixel(station);
      final tp = TextPainter(
        text: TextSpan(
          text: station.name,
          style: TextStyle(
            color: isOnRoute ? Colors.white : const Color(0xFF344054),
            fontSize: isOnRoute ? 11 : 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 120);

      final labelX = p.dx + 10;
      final labelY = p.dy - tp.height / 2;
      final rect = Rect.fromLTWH(labelX, labelY, tp.width, tp.height);
      labels.add(_LabelRect(
        station: station,
        painter: tp,
        rect: rect,
        isOnRoute: isOnRoute,
        priority: isOnRoute ? 2 : (station.isInterchange ? 1 : 0),
      ));
    }

    labels.sort((a, b) => b.priority.compareTo(a.priority));

    final drawn = <Rect>[];
    for (final l in labels) {
      final shrunk = l.rect.inflate(-2);
      if (drawn.any((r) => r.overlaps(shrunk))) continue;

      drawn.add(l.rect);
      if (l.isOnRoute) {
        final bgRect = Rect.fromLTWH(
          l.rect.left - 3,
          l.rect.top - 2,
          l.rect.width + 6,
          l.rect.height + 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(bgRect, const Radius.circular(3)),
          Paint()..color = Colors.black87.withValues(alpha: 0.75),
        );
      }
      l.painter.paint(canvas, Offset(l.rect.left, l.rect.top));
    }
  }

  @override
  bool shouldRepaint(covariant _SchematicMapPainter oldDelegate) => true;
}

class _StationActionSheet extends StatelessWidget {
  final TransitStation station;
  final VoidCallback onViewDetails;
  final VoidCallback? onSetOrigin;
  final VoidCallback? onSetDestination;

  const _StationActionSheet({
    required this.station,
    required this.onViewDetails,
    this.onSetOrigin,
    this.onSetDestination,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = getRouteColor(station.lines.first);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: primaryColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        station.id,
                        style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: station.lines.map((line) {
                final color = getRouteColor(line);
                final onColor = getRouteOnColor(line);
                final label = _lineDisplayName(line);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: onColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                );
              }).toList(),
            ),
            if (station.isInterchange) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz_rounded,
                        size: 14, color: Color(0xFF92400E)),
                    SizedBox(width: 4),
                    Text(
                      'Interchange station',
                      style: TextStyle(
                        color: Color(0xFF92400E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (onSetOrigin != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSetOrigin,
                      icon: const Icon(Icons.trip_origin_rounded, size: 18),
                      label: const Text('Set Origin'),
                    ),
                  ),
                if (onSetOrigin != null && onSetDestination != null)
                  const SizedBox(width: 10),
                if (onSetDestination != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSetDestination,
                      icon: const Icon(Icons.location_on_rounded, size: 18),
                      label: const Text('Set Destination'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onViewDetails,
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                label: const Text('View Station Details'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
