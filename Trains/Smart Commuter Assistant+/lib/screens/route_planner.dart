import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/route_info.dart';
import '../models/transit_graph.dart';
import '../models/transit_line_style.dart';
import '../services/backend_config_service.dart';
import '../services/commuter_ml_service.dart';
import '../services/transit_planner_service.dart';
import '../widgets/crowd_indicator.dart';

class RoutePlanner extends StatefulWidget {
  const RoutePlanner({super.key});

  @override
  State<RoutePlanner> createState() => _RoutePlannerState();
}

class _RoutePlannerState extends State<RoutePlanner> {
  final BackendConfigService _backendConfig = BackendConfigService();
  final ll.Distance _distance = const ll.Distance();

  late TransitPlannerService _planner;
  late TransitGraph _graph;

  String? _origin;
  String? _destination;

  bool _loading = true;
  bool _locating = false;
  String? _errorMessage;
  String? _locationError;
  TransitStationNode? _nearestStation;
  double? _nearestDistanceMeters;
  ll.LatLng? _userLocation;
  DateTime? _locationUpdatedAt;
  RouteRecommendation? _bestRecommendation;

  @override
  void initState() {
    super.initState();
    _planner = _buildPlanner(_backendConfig.baseUrl.value);
    _backendConfig.baseUrl.addListener(_onBackendChanged);
    _graph = _planner.graph;
    _initialize();
  }

  @override
  void dispose() {
    _backendConfig.baseUrl.removeListener(_onBackendChanged);
    super.dispose();
  }

  TransitPlannerService _buildPlanner(String baseUrl) {
    final graph = TransitGraph.klangValleyDemo();
    return TransitPlannerService(
      gateway: ResilientTransitPlanningGateway(
        primary: ApiTransitPlanningGateway(
          graph: graph,
          baseUrl: baseUrl,
        ),
        fallback: LocalTransitPlanningGateway(graph: graph),
      ),
      mlService: CommuterMlService(),
    );
  }

  void _onBackendChanged() {
    _planner = _buildPlanner(_backendConfig.baseUrl.value);
    _graph = _planner.graph;
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    await _setNearestOrigin();
    await _loadBestRoute();
  }

  Future<void> _refreshNearestOrigin() async {
    await _setNearestOrigin();
    await _loadBestRoute();
  }

  Future<void> _setNearestOrigin() async {
    if (!mounted) return;
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location service is disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied.');
      }

      final lastKnown = await Geolocator.getLastKnownPosition();
      final position = lastKnown ??
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
      final user = ll.LatLng(position.latitude, position.longitude);

      TransitStationNode? nearest;
      double? nearestMeters;
      for (final station in _graph.stations) {
        final meters = _distance.as(
          ll.LengthUnit.Meter,
          user,
          ll.LatLng(station.latitude, station.longitude),
        );
        if (nearestMeters == null || meters < nearestMeters) {
          nearestMeters = meters;
          nearest = station;
        }
      }

      if (!mounted || nearest == null) return;
      setState(() {
        _nearestStation = nearest;
        _nearestDistanceMeters = nearestMeters;
        _userLocation = user;
        _locationUpdatedAt = DateTime.now();
        _origin = nearest!.id;
        if (_destination == _origin) {
          _destination = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = e.toString().replaceFirst('Exception: ', '');
        _origin ??= 'KL Sentral';
      });
    } finally {
      if (mounted) {
        setState(() {
          _locating = false;
        });
      }
    }
  }

  Future<void> _loadBestRoute() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
      _bestRecommendation = null;
    });

    if (_origin == null || _destination == null || _origin == _destination) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      final result = await _planner.planTrip(
        TransitPlanRequest(
          originId: _origin!,
          destinationId: _destination!,
          departureTime: DateTime.now(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _bestRecommendation =
            result.ranked.isNotEmpty ? result.ranked.first : null;
        if (_bestRecommendation == null) {
          _errorMessage =
              'No route found for these stations in the current demo network.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _bestRecommendation = null;
        _errorMessage = 'Unable to load route right now.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedRoute = _bestRecommendation?.route;
    final routeStations =
        selectedRoute == null ? <String>[] : _routeStops(selectedRoute);
    final estimatedMinutes = selectedRoute?.totalDurationMinutes ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Planner'),
        actions: [
          IconButton(
            tooltip: 'Use current location',
            onPressed: _locating ? null : _refreshNearestOrigin,
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
          IconButton(
            tooltip: 'Backend URL',
            onPressed: _openBackendSheet,
            icon: const Icon(Icons.cloud_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey<String>(
                                  'planner_from_${_origin ?? 'none'}'),
                              initialValue: _origin,
                              decoration: const InputDecoration(
                                labelText:
                                    'From station (nearest auto-selected)',
                              ),
                              items: _graph.stationIds
                                  .map((id) => DropdownMenuItem<String>(
                                      value: id, child: Text(id)))
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() {
                                  _origin = value;
                                  if (_destination == _origin) {
                                    _destination = null;
                                  }
                                });
                                _loadBestRoute();
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Swap',
                            onPressed: (_origin == null || _destination == null)
                                ? null
                                : () {
                                    setState(() {
                                      final temp = _origin;
                                      _origin = _destination;
                                      _destination = temp;
                                    });
                                    _loadBestRoute();
                                  },
                            icon: const Icon(Icons.swap_horiz_rounded),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<String?>(
                              key: ValueKey<String>(
                                  'planner_to_${_destination ?? 'none'}'),
                              initialValue: _destination,
                              decoration: const InputDecoration(
                                  labelText: 'To station (required)'),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('Select destination'),
                                ),
                                ..._graph.stationIds.map(
                                  (id) => DropdownMenuItem<String?>(
                                      value: id, child: Text(id)),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == _origin) return;
                                setState(() {
                                  _destination = value;
                                });
                                _loadBestRoute();
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_nearestStation != null &&
                          _nearestDistanceMeters != null) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Nearest station: ${_nearestStation!.name} (${_nearestDistanceMeters!.toStringAsFixed(0)}m)',
                            style: const TextStyle(
                              color: Color(0xFF475467),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      if (_userLocation != null) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'GPS: ${_userLocation!.latitude.toStringAsFixed(5)}, ${_userLocation!.longitude.toStringAsFixed(5)}'
                            '${_locationUpdatedAt != null ? ' | Updated ${_formatTime(_locationUpdatedAt!)}' : ''}',
                            style: const TextStyle(
                              color: Color(0xFF98A2B3),
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                      if (_locationError != null) ...[
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _locationError!,
                            style: const TextStyle(
                              color: Color(0xFFB42318),
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_destination == null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE1E8F6)),
                          ),
                          child: const Text(
                            'Select your destination station to calculate the best route.',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        )
                      else if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFF1D0CF)),
                          ),
                          child: Text(_errorMessage!,
                              style: const TextStyle(color: Color(0xFFB42318))),
                        )
                      else if (selectedRoute != null)
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
                                'Best Route (Most Efficient)',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(routeStations.join(' -> ')),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded,
                                      size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                      'Estimated Time: $estimatedMinutes minutes'),
                                  const Spacer(),
                                  CrowdIndicator(
                                      level: selectedRoute.crowdLevel),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      children: [
                        if (selectedRoute != null)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE1E8F6)),
                            ),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectedRoute.steps
                                  .map((step) =>
                                      _lineGuideChip(step.line, step.station))
                                  .toList(),
                            ),
                          ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4.2,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final points = _buildRoutePoints(
                                    routeStations,
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
                                      Container(
                                          color: Colors.black
                                              .withValues(alpha: 0.28)),
                                      CustomPaint(
                                        painter: _RouteOnImagePainter(
                                          graph: _graph,
                                          highlightedStations: routeStations,
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _openBackendSheet() async {
    final controller =
        TextEditingController(text: _backendConfig.baseUrl.value);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Backend URL',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...BackendConfigService.defaults.map((target) {
                final selected = _backendConfig.baseUrl.value == target.baseUrl;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(target.label),
                  subtitle: Text(target.baseUrl),
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: Color(0xFF0A3A8B))
                      : null,
                  onTap: () {
                    _backendConfig.setBaseUrl(target.baseUrl);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 6),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Custom URL',
                  hintText: 'http://192.168.x.x:8000',
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    _backendConfig.setBaseUrl(controller.text);
                    Navigator.pop(context);
                  },
                  child: const Text('Use This URL'),
                ),
              ),
            ],
          ),
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

  Widget _lineGuideChip(String line, String station) {
    final color = TransitLineStyle.colorForLine(line);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$line -> $station',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  List<Offset> _buildRoutePoints(
      List<String> names, double width, double height) {
    final points = <Offset>[];
    for (final stationId in names) {
      final station = _graph.station(stationId);
      if (station == null) continue;
      points.add(Offset(station.mapX * width, station.mapY * height));
    }
    return points;
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _RouteOnImagePainter extends CustomPainter {
  final TransitGraph graph;
  final List<String> highlightedStations;
  final List<Offset> routePoints;

  _RouteOnImagePainter({
    required this.graph,
    required this.highlightedStations,
    required this.routePoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (routePoints.length > 1) {
      final routePath = Path()
        ..moveTo(routePoints.first.dx, routePoints.first.dy);
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
          ..color = const Color(0xFF0A3A8B)
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    for (final station in graph.stations) {
      final isHighlighted = highlightedStations.contains(station.id);
      final point =
          Offset(station.mapX * size.width, station.mapY * size.height);
      canvas.drawCircle(
        point,
        isHighlighted ? 7 : 4,
        Paint()
          ..color = isHighlighted
              ? const Color(0xFF00D084)
              : Colors.white.withValues(alpha: 0.58),
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
    return oldDelegate.highlightedStations != highlightedStations ||
        oldDelegate.routePoints != routePoints;
  }
}
