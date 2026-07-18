import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../models/map_station.dart';
import '../services/active_trip_service.dart';
import '../services/crowd_reports_service.dart';
import '../services/transit_network_service.dart';
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

  List<MapStation> _mapStations = [];
  String? _schematicOriginId;
  String? _schematicDestId;
  bool _debugCoordsMode = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final network = await _transitNetworkService.loadNetwork();
      final position = await _loadLocation();
      final stations = await MapStationData.load();
      if (!mounted) return;
      setState(() {
        _stopsById = network.stopsById;
        _connections = network.connections;
        _userPosition = position;
        _mapStations = stations;
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

  void _showSchematicRouteSheet() {
    final originId = _schematicOriginId;
    final destId = _schematicDestId;
    if (originId == null || destId == null) return;

    final originStation = _mapStations.firstWhere(
      (s) => s.stationId == originId,
      orElse: () => _mapStations.first,
    );
    final destStation = _mapStations.firstWhere(
      (s) => s.stationId == destId,
      orElse: () => _mapStations.first,
    );

    final result = _findSchematicRoute(originId, destId);
    if (result == null && !mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SchematicRouteSheet(
        originName: originStation.name,
        originId: originId,
        destinationName: destStation.name,
        destinationId: destId,
        path: result?.edges ?? <TransitConnection>[],
        totalMinutes: result?.totalMinutes ?? 0,
        stopsById: _stopsById,
      ),
    );
  }

  ({List<TransitConnection> edges, int totalMinutes})? _findSchematicRoute(
    String originId,
    String destId,
  ) {
    final stops = _stopsById;
    final targets = <String>{destId};
    if (!stops.containsKey(destId)) {
      targets.addAll(
        stops.values
            .where((s) => s.stopName.toUpperCase() ==
                stops[destId]?.stopName.toUpperCase())
            .map((s) => s.stopId),
      );
    }
    if (targets.isEmpty ||
        (!stops.containsKey(originId) && !stops.values.any(
              (s) => s.stopId == originId,
            ))) {
      return null;
    }

    final adjacency = <String, List<_RouteEdgeRef>>{};
    for (final c in _connections) {
      adjacency.putIfAbsent(c.fromStopId, () => []).add(
        _RouteEdgeRef(toStopId: c.toStopId, minutes: c.travelMinutes, routeId: c.routeId),
      );
    }

    final dist = <String, int>{originId: 0};
    final prev = <String, String>{};
    final prevEdge = <String, _RouteEdgeRef>{};
    final unvisited = <String>{originId};

    while (unvisited.isNotEmpty) {
      final current = unvisited.reduce((a, b) =>
          (dist[a] ?? 999999) < (dist[b] ?? 999999) ? a : b);
      unvisited.remove(current);

      if (targets.contains(current)) break;

      final currentDist = dist[current] ?? 999999;
      for (final edge in adjacency[current] ?? <_RouteEdgeRef>[]) {
        final alt = currentDist + edge.minutes;
        if (alt < (dist[edge.toStopId] ?? 999999)) {
          dist[edge.toStopId] = alt;
          prev[edge.toStopId] = current;
          prevEdge[edge.toStopId] = edge;
          unvisited.add(edge.toStopId);
        }
      }
    }

    String? bestDest;
    var bestDist = 999999;
    for (final t in targets) {
      if ((dist[t] ?? 999999) < bestDist) {
        bestDist = dist[t]!;
        bestDest = t;
      }
    }
    if (bestDest == null) return null;

    final pathEdges = <TransitConnection>[];
    var cursor = bestDest;
    while (cursor != originId) {
      final e = prevEdge[cursor];
      final p = prev[cursor];
      if (e == null || p == null) break;
      pathEdges.insert(0,
        _connections.firstWhere(
          (c) => c.fromStopId == p && c.toStopId == cursor,
          orElse: () => TransitConnection(
            fromStopId: p,
            toStopId: cursor,
            routeId: e.routeId,
            connectionType: 'standard_stop',
            travelMinutes: e.minutes,
          ),
        ),
      );
      cursor = p;
    }

    return (edges: pathEdges, totalMinutes: bestDist);
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
                  ? Stack(
                      children: [
                        SchematicTransitMap(
                          stations: _mapStations,
                          selectedOriginId: _schematicOriginId,
                          selectedDestinationId: _schematicDestId,
                          onOriginSelected: (station) {
                            setState(() {
                              _schematicOriginId = station.stationId;
                            });
                          },
                          onDestinationSelected: (station) {
                            setState(() {
                              _schematicDestId = station.stationId;
                            });
                          },
                          onPlanRoute: _showSchematicRouteSheet,
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

class _RouteEdgeRef {
  final String toStopId;
  final int minutes;
  final String routeId;
  const _RouteEdgeRef({required this.toStopId, required this.minutes, required this.routeId});
}

class _SchematicRouteSheet extends StatelessWidget {
  final String originName;
  final String originId;
  final String destinationName;
  final String destinationId;
  final List<TransitConnection> path;
  final int totalMinutes;
  final Map<String, TransitStop> stopsById;

  const _SchematicRouteSheet({
    required this.originName,
    required this.originId,
    required this.destinationName,
    required this.destinationId,
    required this.path,
    required this.totalMinutes,
    required this.stopsById,
  });

  @override
  Widget build(BuildContext context) {
    final segments = <_RouteSegmentUi>[];
    String? currentLine;
    String? segmentStart;
    var segmentMinutes = 0;
    var segmentStops = 0;

    for (final edge in path) {
      if (edge.connectionType == 'transfer' || edge.connectionType == 'interchange_transfer') {
        if (currentLine != null && segmentStart != null) {
          segments.add(_RouteSegmentUi(
            line: currentLine,
            fromName: stopsById[segmentStart]?.stopName ?? segmentStart,
            toName: stopsById[edge.fromStopId]?.stopName ?? edge.fromStopId,
            stops: segmentStops,
            minutes: segmentMinutes,
          ));
        }
        segments.add(_RouteSegmentUi(
          line: 'Transfer',
          fromName: stopsById[edge.fromStopId]?.stopName ?? edge.fromStopId,
          toName: stopsById[edge.toStopId]?.stopName ?? edge.toStopId,
          stops: 0,
          minutes: edge.travelMinutes,
        ));
        currentLine = null;
        segmentStart = null;
        segmentMinutes = 0;
        segmentStops = 0;
      } else {
        if (currentLine == null) {
          currentLine = edge.routeId;
          segmentStart = edge.fromStopId;
          segmentMinutes = 0;
          segmentStops = 0;
        }
        segmentMinutes += edge.travelMinutes;
        segmentStops++;
      }
    }
    if (currentLine != null && segmentStart != null) {
      final lastEdge = path.isNotEmpty ? path.last : null;
      segments.add(_RouteSegmentUi(
        line: currentLine,
        fromName: stopsById[segmentStart]?.stopName ?? segmentStart,
        toName: lastEdge != null ? (stopsById[lastEdge.toStopId]?.stopName ?? lastEdge.toStopId) : destinationName,
        stops: segmentStops,
        minutes: segmentMinutes,
      ));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$originName → $destinationName',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              '$totalMinutes min • ${path.length} stops',
              style: const TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w600),
            ),
            if (path.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text('No route found between these stations on the schematic map.',
                    style: TextStyle(color: Color(0xFF667085))),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: segments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final seg = segments[index];
                    final color = seg.line == 'Transfer'
                        ? const Color(0xFF667085)
                        : getRouteColor(seg.line);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3EAF7)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  seg.line == 'Transfer'
                                      ? 'Transfer at ${seg.toName}'
                                      : '${seg.line}: ${seg.fromName} → ${seg.toName}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                ),
                                Text(
                                  '${seg.minutes} min • ${seg.stops} stops',
                                  style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded, size: 14,
                              color: color.withValues(alpha: 0.6)),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteSegmentUi {
  final String line;
  final String fromName;
  final String toName;
  final int stops;
  final int minutes;
  const _RouteSegmentUi({
    required this.line,
    required this.fromName,
    required this.toName,
    required this.stops,
    required this.minutes,
  });
}

enum _MapMode {
  geographic,
  schematic,
}
