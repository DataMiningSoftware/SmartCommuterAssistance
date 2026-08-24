import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/map_station.dart';
import '../models/schematic_layout.dart';
import '../models/transit_graph.dart';
import '../services/station_name_matcher.dart';
import '../services/active_trip_service.dart';
import '../services/backend_config_service.dart';
import '../services/commuter_ml_service.dart';
import '../services/map_selection_controller.dart';
import '../services/transit_data_service.dart';
import '../services/transit_network_service.dart';
import '../services/transit_planner_service.dart';
import '../widgets/app_page_title.dart';
import '../widgets/interactive_schematic_map.dart';
import '../widgets/map_cards.dart';

enum _MapMode { geographic, schematic }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  _MapMode _mode = _MapMode.schematic;

  SchematicLayout? _layout;
  TransitGraph? _graph;
  Map<String, LatLng> _stationCoords = {};
  final Map<String, String> _stationIdToGraphId = {};
  List<MapStation> _allStations = [];

  MapSelectionController? _controller;

  String? _errorText;
  bool _isLoading = true;

  static const Set<String> _hiddenLineIds = {
    '1', '2',   // KTM Batu Caves and Tanjung Malim lines
    '6', '7',   // KLIA Ekspres and KLIA Transit
    '10',       // KTM Skypark
    '11',       // Johan Setia (Coming Soon)
  };

  static const LatLng _klCenter = LatLng(3.1390, 101.6869);
  static const double _labelZoomThreshold = 14.0;
  final MapController _mapController = MapController();
  double _geoZoom = 12.0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _errorText = null;
      _isLoading = true;
    });

    try {
      final network = await TransitNetworkService().loadNetwork();
      final graph = await TransitDataService.instance.load();
      final layout = await SchematicLayout.load();

      final matcher = StationNameMatcher.instance;
      final nameToCoord = <String, LatLng>{};

      for (final gs in graph.stations.values) {
        if (gs.lat != 0 || gs.lng != 0) {
          nameToCoord[matcher.normalize(gs.name)] = LatLng(gs.lat, gs.lng);
        }
      }

      for (final stop in network.stopsById.values) {
        final key = matcher.normalize(stop.stopName);
        nameToCoord.putIfAbsent(key, () => LatLng(stop.latitude, stop.longitude));
      }

      final nameToGraphId = <String, String>{};
      for (final gs in graph.stations.values) {
        nameToGraphId.putIfAbsent(matcher.normalize(gs.name), () => gs.id);
      }

      final allStations = <MapStation>[];

      for (final entry in layout.stations.entries) {
        final sid = entry.key;
        final s = entry.value;
        final normalizedSchematic = matcher.normalize(s.name);
        final coordEntry = nameToCoord.entries.firstWhere(
          (e) => matcher.match(e.key, normalizedSchematic),
          orElse: () => const MapEntry('', LatLng(0, 0)),
        );
        final graphIdEntry = nameToGraphId.entries.firstWhere(
          (e) => matcher.match(e.key, normalizedSchematic),
          orElse: () => const MapEntry('', ''),
        );
        if (graphIdEntry.value.isNotEmpty) {
          _stationIdToGraphId[sid] = graphIdEntry.value;
        }
        final coord = coordEntry.value;
        final hasValidCoord = coord.latitude != 0 || coord.longitude != 0;
        final ms = MapStation(
          stationId: sid,
          name: s.name,
          x: s.x,
          y: s.y,
          lines: s.lines,
          latitude: hasValidCoord ? coord.latitude : null,
          longitude: hasValidCoord ? coord.longitude : null,
        );
        allStations.add(ms);
      }

      _allStations = allStations;
      final unmatchedCoords = <String>[];
      _stationCoords = <String, LatLng>{};
      for (final ms in allStations) {
        if (ms.latitude != null && ms.longitude != null) {
          _stationCoords[ms.stationId] = LatLng(ms.latitude!, ms.longitude!);
        } else {
          unmatchedCoords.add('${ms.stationId} (${ms.name})');
        }
      }

      if (unmatchedCoords.isNotEmpty) {
        debugPrint(
          'map_screen: ${unmatchedCoords.length} schematic station(s) '
          'have no geo coordinate: $unmatchedCoords',
        );
      }

      layout.reorderUsingGraph(graph);

      final baseUrl = BackendConfigService().baseUrl.value;
      final planner = TransitPlannerService(
        gateway: ResilientTransitPlanningGateway(
          primary: ApiTransitPlanningGateway(graph: graph, baseUrl: baseUrl),
          fallback: LocalTransitPlanningGateway(graph: graph),
        ),
        mlService: CommuterMlService(),
      );

      _controller = MapSelectionController(
        plannerService: planner,
        activeTripService: ActiveTripService.instance,
        resolveStationId: (station) =>
            _stationIdToGraphId[station.stationId] ?? station.stationId,
      );
      _controller!.addListener(_onControllerChanged);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _layout = layout;
        _graph = graph;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'Failed to load map data: $e';
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _onStationTapped(MapStation station) {
    _controller?.selectStation(station);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.map_rounded,
          leadingText: 'Rail',
          accentText: 'Map',
          subtitle: 'Geographic and schematic views',
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: _buildModeSwitch(),
        ),
      ),
      body: _errorText != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_errorText!, textAlign: TextAlign.center),
                  ),
                )
              : _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _mode == _MapMode.schematic
                      ? _buildSchematicView()
                      : _buildGeographicView(),
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
          selected: {_mode},
          onSelectionChanged: (selection) => setState(() => _mode = selection.first),
        ),
      ),
    );
  }

  Widget _buildSchematicView() {
    if (_graph == null || _layout == null || _controller == null) {
      return const SizedBox.shrink();
    }
    return Stack(
      children: [
        InteractiveSchematicMap(
          layout: _layout!,
          graph: _graph!,
          controller: _controller!,
          onStationTap: _onStationTapped,
          hiddenLineIds: _hiddenLineIds,
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: StationOrRouteCard(controller: _controller!),
        ),
      ],
    );
  }

  Widget _buildGeographicView() {
    if (_controller == null) return const SizedBox.shrink();
    final routeStationIds = _routeStationIds();
    final hasRoute = routeStationIds.isNotEmpty;

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _klCenter,
              initialZoom: 11.6,
              minZoom: 9,
              maxZoom: 18,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) setState(() => _geoZoom = pos.zoom);
              },
              onTap: (_, point) {
                final nearest = _nearestStation(point);
                if (nearest != null) _controller!.selectStation(nearest);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}@2x.png',
                userAgentPackageName: 'com.nawfal.smartcommuter',
              ),
              PolylineLayer(polylines: _buildLinePolylines(routeStationIds, hasRoute)),
              MarkerLayer(markers: _buildStationMarkers(routeStationIds, hasRoute)),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: StationOrRouteCard(controller: _controller!),
        ),
      ],
    );
  }

  Map<String, String>? _nameToSchematicId;

  Map<String, String> _getNameToSchematicId() {
    if (_nameToSchematicId == null && _layout != null) {
      _nameToSchematicId = {};
      final matcher = StationNameMatcher.instance;
      for (final entry in _layout!.stations.entries) {
        _nameToSchematicId![matcher.normalize(entry.value.name)] = entry.key;
      }
    }
    return _nameToSchematicId ?? const {};
  }

  Set<String> _routeStationIds() {
    final route = _controller?.confirmedRoute ?? _controller?.candidateRoute;
    if (route == null) return {};
    final nameMap = _getNameToSchematicId();
    if (nameMap.isEmpty) return {};
    final matcher = StationNameMatcher.instance;
    return route.steps
        .map((s) => nameMap[matcher.normalize(s.station)])
        .where((id) => id != null && id.isNotEmpty)
        .map((id) => id!)
        .toSet();
  }

  List<Polyline> _buildLinePolylines(Set<String> routeIds, bool hasRoute) {
    final polylines = <Polyline>[];
    if (_layout == null) return polylines;

    for (final line in _layout!.lines.values) {
      if (_hiddenLineIds.contains(line.id)) continue;
      final points = line.stationIds
          .map((id) => _stationCoords[id])
          .whereType<LatLng>()
          .toList();
      if (points.length < 2) continue;

      final idsOnRoute = line.stationIds.where(routeIds.contains).toSet();
      final isOnRoute = !hasRoute || idsOnRoute.length >= 2;

      polylines.add(Polyline(
        points: points,
        strokeWidth: isOnRoute && hasRoute ? 5.0 : 3.0,
        color: line.color.withValues(alpha: isOnRoute ? (hasRoute ? 1.0 : 0.7) : 0.15),
      ));
    }
    return polylines;
  }

  List<Marker> _buildStationMarkers(Set<String> routeIds, bool hasRoute) {
    final showLabels = _geoZoom >= _labelZoomThreshold;
    final markers = <Marker>[];

    for (final station in _allStations) {
      if (_isStationHidden(station)) continue;
      final coord = _stationCoords[station.stationId];
      if (coord == null) continue;

      final isSelected = station.stationId == _controller?.from?.stationId ||
          station.stationId == _controller?.to?.stationId ||
          routeIds.contains(station.stationId);

      markers.add(Marker(
        point: coord,
        width: showLabels ? 150 : 30,
        height: 30,
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: () => _controller?.selectStation(station),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: isSelected ? 14 : 8,
                height: isSelected ? 14 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.amber : Colors.white,
                  border: Border.all(color: Colors.black87, width: 1.2),
                ),
              ),
              if (showLabels) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    StationNameMatcher.instance.displayName(station.name),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: Colors.black87,
                      shadows: const [
                        Shadow(color: Colors.white, blurRadius: 2),
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ));
    }
    return markers;
  }

  bool _isStationHidden(MapStation station) =>
      station.lines.every((l) => _hiddenLineIds.contains(l));

  MapStation? _nearestStation(LatLng tapped) {
    const Distance dist = Distance();
    MapStation? closest;
    double closestMeters = double.infinity;

    for (final station in _allStations) {
      if (_isStationHidden(station)) continue;
      final coord = _stationCoords[station.stationId];
      if (coord == null) continue;
      final meters = dist(tapped, coord);
      if (meters < closestMeters) {
        closestMeters = meters;
        closest = station;
      }
    }
    return closestMeters <= 150 ? closest : null;
  }
}
