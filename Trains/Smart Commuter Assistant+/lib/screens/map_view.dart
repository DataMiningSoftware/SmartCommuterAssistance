import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_info.dart';
import '../services/commuter_ml_service.dart';

class TransitStation {
  final String name;
  final String line;
  final Color color;
  final LatLng point;

  const TransitStation({
    required this.name,
    required this.line,
    required this.color,
    required this.point,
  });
}

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  final CommuterMlService _mlService = CommuterMlService();

  bool _loading = true;
  double _rainfallMm = 2.0;
  bool _eventNearby = false;
  String? _selectedStationName;

  static const LatLng _mapCenter = LatLng(3.1390, 101.6869); // Kuala Lumpur

  static const List<TransitStation> _stations = [
    TransitStation(
      name: 'Batu Caves',
      line: 'KTM Seremban',
      color: Color(0xFF1F3C98),
      point: LatLng(3.2379, 101.6840),
    ),
    TransitStation(
      name: 'Titiwangsa',
      line: 'LRT Ampang/Sri Petaling',
      color: Color(0xFF8C4A2F),
      point: LatLng(3.1748, 101.6959),
    ),
    TransitStation(
      name: 'KL Sentral',
      line: 'LRT Kelana Jaya',
      color: Color(0xFF0A57D5),
      point: LatLng(3.1346, 101.6860),
    ),
    TransitStation(
      name: 'Pasar Seni',
      line: 'MRT Kajang',
      color: Color(0xFF009A44),
      point: LatLng(3.1427, 101.6951),
    ),
    TransitStation(
      name: 'Masjid Jamek',
      line: 'LRT Kelana Jaya',
      color: Color(0xFFE53E3E),
      point: LatLng(3.1493, 101.6968),
    ),
    TransitStation(
      name: 'KLCC',
      line: 'LRT Kelana Jaya',
      color: Color(0xFFFFD100),
      point: LatLng(3.1579, 101.7123),
    ),
    TransitStation(
      name: 'Bukit Bintang',
      line: 'MRT Kajang',
      color: Color(0xFF1B7B3A),
      point: LatLng(3.1467, 101.7113),
    ),
    TransitStation(
      name: 'Merdeka',
      line: 'MRT Kajang',
      color: Color(0xFF2CA02C),
      point: LatLng(3.1422, 101.7035),
    ),
    TransitStation(
      name: 'Kajang',
      line: 'MRT Kajang',
      color: Color(0xFF0B4ABF),
      point: LatLng(2.9927, 101.7909),
    ),
  ];

  static const List<List<String>> _networkLines = [
    ['Batu Caves', 'Titiwangsa', 'KL Sentral'],
    ['KL Sentral', 'Pasar Seni', 'Merdeka', 'Bukit Bintang', 'KLCC'],
    ['Merdeka', 'Kajang'],
  ];

  late String _origin;
  late String _destination;
  List<RouteRecommendation> _recommendations = [];
  DelayCrowdPrediction? _prediction;

  @override
  void initState() {
    super.initState();
    _origin = 'KL Sentral';
    _destination = 'Kajang';
    _initialize();
  }

  Future<void> _initialize() async {
    await _mlService.initialize();
    _recompute();
    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _recompute() {
    final candidates = _buildCandidates(_origin, _destination);
    final recommended = _mlService.optimizeRoutes(
      departureTime: DateTime.now(),
      rainfallMm: _rainfallMm,
      temperatureC: 30,
      eventNearby: _eventNearby,
      candidates: candidates,
    );
    final best = recommended.first.route;
    final firstLine = best.steps.isEmpty ? 'MRT Kajang' : best.steps.first.line;
    final pred = _mlService.predict(
      OperationalSnapshot(
        station: _origin,
        line: firstLine,
        timestamp: DateTime.now(),
        rainfallMm: _rainfallMm,
        temperatureC: 30,
        eventNearby: _eventNearby,
      ),
    );

    setState(() {
      _recommendations = recommended;
      _prediction = pred;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bestRoute = _recommendations.isEmpty ? null : _recommendations.first.route;
    final highlightedStops = bestRoute == null ? [_origin, _destination] : _routeStops(bestRoute);
    final highlightedPoints = _pointsForNames(highlightedStops);
    final evaluation = _mlService.evaluation;
    final bestRecommendation = _recommendations.isEmpty ? null : _recommendations.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Map'),
        actions: [
          IconButton(
            tooltip: 'Scenario settings',
            onPressed: _loading ? null : _openScenarioSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _mapCenter,
                      initialZoom: 11.2,
                      minZoom: 8.5,
                      maxZoom: 17,
                      onTap: (_, __) => setState(() => _selectedStationName = null),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'smart_commuter_assistant',
                      ),
                      PolylineLayer(
                        polylines: _buildNetworkPolylines(highlightedStops),
                      ),
                      MarkerLayer(
                        markers: _buildStationMarkers(highlightedStops),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: _buildTopRouteCard(),
                ),
                Positioned(
                  right: 14,
                  bottom: 180,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'centerRouteBtn',
                        onPressed: highlightedPoints.isEmpty ? null : () => _zoomToRoute(highlightedPoints),
                        child: const Icon(Icons.center_focus_strong),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'centerMapBtn',
                        onPressed: () => _mapController.move(_mapCenter, 11.2),
                        child: const Icon(Icons.my_location),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _buildBottomInsightCard(
                    evaluation: evaluation,
                    bestRecommendation: bestRecommendation,
                  ),
                ),
              ],
            ),
    );
  }

  List<Polyline> _buildNetworkPolylines(List<String> highlightedStops) {
    final basePolylines = <Polyline>[];
    for (final line in _networkLines) {
      final points = _pointsForNames(line);
      if (points.length < 2) continue;
      basePolylines.add(
        Polyline(
          points: points,
          strokeWidth: 4,
          color: const Color(0xFF6C7A94).withValues(alpha: 0.38),
        ),
      );
    }

    final highlighted = _pointsForNames(highlightedStops);
    if (highlighted.length > 1) {
      basePolylines.add(
        Polyline(
          points: highlighted,
          strokeWidth: 10,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      );
      basePolylines.add(
        Polyline(
          points: highlighted,
          strokeWidth: 6,
          color: const Color(0xFF0A3A8B),
        ),
      );
    }
    return basePolylines;
  }

  List<Marker> _buildStationMarkers(List<String> highlightedStops) {
    return _stations.map((station) {
      final isHighlighted = highlightedStops.contains(station.name);
      return Marker(
        point: station.point,
        width: isHighlighted ? 54 : 32,
        height: isHighlighted ? 54 : 32,
        child: GestureDetector(
          onTap: () => setState(() => _selectedStationName = station.name),
          child: Container(
            decoration: BoxDecoration(
              color: isHighlighted ? station.color : Colors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(
                color: isHighlighted ? Colors.white : Colors.black26,
                width: isHighlighted ? 2.0 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: isHighlighted
                ? const Icon(Icons.train_rounded, color: Colors.white, size: 18)
                : Icon(Icons.circle, color: station.color, size: 10),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildTopRouteCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _origin,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: _stations.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                  onChanged: (value) {
                    if (value == null || value == _destination) return;
                    _origin = value;
                    _recompute();
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Swap',
                onPressed: () {
                  final temp = _origin;
                  _origin = _destination;
                  _destination = temp;
                  _recompute();
                },
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _destination,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: _stations.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                  onChanged: (value) {
                    if (value == null || value == _origin) return;
                    _destination = value;
                    _recompute();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricChip(Icons.cloudy_snowing, '${_rainfallMm.toStringAsFixed(1)}mm rain'),
              const SizedBox(width: 8),
              _metricChip(Icons.event_busy, _eventNearby ? 'Event nearby' : 'No event'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInsightCard({
    required ModelEvaluation evaluation,
    required RouteRecommendation? bestRecommendation,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDDE5F3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Live Prediction',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Delay ${_prediction?.predictedDelayMinutes.toStringAsFixed(1) ?? '--'} min • '
            'Crowd ${_prediction?.crowdLevel ?? '--'} • '
            'Confidence ${((_prediction?.confidence ?? 0) * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (bestRecommendation != null) ...[
            const SizedBox(height: 4),
            Text(
              'Best ETA ${bestRecommendation.adjustedMinutes.toStringAsFixed(1)} min',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
          if (_selectedStationName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Selected: $_selectedStationName',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'MAE ${evaluation.mae.toStringAsFixed(2)} • RMSE ${evaluation.rmse.toStringAsFixed(2)} • '
            'ACC ${(evaluation.crowdAccuracy * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF98A2B3)),
          ),
        ],
      ),
    );
  }

  Widget _metricChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5FB),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475467)),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475467),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openScenarioSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scenario Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Rainfall'),
                      Expanded(
                        child: Slider(
                          value: _rainfallMm,
                          min: 0,
                          max: 10,
                          divisions: 20,
                          label: '${_rainfallMm.toStringAsFixed(1)} mm',
                          onChanged: (value) {
                            setSheetState(() => _rainfallMm = value);
                            _recompute();
                          },
                        ),
                      ),
                      Text('${_rainfallMm.toStringAsFixed(1)} mm'),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Nearby Event'),
                    subtitle: const Text('Simulate event-driven congestion'),
                    value: _eventNearby,
                    onChanged: (value) {
                      setSheetState(() => _eventNearby = value);
                      _recompute();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<String> _routeStops(RouteInfo route) {
    final stops = <String>[route.origin];
    for (final step in route.steps) {
      if (!stops.contains(step.station)) {
        stops.add(step.station);
      }
    }
    if (!stops.contains(route.destination)) {
      stops.add(route.destination);
    }
    return stops;
  }

  List<LatLng> _pointsForNames(List<String> names) {
    final points = <LatLng>[];
    for (final name in names) {
      final station = _findStation(name);
      if (station != null) {
        points.add(station.point);
      }
    }
    return points;
  }

  TransitStation? _findStation(String name) {
    for (final station in _stations) {
      if (station.name == name) return station;
    }
    return null;
  }

  void _zoomToRoute(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 13.5);
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(
          LatLng(minLat, minLng),
          LatLng(maxLat, maxLng),
        ),
        padding: const EdgeInsets.all(40),
      ),
    );
  }

  List<RouteInfo> _buildCandidates(String origin, String destination) {
    return [
      RouteInfo(
        routeId: 'direct_mrt',
        origin: origin,
        destination: destination,
        steps: [
          RouteStep(
            type: RouteStepType.train,
            line: 'MRT Kajang',
            station: origin,
            durationMinutes: 26,
            instruction: 'Board MRT Kajang line to $destination',
          ),
          RouteStep(
            type: RouteStepType.train,
            line: 'MRT Kajang',
            station: destination,
            durationMinutes: 12,
            instruction: 'Continue to $destination',
          ),
        ],
        totalDurationMinutes: 38,
        totalDistance: 18.5,
        crowdLevel: 'Medium',
        fare: 3.5,
      ),
      RouteInfo(
        routeId: 'via_merdeka',
        origin: origin,
        destination: destination,
        steps: [
          RouteStep(
            type: RouteStepType.train,
            line: 'LRT Kelana Jaya',
            station: origin,
            durationMinutes: 10,
            instruction: 'Take LRT to Masjid Jamek',
          ),
          RouteStep(
            type: RouteStepType.transfer,
            line: 'MRT Kajang',
            station: 'Merdeka',
            durationMinutes: 4,
            instruction: 'Walk and transfer at Merdeka',
          ),
          RouteStep(
            type: RouteStepType.train,
            line: 'MRT Kajang',
            station: destination,
            durationMinutes: 16,
            instruction: 'Continue to $destination',
          ),
        ],
        totalDurationMinutes: 35,
        totalDistance: 16.8,
        crowdLevel: 'High',
        fare: 3.8,
      ),
      RouteInfo(
        routeId: 'via_klsentral',
        origin: origin,
        destination: destination,
        steps: [
          RouteStep(
            type: RouteStepType.train,
            line: 'KTM Seremban',
            station: origin,
            durationMinutes: 8,
            instruction: 'Take KTM to KL Sentral',
          ),
          RouteStep(
            type: RouteStepType.transfer,
            line: 'MRT Kajang',
            station: 'KL Sentral',
            durationMinutes: 5,
            instruction: 'Transfer at KL Sentral',
          ),
          RouteStep(
            type: RouteStepType.train,
            line: 'MRT Kajang',
            station: destination,
            durationMinutes: 17,
            instruction: 'Continue to $destination',
          ),
        ],
        totalDurationMinutes: 34,
        totalDistance: 17.1,
        crowdLevel: 'Medium',
        fare: 3.6,
      ),
    ];
  }
}
