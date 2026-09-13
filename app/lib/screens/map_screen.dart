import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../constants/route_colors.dart';
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

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  _MapMode _mode = _MapMode.schematic;

  SchematicLayout? _layout;
  TransitGraph? _graph;
  Map<String, LatLng> _stationCoords = {};
  final Map<String, String> _stationIdToGraphId = {};
  final Map<String, String> _graphIdToStationId = {};
  final Map<String, MapStation> _stationById = {};
  final Map<String, String> _nameToStationId = {};
  List<MapStation> _allStations = [];

  MapSelectionController? _controller;

  String? _errorText;
  bool _isLoading = true;

  static const Set<String> _hiddenLineIds = {
    '11', // Johan Setia (Coming Soon)
  };

  static const LatLng _klCenter = LatLng(3.1390, 101.6869);
  static const double _labelZoomThreshold = 14.0;
  final MapController _mapController = MapController();
  double _geoZoom = 11.6;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
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
      _stationById.clear();
      _nameToStationId.clear();
      for (final ms in allStations) {
        _stationById[ms.stationId] = ms;
        _nameToStationId.putIfAbsent(
          StationNameMatcher.instance.normalize(ms.name),
          () => ms.stationId,
        );
      }
      _graphIdToStationId.clear();
      for (final entry in _stationIdToGraphId.entries) {
        _graphIdToStationId[entry.value] = entry.key;
      }

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
      ActiveTripService.instance.activeTrip.addListener(_onActiveTripChanged);
      _hydrateFromActiveTrip();

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
    ActiveTripService.instance.activeTrip.removeListener(_onActiveTripChanged);
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    _mapController.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  void _onActiveTripChanged() {
    if (!mounted) return;
    _hydrateFromActiveTrip();
  }

  String? _schematicIdFor(String stopId, String name) {
    final byId = _graphIdToStationId[stopId];
    if (byId != null && _stationById.containsKey(byId)) return byId;
    if (_stationById.containsKey(stopId)) return stopId;
    return _nameToStationId[StationNameMatcher.instance.normalize(name)];
  }

  void _hydrateFromActiveTrip() {
    final controller = _controller;
    if (controller == null) return;
    final trip = ActiveTripService.instance.activeTrip.value;
    if (trip == null || trip.stops.isEmpty) {
      controller.clearActiveTrip();
      return;
    }

    final fromId = _schematicIdFor(trip.originStopId, trip.originName);
    final toId = _schematicIdFor(trip.destinationStopId, trip.destinationName);
    if (fromId == null || toId == null) {
      controller.clearActiveTrip();
      return;
    }

    final segments = <RouteSegment>[];
    var prevId = fromId;
    for (final stop in trip.stops) {
      final sid = _schematicIdFor(stop.stopId, stop.stopName);
      if (sid == null || sid == prevId) continue;
      segments.add(RouteSegment(
        fromStationId: prevId,
        toStationId: sid,
        line: normalizeRouteId(stop.routeId),
      ));
      prevId = sid;
    }

    if (segments.isEmpty) {
      controller.clearActiveTrip();
      return;
    }

    controller.showActiveTrip(
      from: _stationById[fromId]!,
      to: _stationById[toId]!,
      segments: segments,
    );
  }

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
    final segments = _routeSegments();
    final hasRoute = _controller!.isRouteActive;
    final routeStationIds = <String>{
      for (final s in segments) ...[s.fromStationId, s.toStationId],
    };

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
              PolylineLayer(
                  polylines: _buildLinePolylines(segments, hasRoute)),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => MarkerLayer(
                  markers: _buildStationMarkers(
                      routeStationIds, hasRoute, _pulse.value),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapZoomButton(icon: Icons.add_rounded, onTap: _zoomIn),
              const SizedBox(height: 8),
              _MapZoomButton(icon: Icons.remove_rounded, onTap: _zoomOut),
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

  List<RouteSegment> _routeSegments() =>
      _controller?.routeSegments ?? const <RouteSegment>[];

  void _zoomIn() {
    final target = (_geoZoom + 1).clamp(9.0, 18.0);
    _mapController.move(_mapController.camera.center, target);
    setState(() => _geoZoom = target);
  }

  void _zoomOut() {
    final target = (_geoZoom - 1).clamp(9.0, 18.0);
    _mapController.move(_mapController.camera.center, target);
    setState(() => _geoZoom = target);
  }

  List<Polyline> _buildLinePolylines(
      List<RouteSegment> segments, bool hasRoute) {
    final polylines = <Polyline>[];
    if (_layout == null) return polylines;

    for (final line in _layout!.lines.values) {
      if (_hiddenLineIds.contains(line.id)) continue;
      final points = line.stationIds
          .map((id) => _stationCoords[id])
          .whereType<LatLng>()
          .toList();
      if (points.length < 2) continue;

      polylines.add(Polyline(
        points: points,
        strokeWidth: hasRoute ? 2.5 : 3.0,
        color: hasRoute
            ? kMapDisabledGrey.withValues(alpha: 0.3)
            : line.color.withValues(alpha: 0.85),
      ));
    }

    if (hasRoute) {
      for (final segment in segments) {
        if (segment.isTransfer) continue;
        final a = _stationCoords[segment.fromStationId];
        final b = _stationCoords[segment.toStationId];
        if (a == null || b == null) continue;
        polylines.add(Polyline(
          points: [a, b],
          strokeWidth: 5.0,
          color: getRouteColor(segment.line),
        ));
      }
    }
    return polylines;
  }

  List<Marker> _buildStationMarkers(
      Set<String> routeStationIds, bool hasRoute, double blink) {
    final showLabels = _geoZoom >= _labelZoomThreshold;
    final markers = <Marker>[];

    for (final station in _allStations) {
      if (_isStationHidden(station)) continue;
      final coord = _stationCoords[station.stationId];
      if (coord == null) continue;

      final isCurrent = station.stationId == _controller?.from?.stationId;
      final isDestination = station.stationId == _controller?.to?.stationId;
      final onRoute = routeStationIds.contains(station.stationId);

      final Color dotColor;
      if (hasRoute && !onRoute) {
        dotColor = kMapDisabledGrey;
      } else if (isCurrent) {
        dotColor = Color.lerp(Colors.amber, Colors.deepOrangeAccent, blink)!;
      } else if (isDestination) {
        dotColor = Colors.amber;
      } else {
        dotColor = Colors.white;
      }

      final double dotSize =
          isCurrent ? 14 + 4 * blink : (isDestination || onRoute ? 12 : 8);

      final dot = Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dotColor,
          border: Border.all(color: Colors.black87, width: 1.2),
        ),
      );

      markers.add(Marker(
        point: coord,
        width: showLabels ? 150 : 44,
        height: 44,
        alignment: Alignment.center,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controller?.selectStation(station),
          child: showLabels
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(child: dot),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        StationNameMatcher.instance.displayName(station.name),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isCurrent || isDestination
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: hasRoute && !onRoute
                              ? kMapDisabledGrey
                              : Colors.black87,
                          shadows: const [
                            Shadow(color: Colors.white, blurRadius: 2),
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              : Center(child: dot),
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

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: scheme.onSurface),
        ),
      ),
    );
  }
}
