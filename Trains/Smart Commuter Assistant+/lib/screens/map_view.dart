import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_info.dart';
import '../models/transit_graph.dart';
import '../models/transit_line_style.dart';
import '../services/backend_config_service.dart';
import '../services/commuter_ml_service.dart';
import '../services/transit_planner_service.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  final Distance _distance = const Distance();
  final BackendConfigService _backendConfig = BackendConfigService();
  late TransitPlannerService _planner;

  bool _loading = true;
  String? _errorMessage;
  double _rainfallMm = 2.0;
  bool _eventNearby = false;
  String? _selectedStationName;
  bool _locating = false;
  LatLng? _userLocation;
  TransitStationNode? _nearestStation;
  double? _nearestDistanceMeters;
  double? _locationAccuracyMeters;
  DateTime? _locationUpdatedAt;
  String? _locationError;

  late TransitGraph _graph;
  late String _origin;
  String? _destination;

  List<RouteRecommendation> _recommendations = <RouteRecommendation>[];
  DelayCrowdPrediction? _prediction;

  static const LatLng _mapCenter = LatLng(3.1390, 101.6869);

  @override
  void initState() {
    super.initState();
    _planner = _buildPlanner(_backendConfig.baseUrl.value);
    _backendConfig.baseUrl.addListener(_onBackendChanged);
    _graph = _planner.graph;
    _origin = 'KL Sentral';
    _destination = null;
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

    try {
      await _planner.mlService.initialize();
      await _refreshLocation(centerMap: false);
      await _recompute();
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Unable to load map planning data.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _recompute() async {
    if (_destination == null || _destination == _origin) {
      if (!mounted) return;
      setState(() {
        _recommendations = <RouteRecommendation>[];
        _prediction = null;
        _errorMessage = null;
      });
      return;
    }

    try {
      final result = await _planner.planTrip(
        TransitPlanRequest(
          originId: _origin,
          destinationId: _destination!,
          departureTime: DateTime.now(),
          rainfallMm: _rainfallMm,
          eventNearby: _eventNearby,
        ),
      );
      if (!mounted) return;
      setState(() {
        _recommendations = result.ranked;
        _prediction = result.originPrediction;
        _errorMessage = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to update route predictions.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bestRoute =
        _recommendations.isEmpty ? null : _recommendations.first.route;
    final highlightedStops = bestRoute == null
        ? <String>[
            _origin,
            if (_destination != null) _destination!,
          ]
        : _routeStops(bestRoute);
    final highlightedPoints = _pointsForNames(highlightedStops);
    final evaluation = _planner.mlService.evaluation;
    final bestRecommendation =
        _recommendations.isEmpty ? null : _recommendations.first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Map'),
        actions: [
          IconButton(
            tooltip: 'Backend URL',
            onPressed: _openBackendSheet,
            icon: const Icon(Icons.cloud_outlined),
          ),
          IconButton(
            tooltip: 'Scenario settings',
            onPressed: _loading ? null : _openScenarioSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null && _recommendations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _initialize,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
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
                          onTap: (_, __) =>
                              setState(() => _selectedStationName = null),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'smart_commuter_assistant',
                          ),
                          PolylineLayer(
                              polylines:
                                  _buildNetworkPolylines(highlightedStops)),
                          MarkerLayer(
                              markers: _buildStationMarkers(highlightedStops)),
                          if (_userLocation != null)
                            MarkerLayer(markers: _buildUserMarker()),
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
                            onPressed: highlightedPoints.isEmpty
                                ? null
                                : () => _zoomToRoute(highlightedPoints),
                            child: const Icon(Icons.center_focus_strong),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'centerMapBtn',
                            onPressed: _locating
                                ? null
                                : () => _refreshLocation(centerMap: true),
                            child: _locating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.my_location),
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
                )),
    );
  }

  List<Polyline> _buildNetworkPolylines(List<String> highlightedStops) {
    final polylines = <Polyline>[];
    for (final corridor in _graph.lineCorridors) {
      final points = _pointsForNames(corridor);
      if (points.length < 2) continue;
      polylines.add(
        Polyline(
          points: points,
          strokeWidth: 4,
          color: const Color(0xFF6C7A94).withValues(alpha: 0.35),
        ),
      );
    }

    final highlighted = _pointsForNames(highlightedStops);
    if (highlighted.length > 1) {
      polylines.add(
        Polyline(
          points: highlighted,
          strokeWidth: 10,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      );
      polylines.add(
        Polyline(
          points: highlighted,
          strokeWidth: 6,
          color: const Color(0xFF0A3A8B),
        ),
      );
    }

    return polylines;
  }

  List<Marker> _buildStationMarkers(List<String> highlightedStops) {
    return _graph.stations.map((station) {
      final isHighlighted = highlightedStops.contains(station.id);
      return Marker(
        point: LatLng(station.latitude, station.longitude),
        width: isHighlighted ? 54 : 32,
        height: isHighlighted ? 54 : 32,
        child: GestureDetector(
          onTap: () => setState(() => _selectedStationName = station.name),
          child: Container(
            decoration: BoxDecoration(
              color: isHighlighted
                  ? _lineColor(station.line)
                  : Colors.white.withValues(alpha: 0.92),
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
                : Icon(Icons.circle, color: _lineColor(station.line), size: 10),
          ),
        ),
      );
    }).toList();
  }

  List<Marker> _buildUserMarker() {
    final point = _userLocation;
    if (point == null) return const <Marker>[];
    return <Marker>[
      Marker(
        point: point,
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0A57D5),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _buildTopRouteCard() {
    final stationNames = _graph.stationIds;
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
                  key: ValueKey<String>('from_$_origin'),
                  initialValue: _origin,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: stationNames
                      .map((name) => DropdownMenuItem<String>(
                          value: name, child: Text(name)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null || value == _destination) return;
                    setState(() {
                      _origin = value;
                      if (_destination == _origin) {
                        _destination = null;
                      }
                    });
                    _recompute();
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Swap',
                onPressed: _destination == null
                    ? null
                    : () {
                        setState(() {
                          final temp = _origin;
                          _origin = _destination!;
                          _destination = temp;
                        });
                        _recompute();
                      },
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey<String>('to_${_destination ?? 'none'}'),
                  initialValue: _destination,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Select destination'),
                    ),
                    ...stationNames.map(
                      (name) => DropdownMenuItem<String?>(
                          value: name, child: Text(name)),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == _origin) return;
                    setState(() {
                      _destination = value;
                    });
                    _recompute();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _metricChip(Icons.cloudy_snowing,
                  '${_rainfallMm.toStringAsFixed(1)}mm rain'),
              const SizedBox(width: 8),
              _metricChip(
                  Icons.event_busy, _eventNearby ? 'Event nearby' : 'No event'),
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
            'Delay ${_prediction?.predictedDelayMinutes.toStringAsFixed(1) ?? '--'} min | '
            'Crowd ${_prediction?.crowdLevel ?? '--'} | '
            'Confidence ${((_prediction?.confidence ?? 0) * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (bestRecommendation != null) ...[
            const SizedBox(height: 4),
            Text(
              'Best ETA ${bestRecommendation.adjustedMinutes.toStringAsFixed(1)} min',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: bestRecommendation.route.steps
                  .map((step) => _lineGuideChip(step.line, step.station))
                  .toList(),
            ),
          ],
          if (_selectedStationName != null) ...[
            const SizedBox(height: 4),
            Text(
              'Selected: $_selectedStationName',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
          if (_nearestStation != null && _nearestDistanceMeters != null) ...[
            const SizedBox(height: 4),
            Text(
              'Nearest station: ${_nearestStation!.name} (${_nearestDistanceMeters!.toStringAsFixed(0)}m)',
              style: const TextStyle(
                  color: Color(0xFF344054), fontWeight: FontWeight.w600),
            ),
          ],
          if (_locationAccuracyMeters != null ||
              _locationUpdatedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'GPS accuracy: ${_locationAccuracyMeters?.toStringAsFixed(0) ?? '--'}m'
              ' | Updated: ${_locationUpdatedAt != null ? _formatTime(_locationUpdatedAt!) : '--'}',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF98A2B3)),
            ),
          ],
          if (_locationError != null) ...[
            const SizedBox(height: 4),
            Text(
              _locationError!,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB42318)),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'MAE ${evaluation.mae.toStringAsFixed(2)} | RMSE ${evaluation.rmse.toStringAsFixed(2)} | '
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

  Widget _lineGuideChip(String line, String station) {
    final color = TransitLineStyle.colorForLine(line);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
              fontSize: 11,
              fontWeight: FontWeight.w700,
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

  List<LatLng> _pointsForNames(List<String> names) {
    final points = <LatLng>[];
    for (final stationId in names) {
      final station = _graph.station(stationId);
      if (station != null) {
        points.add(LatLng(station.latitude, station.longitude));
      }
    }
    return points;
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

  Color _lineColor(String line) {
    return TransitLineStyle.colorForLine(line);
  }

  Future<void> _refreshLocation({required bool centerMap}) async {
    setState(() {
      _locating = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location service is disabled on this device.');
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
      final user = LatLng(position.latitude, position.longitude);

      TransitStationNode? nearest;
      double? nearestMeters;
      for (final station in _graph.stations) {
        final stationPoint = LatLng(station.latitude, station.longitude);
        final meters = _distance.as(LengthUnit.Meter, user, stationPoint);
        if (nearestMeters == null || meters < nearestMeters) {
          nearestMeters = meters;
          nearest = station;
        }
      }

      if (!mounted) return;
      setState(() {
        _userLocation = user;
        _nearestStation = nearest;
        if (nearest != null) {
          _origin = nearest.id;
          if (_destination == _origin) {
            _destination = null;
          }
        }
        _nearestDistanceMeters = nearestMeters;
        _locationAccuracyMeters = position.accuracy;
        _locationUpdatedAt = DateTime.now();
      });

      await _recompute();

      if (centerMap) {
        _mapController.move(user, 13.8);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locationError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _locating = false);
      }
    }
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
