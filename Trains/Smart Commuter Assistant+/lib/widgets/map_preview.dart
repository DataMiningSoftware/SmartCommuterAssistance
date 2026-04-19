import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_shadows.dart';
import '../constants/route_colors.dart';

class MapPreviewStop {
  final String stopId;
  final String stationName;
  final List<String> routeIds;
  final double latitude;
  final double longitude;
  final bool isNearest;
  final bool isCurrent;
  final bool isNext;
  final bool isDestination;

  const MapPreviewStop({
    required this.stopId,
    required this.stationName,
    required this.routeIds,
    required this.latitude,
    required this.longitude,
    this.isNearest = false,
    this.isCurrent = false,
    this.isNext = false,
    this.isDestination = false,
  });
}

class MapPreviewSegment {
  final String fromStopId;
  final String toStopId;
  final String routeId;

  const MapPreviewSegment({
    required this.fromStopId,
    required this.toStopId,
    required this.routeId,
  });
}

class MapPreview extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<MapPreviewStop> stops;
  final List<MapPreviewSegment> highlightedSegments;
  final VoidCallback? onOpenMap;
  final VoidCallback? onLocateMe;
  final Function(MapPreviewStop)? onStationTapped;

  const MapPreview({
    super.key,
    required this.title,
    required this.subtitle,
    required this.stops,
    required this.highlightedSegments,
    this.onOpenMap,
    this.onLocateMe,
    this.onStationTapped,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
          boxShadow: appCardShadows(context, prominent: true),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: onOpenMap,
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text('Full map'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onLocateMe,
                      icon: const Icon(Icons.my_location_rounded, size: 18),
                      label: const Text('Locate me'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              height: 290,
                decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF5F8FF),
                    Color(0xFFEEF4FF),
                    Color(0xFFF8FBFF),
                  ],
                ),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.06)),
              ),
              child: stops.isEmpty
                  ? const Center(
                      child: Text(
                        'Map data unavailable.',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onTapUp: (details) {
                              _handleStationTap(
                                context,
                                details.localPosition,
                                Size(constraints.maxWidth,
                                    constraints.maxHeight),
                              );
                            },
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _MapPreviewPainter(
                                      stops: stops,
                                      segments: highlightedSegments,
                                    ),
                                  ),
                                ),
                                ..._buildPinnedLabels(
                                  context: context,
                                  stops: stops,
                                  size: Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _LegendPill(
                  label: 'You',
                  icon: Icons.my_location_rounded,
                  color: Color(0xFF0F6FFF),
                ),
                _LegendPill(
                  label: 'Nearest',
                  icon: Icons.near_me_rounded,
                  color: Color(0xFF111827),
                ),
                _LegendPill(
                  label: 'Next stop',
                  icon: Icons.flag_rounded,
                  color: Color(0xFFF59E0B),
                ),
                _LegendPill(
                  label: 'Destination',
                  icon: Icons.place_rounded,
                  color: Color(0xFFDC2626),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPinnedLabels({
    required BuildContext context,
    required List<MapPreviewStop> stops,
    required Size size,
  }) {
    if (stops.isEmpty) return const <Widget>[];
    final bounds = _LatLonBounds.fromStops(stops);
    final keyStops = stops.where((stop) {
      return stop.isCurrent ||
          stop.isNext ||
          stop.isDestination ||
          stop.isNearest;
    }).toList();
    return keyStops.map((stop) {
      final point = bounds.project(stop.latitude, stop.longitude, size);
      final routeId = stop.routeIds.isEmpty ? 'N/A' : stop.routeIds.first;
            return Positioned(
        left: point.dx.clamp(8.0, math.max(8.0, size.width - 108.0)),
        top: (point.dy - 36).clamp(8.0, math.max(8.0, size.height - 44.0)),
        child: IgnorePointer(
            child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.12)),
              boxShadow: appCardShadows(context),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: getRouteColor(routeId),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  stop.stationName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  void _handleStationTap(
      BuildContext context, Offset tapPosition, Size mapSize) {
    final bounds = _LatLonBounds.fromStops(stops);
    const tapRadius = 30.0;

    MapPreviewStop? closestStop;
    double closestDistance = double.infinity;

    for (final stop in stops) {
      final point = bounds.project(stop.latitude, stop.longitude, mapSize);
      final distance = (tapPosition - point).distance;
      if (distance < closestDistance && distance < tapRadius) {
        closestDistance = distance;
        closestStop = stop;
      }
    }

    if (closestStop != null) {
      onStationTapped?.call(closestStop);
    }
  }
}

class _MapPreviewPainter extends CustomPainter {
  final List<MapPreviewStop> stops;
  final List<MapPreviewSegment> segments;

  const _MapPreviewPainter({
    required this.stops,
    required this.segments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _LatLonBounds.fromStops(stops);
    final pointsByStopId = <String, Offset>{};
    for (final stop in stops) {
      pointsByStopId[stop.stopId] =
          bounds.project(stop.latitude, stop.longitude, size);
    }

    _paintGrid(canvas, size);
    _paintHighlightedSegments(canvas, pointsByStopId);
    _paintStops(canvas, pointsByStopId);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD6E1F3).withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i <= 5; i++) {
      final dx = size.width * i / 6;
      final dy = size.height * i / 6;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  void _paintHighlightedSegments(
    Canvas canvas,
    Map<String, Offset> pointsByStopId,
  ) {
    for (final segment in segments) {
      final from = pointsByStopId[segment.fromStopId];
      final to = pointsByStopId[segment.toStopId];
      if (from == null || to == null) continue;

      final glow = Paint()
        ..color = getRouteColor(segment.routeId).withValues(alpha: 0.20)
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final line = Paint()
        ..color = getRouteColor(segment.routeId)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawLine(from, to, glow);
      canvas.drawLine(from, to, line);
    }
  }

  void _paintStops(Canvas canvas, Map<String, Offset> pointsByStopId) {
    for (final stop in stops) {
      final point = pointsByStopId[stop.stopId];
      if (point == null) continue;
      final routeId = stop.routeIds.isEmpty ? 'N/A' : stop.routeIds.first;
      final color = getRouteColor(routeId);

      if (stop.isNearest ||
          stop.isCurrent ||
          stop.isNext ||
          stop.isDestination) {
        final halo = Paint()
          ..color = color.withValues(alpha: 0.16)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(point, stop.isCurrent ? 18 : 14, halo);
      }

      final border = Paint()
        ..color = Colors.white
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      final fill = Paint()
        ..color = stop.isCurrent
            ? const Color(0xFF0F6FFF)
            : stop.isDestination
                ? const Color(0xFFDC2626)
                : stop.isNext
                    ? const Color(0xFFF59E0B)
                    : stop.isNearest
                        ? const Color(0xFF111827)
                        : color.withValues(alpha: 0.88)
        ..style = PaintingStyle.fill;

      final radius = stop.isCurrent
          ? 8.5
          : stop.isDestination
              ? 7.0
              : stop.isNext
                  ? 6.5
                  : stop.isNearest
                      ? 6.0
                      : 3.4;
      canvas.drawCircle(point, radius, fill);
      if (radius >= 6) {
        canvas.drawCircle(point, radius, border);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) {
    return oldDelegate.stops != stops || oldDelegate.segments != segments;
  }
}

class _LegendPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _LegendPill({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatLonBounds {
  final double minLat;
  final double maxLat;
  final double minLon;
  final double maxLon;

  const _LatLonBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  factory _LatLonBounds.fromStops(List<MapPreviewStop> stops) {
    var minLat = stops.first.latitude;
    var maxLat = stops.first.latitude;
    var minLon = stops.first.longitude;
    var maxLon = stops.first.longitude;

    for (final stop in stops.skip(1)) {
      minLat = math.min(minLat, stop.latitude);
      maxLat = math.max(maxLat, stop.latitude);
      minLon = math.min(minLon, stop.longitude);
      maxLon = math.max(maxLon, stop.longitude);
    }

    return _LatLonBounds(
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
    );
  }

  Offset project(double lat, double lon, Size size) {
    final lonRange = math.max(0.0001, maxLon - minLon);
    final latRange = math.max(0.0001, maxLat - minLat);
    const padding = 26.0;
    final usableWidth = math.max(1.0, size.width - padding * 2);
    final usableHeight = math.max(1.0, size.height - padding * 2);
    final x = ((lon - minLon) / lonRange) * usableWidth + padding;
    final y = ((maxLat - lat) / latRange) * usableHeight + padding;
    return Offset(x, y);
  }
}
