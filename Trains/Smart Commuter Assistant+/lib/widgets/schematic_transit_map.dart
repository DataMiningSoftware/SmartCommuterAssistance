import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../models/map_station.dart';
import '../screens/station_details.dart';

class SchematicTransitMap extends StatefulWidget {
  final List<MapStation> stations;
  final String? selectedOriginId;
  final String? selectedDestinationId;
  final ValueChanged<MapStation>? onOriginSelected;
  final ValueChanged<MapStation>? onDestinationSelected;

  const SchematicTransitMap({
    super.key,
    required this.stations,
    this.selectedOriginId,
    this.selectedDestinationId,
    this.onOriginSelected,
    this.onDestinationSelected,
  });

  @override
  State<SchematicTransitMap> createState() => _SchematicTransitMapState();
}

class _SchematicTransitMapState extends State<SchematicTransitMap> {
  final TransformationController _transformController =
      TransformationController();
  MapStation? _selectedStation;
  String? _hoveredStationId;

  static const double _mapImageWidth = 1805;
  static const double _mapImageHeight = 2560;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _onStationTap(MapStation station) {
    setState(() => _selectedStation = station);
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
                stopId: station.stationId,
                stopName: station.name,
              ),
            ),
          );
        },
        onSetOrigin: widget.onOriginSelected != null
            ? () {
                Navigator.pop(ctx);
                widget.onOriginSelected!(station);
              }
            : null,
        onSetDestination: widget.onDestinationSelected != null
            ? () {
                Navigator.pop(ctx);
                widget.onDestinationSelected!(station);
              }
            : null,
      ),
    );
  }

  Set<String> _activeLines() {
    final lines = <String>{};
    for (final station in widget.stations) {
      if (station.stationId == widget.selectedOriginId ||
          station.stationId == widget.selectedDestinationId) {
        lines.addAll(station.lines);
      }
    }
    return lines;
  }

  List<_LineSegment> _buildLineSegments() {
    final activeLines = _activeLines();
    final segments = <_LineSegment>[];
    final byLine = <String, List<MapStation>>{};
    for (final station in widget.stations) {
      for (final line in station.lines) {
        byLine.putIfAbsent(line, () => []).add(station);
      }
    }
    for (final entry in byLine.entries) {
      final line = entry.key;
      final stations = entry.value;
      stations.sort((a, b) {
        final distA = a.x * a.x + a.y * a.y;
        final distB = b.x * b.x + b.y * b.y;
        return distA.compareTo(distB);
      });
      for (var i = 0; i < stations.length - 1; i++) {
        segments.add(_LineSegment(
          from: Offset(stations[i].x, stations[i].y),
          to: Offset(stations[i + 1].x, stations[i + 1].y),
          line: line,
          active: activeLines.isEmpty || activeLines.contains(line),
        ));
      }
    }
    return segments;
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
        child: SizedBox(
          width: _mapImageWidth,
          height: _mapImageHeight,
          child: Stack(
            children: [
              Image.asset(
                'assets/images/klang_valley_map.png',
                width: _mapImageWidth,
                height: _mapImageHeight,
                fit: BoxFit.fill,
              ),
              if (hasSelection)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _LinePainter(
                        segments: segments,
                        activeLines: activeLines,
                      ),
                    ),
                  ),
                ),
              ...widget.stations.map((station) {
                final isOrigin =
                    station.stationId == widget.selectedOriginId;
                final isDest =
                    station.stationId == widget.selectedDestinationId;
                final isHovered = _hoveredStationId == station.stationId;
                final isActive = activeLines.isEmpty ||
                    station.lines.any((l) => activeLines.contains(l));
                final isHighlighted = isOrigin || isDest;

                double size = 22;
                Color markerColor;
                if (isOrigin) {
                  markerColor = const Color(0xFF0F6FFF);
                  size = 30;
                } else if (isDest) {
                  markerColor = const Color(0xFFD7263D);
                  size = 30;
                } else if (isHovered) {
                  markerColor = Colors.black87;
                  size = 26;
                } else if (!hasSelection || isActive) {
                  markerColor = getRouteColor(station.lines.isNotEmpty
                      ? station.lines.first
                      : '');
                } else {
                  markerColor = Colors.grey;
                }

                final opacity =
                    hasSelection && !isActive && !isHighlighted ? 0.25 : 1.0;

                return Positioned(
                  left: station.x * _mapImageWidth - size / 2,
                  top: station.y * _mapImageHeight - size / 2,
                  child: GestureDetector(
                    onTap: () => _onStationTap(station),
                    child: MouseRegion(
                      onEnter: (_) =>
                          setState(() => _hoveredStationId = station.stationId),
                      onExit: (_) =>
                          setState(() => _hoveredStationId = null),
                      child: Opacity(
                        opacity: opacity,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: markerColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isHighlighted
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.8),
                              width: isHighlighted ? 3 : 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: markerColor.withValues(alpha: 0.4),
                                blurRadius: isHighlighted ? 10 : 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: isHighlighted
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
                    ),
                  ),
                );
              }),
              if (_selectedStation != null)
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white.withValues(alpha: 0.94),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFDCE6F5)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.touch_app_rounded,
                              size: 18, color: Color(0xFF0A3A8B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Tap a station to view details, set as origin, or destination.',
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
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
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.trip_origin_rounded,
                                        size: 14, color: Color(0xFF0F6FFF)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        widget.stations
                                                .firstWhere(
                                                  (s) =>
                                                      s.stationId ==
                                                      widget
                                                          .selectedOriginId,
                                                )
                                                .name,
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
                                        size: 14, color: Color(0xFFD7263D)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        widget.stations
                                                .firstWhere(
                                                  (s) =>
                                                      s.stationId ==
                                                      widget
                                                          .selectedDestinationId,
                                                )
                                                .name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              widget.onOriginSelected?.call(
                                widget.stations.firstWhere(
                                  (s) =>
                                      s.stationId ==
                                      widget.selectedOriginId,
                                ),
                              );
                              widget.onDestinationSelected?.call(
                                widget.stations.firstWhere(
                                  (s) =>
                                      s.stationId ==
                                      widget.selectedDestinationId,
                                ),
                              );
                            },
                            icon: const Icon(Icons.route_rounded, size: 18),
                            label: const Text('Plan Route'),
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
    );
  }
}

class _LineSegment {
  final Offset from;
  final Offset to;
  final String line;
  final bool active;

  const _LineSegment({
    required this.from,
    required this.to,
    required this.line,
    required this.active,
  });
}

class _LinePainter extends CustomPainter {
  final List<_LineSegment> segments;
  final Set<String> activeLines;

  _LinePainter({required this.segments, required this.activeLines});

  @override
  void paint(Canvas canvas, Size size) {
    for (final segment in segments) {
      final fromPx = Offset(
        segment.from.dx * size.width,
        segment.from.dy * size.height,
      );
      final toPx = Offset(
        segment.to.dx * size.width,
        segment.to.dy * size.height,
      );

      final color = segment.active
          ? getRouteColor(segment.line)
          : Colors.grey;

      final paint = Paint()
        ..color = color.withValues(
            alpha: segment.active ? 0.85 : 0.15)
        ..strokeWidth = segment.active ? 5.0 : 2.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(fromPx, toPx, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.activeLines != activeLines;
}

class _StationActionSheet extends StatelessWidget {
  final MapStation station;
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
    final lineColor = getRouteColor(
      station.lines.isNotEmpty ? station.lines.first : '',
    );
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
                    color: lineColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    station.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                '${station.stationId} | ${station.lines.join(" / ")}',
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
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
                      icon:
                          const Icon(Icons.location_on_rounded, size: 18),
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
