import 'dart:collection';

import 'package:flutter/material.dart';

import '../widgets/crowd_indicator.dart';

class _StationNode {
  final String name;
  final Offset point;

  const _StationNode({
    required this.name,
    required this.point,
  });
}

class RoutePlanner extends StatefulWidget {
  const RoutePlanner({super.key});

  @override
  State<RoutePlanner> createState() => _RoutePlannerState();
}

class _RoutePlannerState extends State<RoutePlanner> {
  static const List<_StationNode> _stations = [
    _StationNode(name: 'Batu Caves', point: Offset(0.54, 0.19)),
    _StationNode(name: 'Titiwangsa', point: Offset(0.57, 0.34)),
    _StationNode(name: 'KL Sentral', point: Offset(0.50, 0.52)),
    _StationNode(name: 'Pasar Seni', point: Offset(0.56, 0.52)),
    _StationNode(name: 'Masjid Jamek', point: Offset(0.59, 0.44)),
    _StationNode(name: 'KLCC', point: Offset(0.68, 0.35)),
    _StationNode(name: 'Bukit Bintang', point: Offset(0.65, 0.41)),
    _StationNode(name: 'Merdeka', point: Offset(0.61, 0.47)),
    _StationNode(name: 'Kajang', point: Offset(0.84, 0.69)),
  ];

  static const List<List<String>> _edges = [
    ['Batu Caves', 'Titiwangsa'],
    ['Titiwangsa', 'KL Sentral'],
    ['KL Sentral', 'Pasar Seni'],
    ['Pasar Seni', 'Merdeka'],
    ['Merdeka', 'Bukit Bintang'],
    ['Bukit Bintang', 'KLCC'],
    ['Merdeka', 'Kajang'],
    ['KL Sentral', 'Masjid Jamek'],
    ['Masjid Jamek', 'KLCC'],
    ['Masjid Jamek', 'Pasar Seni'],
  ];

  late String _origin;
  late String _destination;
  List<String> _routeStations = [];

  @override
  void initState() {
    super.initState();
    _origin = 'KL Sentral';
    _destination = 'Kajang';
    _routeStations = _computeShortestPath(_origin, _destination);
  }

  @override
  Widget build(BuildContext context) {
    final estimatedMinutes = (_routeStations.length <= 1 ? 0 : (_routeStations.length - 1) * 6) + 4;
    final routeLabel = _routeStations.isEmpty ? 'No route found' : _routeStations.join(' -> ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Planner'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _origin,
                        decoration: const InputDecoration(labelText: 'From station'),
                        items: _stations
                            .map((s) => DropdownMenuItem(value: s.name, child: Text(s.name)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null || value == _destination) return;
                          setState(() {
                            _origin = value;
                            _routeStations = _computeShortestPath(_origin, _destination);
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Swap',
                      onPressed: () {
                        setState(() {
                          final temp = _origin;
                          _origin = _destination;
                          _destination = temp;
                          _routeStations = _computeShortestPath(_origin, _destination);
                        });
                      },
                      icon: const Icon(Icons.swap_horiz_rounded),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _destination,
                        decoration: const InputDecoration(labelText: 'To station'),
                        items: _stations
                            .map((s) => DropdownMenuItem(value: s.name, child: Text(s.name)))
                            .toList(),
                        onChanged: (value) {
                          if (value == null || value == _origin) return;
                          setState(() {
                            _destination = value;
                            _routeStations = _computeShortestPath(_origin, _destination);
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE1E8F6)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recommended Route',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(routeLabel),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text('Estimated Time: $estimatedMinutes minutes'),
                          const Spacer(),
                          const CrowdIndicator(level: 'Medium'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4.2,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final points = _buildRoutePoints(
                        _routeStations,
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/images/klang_valley_map.png',
                            fit: BoxFit.cover,
                          ),
                          Container(color: Colors.black.withValues(alpha: 0.28)),
                          CustomPaint(
                            painter: _RouteOnImagePainter(
                              stations: _stations,
                              highlightedStations: _routeStations,
                              routePoints: points,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Offset> _buildRoutePoints(List<String> names, double width, double height) {
    final points = <Offset>[];
    for (final name in names) {
      for (final station in _stations) {
        if (station.name == name) {
          points.add(Offset(station.point.dx * width, station.point.dy * height));
          break;
        }
      }
    }
    return points;
  }

  List<String> _computeShortestPath(String origin, String destination) {
    if (origin == destination) return [origin];

    final adjacency = <String, List<String>>{};
    for (final station in _stations) {
      adjacency[station.name] = [];
    }
    for (final edge in _edges) {
      final a = edge[0];
      final b = edge[1];
      adjacency[a]!.add(b);
      adjacency[b]!.add(a);
    }

    final queue = Queue<String>()..add(origin);
    final visited = <String>{origin};
    final previous = <String, String?>{origin: null};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current == destination) break;
      for (final next in adjacency[current]!) {
        if (!visited.contains(next)) {
          visited.add(next);
          previous[next] = current;
          queue.add(next);
        }
      }
    }

    if (!previous.containsKey(destination)) return [];
    final path = <String>[];
    String? walk = destination;
    while (walk != null) {
      path.add(walk);
      walk = previous[walk];
    }
    return path.reversed.toList();
  }
}

class _RouteOnImagePainter extends CustomPainter {
  final List<_StationNode> stations;
  final List<String> highlightedStations;
  final List<Offset> routePoints;

  _RouteOnImagePainter({
    required this.stations,
    required this.highlightedStations,
    required this.routePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (routePoints.length > 1) {
      final routePath = Path()..moveTo(routePoints.first.dx, routePoints.first.dy);
      for (var i = 1; i < routePoints.length; i++) {
        routePath.lineTo(routePoints[i].dx, routePoints[i].dy);
      }

      canvas.drawPath(
        routePath,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.95)
          ..strokeWidth = 11
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        routePath,
        Paint()
          ..color = const Color(0xFFFFD100)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    for (final station in stations) {
      final isHighlighted = highlightedStations.contains(station.name);
      final point = Offset(station.point.dx * size.width, station.point.dy * size.height);
      canvas.drawCircle(
        point,
        isHighlighted ? 7 : 4,
        Paint()..color = isHighlighted ? const Color(0xFF00D084) : Colors.white.withValues(alpha: 0.58),
      );

      if (isHighlighted) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: station.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, point + const Offset(8, -16));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RouteOnImagePainter oldDelegate) {
    return oldDelegate.highlightedStations != highlightedStations || oldDelegate.routePoints != routePoints;
  }
}
