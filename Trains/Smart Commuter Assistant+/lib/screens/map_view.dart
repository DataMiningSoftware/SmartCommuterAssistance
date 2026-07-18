import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../models/transit_graph.dart';
import '../services/active_trip_service.dart';
import '../services/crowd_reports_service.dart';
import '../services/transit_data_service.dart';
import '../services/transit_network_service.dart';
import '../services/route_selection_service.dart';
import '../widgets/app_page_title.dart';
import '../widgets/scheduled_arrivals_panel.dart';
import '../widgets/schematic_transit_map.dart';

class MapView extends StatefulWidget {
  final String? initialDestinationName;
  final String? preferredRouteType;

  const MapView({
    super.key,
    this.initialDestinationName,
    this.preferredRouteType,
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const LatLng _klCenter = LatLng(3.1390, 101.6869);
  static const double _defaultZoom = 11.6;

  final MapController _mapController = MapController();
  final TransitNetworkService _transitNetworkService = TransitNetworkService();
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  final ActiveTripService _activeTripService = ActiveTripService.instance;

  bool _isLoading = true;
  String? _errorText;
  Map<String, TransitStop> _stopsById = const <String, TransitStop>{};
  List<TransitConnection> _connections = const <TransitConnection>[];
  Position? _userPosition;
  String? _selectedStopId;
  StopCrowdForecast? _selectedForecast;
  _MapMode _mapMode = _MapMode.geographic;

  TransitGraph? _graph;
  TransitPath? _activeRoute;
  bool _debugCoordsMode = false;

  @override
  void initState() {
    super.initState();
    RouteSelectionService.instance.originStationId.addListener(_onRouteSelectionChanged);
    RouteSelectionService.instance.destinationStationId.addListener(_onRouteSelectionChanged);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    RouteSelectionService.instance.originStationId.removeListener(_onRouteSelectionChanged);
    RouteSelectionService.instance.destinationStationId.removeListener(_onRouteSelectionChanged);
    super.dispose();
  }

  void _onRouteSelectionChanged() {
    final originId = RouteSelectionService.instance.originStationId.value;
    final destId = RouteSelectionService.instance.destinationStationId.value;
    if (originId == null || destId == null || _graph == null) {
      setState(() => _activeRoute = null);
      return;
    }
    final path = _graph!.findShortestPath(originId, destId);
    setState(() => _activeRoute = path);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final network = await _transitNetworkService.loadNetwork();
      final position = await _loadLocation();
      final graph = await TransitDataService.instance.load();
      if (!mounted) return;
      setState(() {
        _stopsById = network.stopsById;
        _connections = network.connections;
        _userPosition = position;
        _graph = graph;
        _isLoading = false;
      });
      _focusInitialContext();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = 'Failed to load map data: $e';
        _isLoading = false;
      });
    }
  }

  Future<Position?> _loadLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  void _focusInitialContext() {
    final selected = _findStopByName(
      widget.initialDestinationName?.trim() ??
          _activeTripService.activeTrip.value?.destinationName,
    );

    if (selected != null) {
      unawaited(_selectStop(selected, moveCamera: true));
      return;
    }

    final position = _userPosition;
    if (position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(
          LatLng(position.latitude, position.longitude),
          12.8,
        );
      });
    }
  }

  TransitStop? _findStopByName(String? rawQuery) {
    final query = rawQuery?.trim().toLowerCase() ?? '';
    if (query.isEmpty) return null;
    for (final stop in _stopsById.values) {
      final name = stop.stopName.toLowerCase();
      if (name == query || name.contains(query)) {
        return stop;
      }
    }
    return null;
  }

  Future<void> _selectStop(
    TransitStop stop, {
    bool moveCamera = false,
  }) async {
    setState(() {
      _selectedStopId = stop.stopId;
      _selectedForecast = null;
    });

    if (moveCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(
          LatLng(stop.latitude, stop.longitude),
          14.2,
        );
      });
    }

    final forecast = await _crowdReportsService.fetchForecastForStopsAtTime(
      <String>[stop.stopId],
      DateTime.now(),
    );
    if (!mounted || _selectedStopId != stop.stopId) return;
    setState(() {
      _selectedForecast = forecast[stop.stopId];
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedStopId = null;
      _selectedForecast = null;
    });
  }

  List<Polyline> _buildNetworkPolylines() {
    final seen = <String>{};
    final polylines = <Polyline>[];

    for (final edge in _connections) {
      if (edge.connectionType != 'standard_stop') continue;
      final from = _stopsById[edge.fromStopId];
      final to = _stopsById[edge.toStopId];
      if (from == null || to == null) continue;

      final keyParts = <String>[from.stopId, to.stopId]..sort();
      final key = '${keyParts.first}|${keyParts.last}|${edge.routeId}';
      if (!seen.add(key)) continue;

      polylines.add(
        Polyline(
          points: <LatLng>[
            LatLng(from.latitude, from.longitude),
            LatLng(to.latitude, to.longitude),
          ],
          strokeWidth: 4,
          color: getRouteColor(edge.routeId).withValues(alpha: 0.82),
        ),
      );
    }

    return polylines;
  }

  List<Marker> _buildStopMarkers() {
    final stationCountByName = <String, int>{};
    for (final stop in _stopsById.values) {
      stationCountByName.update(
        stop.stopName.toUpperCase(),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    return _stopsById.values.map((stop) {
      final isSelected = stop.stopId == _selectedStopId;
      final isInterchange =
          (stationCountByName[stop.stopName.toUpperCase()] ?? 0) > 1;
      final size = isSelected
          ? 26.0
          : isInterchange
              ? 18.0
              : 14.0;

      return Marker(
        point: LatLng(stop.latitude, stop.longitude),
        width: size + 10,
        height: size + 10,
        child: GestureDetector(
          onTap: () => unawaited(_selectStop(stop)),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : getRouteColor(stop.routeId),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      isSelected ? getRouteColor(stop.routeId) : Colors.white,
                  width: isSelected ? 3 : 2,
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x26101828),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Polyline> _buildActiveTripPolylines() {
    final trip = _activeTripService.activeTrip.value;
    if (trip == null || trip.stops.length < 2) return const <Polyline>[];

    final points = <LatLng>[];
    for (final stop in trip.stops) {
      final resolved = _stopsById[stop.stopId.trim().toUpperCase()];
      if (resolved == null) continue;
      points.add(LatLng(resolved.latitude, resolved.longitude));
    }

    if (points.length < 2) return const <Polyline>[];
    return <Polyline>[
      Polyline(
        points: points,
        strokeWidth: 8,
        color: const Color(0x80111827),
      ),
      Polyline(
        points: points,
        strokeWidth: 5,
        color: const Color(0xFF0A3A8B),
      ),
    ];
  }

  Marker? _buildUserMarker() {
    final position = _userPosition;
    if (position == null) return null;
    return Marker(
      point: LatLng(position.latitude, position.longitude),
      width: 34,
      height: 34,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF0F6FFF),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x26101828),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.my_location_rounded,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }

  void _centerOnUser() {
    final position = _userPosition;
    if (position == null) return;
    _mapController.move(LatLng(position.latitude, position.longitude), 12.8);
  }

  @override
  Widget build(BuildContext context) {
    final selectedStop =
        _selectedStopId == null ? null : _stopsById[_selectedStopId!];
    final crowdStyle = crowdLevelStyleFromIndex(
      _selectedForecast?.occupancyLevel ?? 0,
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.map_rounded,
          leadingText: 'Rail',
          accentText: 'Map',
          badgeText: 'LIVE',
          subtitle: 'Geographic and schematic views',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: _buildModeSwitch(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorText != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorText!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                  : _mapMode == _MapMode.schematic
                  ? ValueListenableBuilder<String?>(
                      valueListenable: RouteSelectionService.instance.originStationId,
                      builder: (context, originId, _) {
                        return ValueListenableBuilder<String?>(
                          valueListenable: RouteSelectionService.instance.destinationStationId,
                          builder: (context, destId, _) {
                            if (_graph == null) return const Center(child: CircularProgressIndicator());
                            return Stack(
                              children: [
                                SchematicTransitMap(
                                  graph: _graph!,
                                  selectedOriginId: originId,
                                  selectedDestinationId: destId,
                                  activeRoute: _activeRoute,
                                  onOriginSelected: (_) {},
                                  onDestinationSelected: (_) {},
                                  debugMode: _debugCoordsMode,
                                ),
                                Positioned(
                                  top: 4,
                                  left: 4,
                                  child: Material(
                                    elevation: 2,
                                    borderRadius: BorderRadius.circular(8),
                                    child: IconButton(
                                      icon: Icon(
                                        _debugCoordsMode
                                            ? Icons.touch_app
                                            : Icons.touch_app_outlined,
                                        size: 20,
                                      ),
                                      tooltip: _debugCoordsMode
                                          ? 'Coord calibration ON'
                                          : 'Toggle coord calibration (tap map to get x,y)',
                                      onPressed: () {
                                        setState(() =>
                                            _debugCoordsMode = !_debugCoordsMode);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    )
                  : Stack(
                      children: [
                        Positioned.fill(
                          child: FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: _klCenter,
                              initialZoom: _defaultZoom,
                              minZoom: 9,
                              maxZoom: 18,
                              onTap: (_, __) => _clearSelection(),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName:
                                    'smart_commuter_assistant',
                              ),
                              PolylineLayer(
                                  polylines: _buildNetworkPolylines()),
                              ValueListenableBuilder<ActiveTrip?>(
                                valueListenable: _activeTripService.activeTrip,
                                builder: (context, _, __) {
                                  return PolylineLayer(
                                    polylines: _buildActiveTripPolylines(),
                                  );
                                },
                              ),
                              MarkerLayer(
                                markers: <Marker>[
                                  ..._buildStopMarkers(),
                                  if (_buildUserMarker() case final marker?)
                                    marker,
                                ],
                              ),
                            ],
                          ),
                        ),
                        if ((widget.preferredRouteType?.trim().isNotEmpty ??
                            false))
                          Positioned(
                            top: 12,
                            left: 16,
                            right: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Route preference: ${widget.preferredRouteType}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Column(
                            children: [
                              FloatingActionButton.small(
                                heroTag: 'locate_me',
                                onPressed: _centerOnUser,
                                child: const Icon(Icons.my_location_rounded),
                              ),
                              const SizedBox(height: 10),
                              FloatingActionButton.small(
                                heroTag: 'reset_map',
                                onPressed: () => _mapController.move(
                                    _klCenter, _defaultZoom),
                                child: const Icon(
                                    Icons.center_focus_strong_rounded),
                              ),
                            ],
                          ),
                        ),
                        if (selectedStop != null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: 16,
                            child: Material(
                              color: Colors.transparent,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: const <BoxShadow>[
                                    BoxShadow(
                                      color: Color(0x26101828),
                                      blurRadius: 18,
                                      offset: Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: getRouteColor(
                                                selectedStop.routeId),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            selectedStop.stopName,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: _clearSelection,
                                          icon:
                                              const Icon(Icons.close_rounded),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${selectedStop.stopId} • ${selectedStop.routeId}',
                                      style: const TextStyle(
                                        color: Color(0xFF667085),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: crowdStyle.color
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _selectedForecast == null
                                            ? 'No backend forecast available'
                                            : 'Crowd: ${crowdStyle.label}',
                                        style: TextStyle(
                                          color: crowdStyle.color,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ScheduledArrivalsPanel(
                                      stopId: selectedStop.stopId,
                                      stationName: selectedStop.stopName,
                                      compact: true,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _buildModeSwitch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<_MapMode>(
          segments: const [
            ButtonSegment<_MapMode>(
              value: _MapMode.geographic,
              icon: Icon(Icons.public_rounded),
              label: Text('Geographic'),
            ),
            ButtonSegment<_MapMode>(
              value: _MapMode.schematic,
              icon: Icon(Icons.schema_rounded),
              label: Text('Transit map'),
            ),
          ],
          selected: {_mapMode},
          onSelectionChanged: (selection) {
            setState(() => _mapMode = selection.first);
          },
        ),
      ),
    );
  }
}

enum _MapMode {
  geographic,
  schematic,
}
