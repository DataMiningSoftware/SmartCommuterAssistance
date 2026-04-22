import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/route_colors.dart';
import '../services/active_trip_service.dart';
import '../services/database_service.dart';
import '../widgets/app_page_title.dart';
import '../widgets/train_loading_transition.dart';

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

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  static const double _mapAspectRatio = 1805 / 2560;
  static const double _mapMarginX = 0.06;
  static const double _mapMarginY = 0.05;
  static const Duration _blinkDuration = Duration(milliseconds: 1800);
  static const Map<String, Offset> _anchorMapByStopId = <String, Offset>{
    'KJ1': Offset(0.73, 0.17), // GOMBAK
    'KJ2': Offset(0.72, 0.20), // TAMAN MELATI
    'KJ3': Offset(0.71, 0.23), // WANGSA MAJU
    'KJ4': Offset(0.70, 0.26), // SRI RAMPAI
    'KJ5': Offset(0.69, 0.29), // SETIAWANGSA
    'KJ6': Offset(0.68, 0.32), // JELATEK
    'KJ7': Offset(0.67, 0.35), // DATO' KERAMAT
    'KJ8': Offset(0.66, 0.38), // DAMAI
    'KJ9': Offset(0.65, 0.41), // AMPANG PARK
    'KJ10': Offset(0.64, 0.44), // KLCC
    'KJ11': Offset(0.62, 0.46), // KAMPUNG BARU
    'KJ12': Offset(0.60, 0.48), // DANG WANGI
    'KJ13': Offset(0.58, 0.51), // MASJID JAMEK
    'KJ14': Offset(0.56, 0.54), // PASAR SENI
    'KJ15': Offset(0.54, 0.58), // KL SENTRAL
    'AG3': Offset(0.59, 0.32), // TITIWANGSA
    'AG7': Offset(0.58, 0.51), // MASJID JAMEK
    'AG11': Offset(0.66, 0.56), // CHAN SOW LIN
    'PY17': Offset(0.59, 0.32), // TITIWANGSA
    'PY18': Offset(0.56, 0.35), // HOSPITAL KUALA LUMPUR
    'PY19': Offset(0.60, 0.37), // RAJA UDA
    'PY20': Offset(0.64, 0.40), // AMPANG PARK
    'PY21': Offset(0.70, 0.42), // PERSIARAN KLCC
    'PY22': Offset(0.71, 0.46), // CONLAY
    'PY23': Offset(0.69, 0.49), // TUN RAZAK EXCHANGE
    'PY24': Offset(0.69, 0.56), // CHAN SOW LIN
    'KG16': Offset(0.56, 0.54), // PASAR SENI
    'KG17': Offset(0.57, 0.57), // MERDEKA
    'KG18A': Offset(0.62, 0.53), // BUKIT BINTANG
    'KG20': Offset(0.69, 0.49), // TUN RAZAK EXCHANGE
    'KG21': Offset(0.72, 0.50), // COCHRANE
    'KG22': Offset(0.74, 0.52), // MALURI
    'KG35': Offset(0.78, 0.69), // KAJANG
    'MR1': Offset(0.54, 0.58), // KL SENTRAL
    'MR4': Offset(0.61, 0.56), // HANG TUAH
    'MR6': Offset(0.64, 0.52), // BUKIT BINTANG
    'MR8': Offset(0.62, 0.46), // BUKIT NANAS
    'MR11': Offset(0.59, 0.32), // TITIWANGSA
    'PY38': Offset(0.67, 0.77), // 16 SIERRA
    'PY39': Offset(0.64, 0.80), // CYBERJAYA UTARA
    'PY40': Offset(0.63, 0.82), // CYBERJAYA CITY CENTRE
    'PY41': Offset(0.69, 0.84), // PUTRAJAYA SENTRAL
    'AG18': Offset(0.87, 0.20), // AMPANG
  };

  final SupabaseClient _client = Supabase.instance.client;
  final DatabaseService _databaseService = DatabaseService();

  late final AnimationController _blinkController;
  late final TransformationController _mapController;

  bool _isLoading = true;
  bool _isRouting = false;
  String? _errorText;

  Position? _userPosition;
  Map<String, _StopNode> _stopsById = <String, _StopNode>{};
  List<_RouteConnection> _connections = <_RouteConnection>[];
  List<_StationOption> _stationOptions = <_StationOption>[];
  _StationOption? _selectedDestination;
  _ResolvedRoute? _resolvedRoute;
  String? _focusedStopId;

  @override
  void initState() {
    super.initState();
    _mapController = TransformationController();
    _blinkController = AnimationController(
      vsync: this,
      duration: _blinkDuration,
    )..repeat(reverse: true);
    _bootstrap();
    if (widget.preferredRouteType != null) {
      // Show user selected preference briefly
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMessage('Route preference: ${widget.preferredRouteType}');
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      await _loadNetworkData();
      await _refreshLocation(silentOnError: true);
      final activeTrip = ActiveTripService.instance.activeTrip.value;
      final initialQuery = widget.initialDestinationName?.trim() ??
          activeTrip?.destinationName.trim() ??
          '';
      if (initialQuery.isNotEmpty) {
        _StationOption? match;
        for (final option in _stationOptions) {
          final name = option.stationName.toLowerCase();
          final query = initialQuery.toLowerCase();
          if (name == query || name.contains(query)) {
            match = option;
            break;
          }
        }
        if (match != null) {
          _selectedDestination = match;
          await _computeRoute();
        }
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = 'Failed to load map data: $e';
      });
    }
  }

  Future<void> _loadNetworkData() async {
    final stopMaps = <Map<String, dynamic>>[];
    try {
      final stopRows = await _client
          .from('train_stops_kl')
          .select('stop_id,stop_name,stop_lat,stop_lon,route_id');
      stopMaps.addAll(
        stopRows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
      );
      if (stopMaps.isNotEmpty) {
        await _databaseService.cacheTrainStops(stopMaps);
      }
    } catch (_) {
      // Fall through to local cache.
    }
    if (stopMaps.isEmpty) {
      final cachedStops = await _databaseService.getCachedTrainStops();
      if (cachedStops.isNotEmpty) {
        stopMaps.addAll(
          cachedStops.map((row) => Map<String, dynamic>.from(row)),
        );
      }
    }

    final rawStops = <_StopNode>[];
    for (final map in stopMaps) {
      final stopId = (map['stop_id']?.toString() ?? '').trim().toUpperCase();
      final stopName = (map['stop_name']?.toString() ?? '').trim();
      final routeId = (map['route_id']?.toString() ?? '').trim().toUpperCase();
      final lat = _toDouble(map['stop_lat']);
      final lon = _toDouble(map['stop_lon']);
      if (stopId.isEmpty || stopName.isEmpty || lat == null || lon == null) {
        continue;
      }
      rawStops.add(
        _StopNode(
          stopId: stopId,
          stopName: stopName,
          routeId: routeId,
          latitude: lat,
          longitude: lon,
          mapX: 0,
          mapY: 0,
        ),
      );
    }

    if (rawStops.isEmpty) {
      throw StateError(
          'No valid stops with coordinates found in train_stops_kl.');
    }

    final projectedStops = <String, _StopNode>{};
    final transform = _buildMapTransform(rawStops);
    final projectedOffsets = _projectStopOffsets(
      rawStops: rawStops,
      transform: transform,
    );
    for (final stop in rawStops) {
      final projected = projectedOffsets[stop.stopId] ??
          transform.project(stop.longitude, stop.latitude);
      projectedStops[stop.stopId] = stop.copyWith(
        mapX: projected.dx.clamp(0.0, 1.0),
        mapY: projected.dy.clamp(0.0, 1.0),
      );
    }

    final edgeMaps = <Map<String, dynamic>>[];
    try {
      final edgeRows = await _client.from('route_connections').select(
          'from_stop_id,to_stop_id,route_id,travel_time_minutes,connection_type');
      edgeMaps.addAll(
        edgeRows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)),
      );
      if (edgeMaps.isNotEmpty) {
        await _databaseService.cacheRouteConnections(edgeMaps);
      }
    } catch (_) {
      // Fall through to cached/inferred connections.
    }
    if (edgeMaps.isEmpty) {
      final cachedEdges = await _databaseService.getCachedRouteConnections();
      if (cachedEdges.isNotEmpty) {
        edgeMaps.addAll(
          cachedEdges.map((row) => Map<String, dynamic>.from(row)),
        );
      }
    }

    var edges = _mapEdgeRows(
      edgeRows: edgeMaps,
      projectedStops: projectedStops,
    );

    if (edges.isEmpty) {
      edges = _buildFallbackConnections(projectedStops.values.toList());
    }
    if (edges.isEmpty) {
      throw StateError(
        'No station connections available. Populate route_connections or open the stations page once to sync cache.',
      );
    }

    final groupedByStation = <String, List<_StopNode>>{};
    for (final stop in projectedStops.values) {
      final key = stop.stopName.toUpperCase();
      groupedByStation.putIfAbsent(key, () => <_StopNode>[]).add(stop);
    }
    final options = groupedByStation.values.map((stops) {
      final sorted = List<_StopNode>.from(stops)
        ..sort((a, b) => a.stopId.compareTo(b.stopId));
      final routeIds = <String>{
        for (final stop in sorted) _resolvedRouteId(stop),
      }.where((routeId) => routeId != 'N/A').toList()
        ..sort();
      final stopCodes = sorted.map((stop) => stop.stopId).toList();
      return _StationOption(
        stationName: sorted.first.stopName,
        stopIds: stopCodes,
        routeIds: routeIds,
        stopCodes: stopCodes,
      );
    }).toList()
      ..sort((a, b) => a.stationName.compareTo(b.stationName));

    if (!mounted) return;
    setState(() {
      _stopsById = projectedStops;
      _connections = edges;
      _stationOptions = options;
    });
  }

  List<_RouteConnection> _mapEdgeRows({
    required List<Map<String, dynamic>> edgeRows,
    required Map<String, _StopNode> projectedStops,
  }) {
    final output = <_RouteConnection>[];
    for (final map in edgeRows) {
      final from = (map['from_stop_id']?.toString() ?? '').trim().toUpperCase();
      final to = (map['to_stop_id']?.toString() ?? '').trim().toUpperCase();
      if (!projectedStops.containsKey(from) ||
          !projectedStops.containsKey(to)) {
        continue;
      }

      final routeId = normalizeRouteId(
        (map['route_id']?.toString() ?? '').trim().toUpperCase(),
      );
      final type =
          (map['connection_type']?.toString() ?? 'standard_stop').trim();
      final minutesRaw = map['travel_time_minutes'];
      final minutes = minutesRaw is num
          ? minutesRaw.toInt()
          : int.tryParse(minutesRaw?.toString() ?? '') ?? 2;

      output.add(
        _RouteConnection(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          connectionType: type,
          travelMinutes: minutes.clamp(1, 60),
        ),
      );
    }
    return output;
  }

  List<_RouteConnection> _buildFallbackConnections(List<_StopNode> stops) {
    if (stops.length < 2) return const <_RouteConnection>[];

    final edges = <_RouteConnection>[];
    final seen = <String>{};

    void addEdge({
      required String from,
      required String to,
      required String routeId,
      required String type,
      required int minutes,
    }) {
      if (from == to) return;
      final normalizedRoute = normalizeRouteId(routeId);
      final key = '$from|$to|$normalizedRoute|$type';
      if (!seen.add(key)) return;
      edges.add(
        _RouteConnection(
          fromStopId: from,
          toStopId: to,
          routeId: normalizedRoute,
          connectionType: type,
          travelMinutes: minutes.clamp(1, 60),
        ),
      );
    }

    final byLine = <String, List<_StopNode>>{};
    for (final stop in stops) {
      final line = _resolvedRouteId(stop);
      if (line == 'N/A') continue;
      byLine.putIfAbsent(line, () => <_StopNode>[]).add(stop);
    }

    for (final entry in byLine.entries) {
      final routeId = entry.key;
      final ordered = List<_StopNode>.from(entry.value)
        ..sort((a, b) => _compareStopCode(a.stopId, b.stopId));
      for (var i = 0; i < ordered.length - 1; i++) {
        final a = ordered[i];
        final b = ordered[i + 1];
        addEdge(
          from: a.stopId,
          to: b.stopId,
          routeId: routeId,
          type: 'standard_stop',
          minutes: 2,
        );
        addEdge(
          from: b.stopId,
          to: a.stopId,
          routeId: routeId,
          type: 'standard_stop',
          minutes: 2,
        );
      }
    }

    final byStation = <String, List<_StopNode>>{};
    for (final stop in stops) {
      final key = stop.stopName.toUpperCase();
      byStation.putIfAbsent(key, () => <_StopNode>[]).add(stop);
    }
    for (final stationStops in byStation.values) {
      if (stationStops.length < 2) continue;
      for (var i = 0; i < stationStops.length - 1; i++) {
        for (var j = i + 1; j < stationStops.length; j++) {
          final a = stationStops[i];
          final b = stationStops[j];
          final aLine = _resolvedRouteId(a);
          final bLine = _resolvedRouteId(b);
          if (aLine == bLine) continue;
          addEdge(
            from: a.stopId,
            to: b.stopId,
            routeId: aLine,
            type: 'interchange_transfer',
            minutes: 3,
          );
          addEdge(
            from: b.stopId,
            to: a.stopId,
            routeId: bLine,
            type: 'interchange_transfer',
            minutes: 3,
          );
        }
      }
    }

    return edges;
  }

  String _resolvedRouteId(_StopNode stop) {
    if (stop.routeId.trim().isNotEmpty) {
      return normalizeRouteId(stop.routeId);
    }
    return normalizeRouteId(_inferRouteIdFromStopId(stop.stopId));
  }

  static int _compareStopCode(String a, String b) {
    final pa = _StopIdParts.tryParse(a);
    final pb = _StopIdParts.tryParse(b);
    if (pa == null || pb == null) {
      return a.compareTo(b);
    }
    if (pa.prefix != pb.prefix) return pa.prefix.compareTo(pb.prefix);
    if (pa.number != pb.number) return pa.number.compareTo(pb.number);
    return pa.suffix.compareTo(pb.suffix);
  }

  Future<void> _refreshLocation({bool silentOnError = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silentOnError) {
          _showMessage('Location services are disabled.');
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!silentOnError) {
          _showMessage('Location permission was denied.');
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );

      if (!mounted) return;
      setState(() => _userPosition = position);
    } catch (e) {
      if (!silentOnError) {
        _showMessage('Failed to get location: $e');
      }
    }
  }

  void _onDestinationSelected(_StationOption option) {
    FocusScope.of(context).unfocus();
    setState(() => _selectedDestination = option);
    _computeRoute();
  }

  Future<void> _computeRoute() async {
    if (_selectedDestination == null || _isRouting) return;
    setState(() => _isRouting = true);
    try {
      await _refreshLocation(silentOnError: true);
      Position? position = _userPosition;
      if (position == null) {
        await _refreshLocation();
        position = _userPosition;
      }
      if (position == null) {
        _showMessage('Location unavailable. Cannot compute route.');
        return;
      }

      final originStop = _nearestStop(position.latitude, position.longitude);
      if (originStop == null) {
        _showMessage('Unable to detect nearest origin station.');
        return;
      }

      final destination = _selectedDestination!;
      if (destination.stopIds.contains(originStop.stopId)) {
        if (!mounted) return;
        setState(() {
          _resolvedRoute = null;
          _focusedStopId = originStop.stopId;
        });
        _showMessage('You are already at ${originStop.stopName}.');
        return;
      }

      _DijkstraResult? bestResult;
      for (final candidateStopId in destination.stopIds) {
        final result = _shortestPath(
          originStopId: originStop.stopId,
          destinationStopId: candidateStopId,
        );
        if (result == null) continue;
        if (bestResult == null ||
            result.totalMinutes < bestResult.totalMinutes) {
          bestResult = result;
        }
      }

      if (bestResult == null) {
        _showMessage('No route found for selected destination.');
        return;
      }
      final resolved = bestResult;

      final routeLines = <String>[];
      String? previousLine;
      for (final edge in bestResult.path) {
        final normalized = normalizeRouteId(edge.routeId);
        if (normalized == previousLine) continue;
        routeLines.add(normalized);
        previousLine = normalized;
      }

      final interchanges = <_InterchangeMarker>[];
      for (var i = 1; i < bestResult.path.length; i++) {
        final previous = bestResult.path[i - 1];
        final current = bestResult.path[i];
        final previousLine = normalizeRouteId(previous.routeId);
        final currentLine = normalizeRouteId(current.routeId);
        if (previousLine == currentLine &&
            !previous.connectionType.toLowerCase().contains('transfer') &&
            !current.connectionType.toLowerCase().contains('transfer')) {
          continue;
        }
        final colors = <Color>[
          getRouteColor(previousLine),
          getRouteColor(currentLine),
        ];
        interchanges.add(
          _InterchangeMarker(
            stopId: current.fromStopId,
            colors: colors,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _resolvedRoute = _ResolvedRoute(
          originStopId: originStop.stopId,
          destinationStopId: resolved.destinationStopId,
          edges: resolved.path,
          totalMinutes: resolved.totalMinutes,
          routeLines: routeLines,
          interchangeMarkers: interchanges,
        );
        _focusedStopId = resolved.destinationStopId;
      });
      if (routeLines.isNotEmpty) {
        _showMessage('Route ready via ${routeLines.join(' -> ')}');
      }
    } catch (e) {
      _showMessage('Failed to compute route: $e');
    } finally {
      if (mounted) {
        setState(() => _isRouting = false);
      }
    }
  }

  _StopNode? _nearestStop(
    double latitude,
    double longitude, {
    Set<String>? allowedStopIds,
  }) {
    _StopNode? nearest;
    double nearestMeters = double.infinity;
    for (final stop in _stopsById.values) {
      if (allowedStopIds != null && !allowedStopIds.contains(stop.stopId)) {
        continue;
      }
      final meters = Geolocator.distanceBetween(
        latitude,
        longitude,
        stop.latitude,
        stop.longitude,
      );
      if (meters < nearestMeters) {
        nearestMeters = meters;
        nearest = stop;
      }
    }
    return nearest;
  }

  _DijkstraResult? _shortestPath({
    required String originStopId,
    required String destinationStopId,
  }) {
    if (!_stopsById.containsKey(originStopId) ||
        !_stopsById.containsKey(destinationStopId)) {
      return null;
    }

    final adjacency = <String, List<_RouteConnection>>{};
    void addEdge(_RouteConnection edge) {
      adjacency
          .putIfAbsent(edge.fromStopId, () => <_RouteConnection>[])
          .add(edge);
    }

    for (final edge in _connections) {
      addEdge(edge);
      addEdge(edge.reversed());
    }

    final distances = <String, int>{originStopId: 0};
    final previousNode = <String, String>{};
    final previousEdge = <String, _RouteConnection>{};
    final visited = <String>{};

    while (visited.length < _stopsById.length) {
      String? current;
      var currentDistance = 1 << 30;
      for (final id in _stopsById.keys) {
        if (visited.contains(id)) continue;
        final dist = distances[id];
        if (dist == null) continue;
        if (dist < currentDistance) {
          currentDistance = dist;
          current = id;
        }
      }

      if (current == null || currentDistance >= (1 << 29)) break;
      if (current == destinationStopId) break;

      visited.add(current);
      for (final edge in adjacency[current] ?? const <_RouteConnection>[]) {
        if (visited.contains(edge.toStopId)) continue;
        final candidate = currentDistance + edge.travelMinutes;
        if (candidate < (distances[edge.toStopId] ?? (1 << 30))) {
          distances[edge.toStopId] = candidate;
          previousNode[edge.toStopId] = current;
          previousEdge[edge.toStopId] = edge;
        }
      }
    }

    if (!previousEdge.containsKey(destinationStopId)) return null;
    final path = <_RouteConnection>[];
    var cursor = destinationStopId;
    while (cursor != originStopId) {
      final edge = previousEdge[cursor];
      final parent = previousNode[cursor];
      if (edge == null || parent == null) break;
      path.add(edge);
      cursor = parent;
    }
    if (cursor != originStopId) return null;
    final ordered = path.reversed.toList();
    final total = ordered.fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
    return _DijkstraResult(
      destinationStopId: destinationStopId,
      path: ordered,
      totalMinutes: total,
    );
  }

  _MapTransform _buildMapTransform(List<_StopNode> stops) {
    final anchors = <_AnchorPair>[];
    for (final stop in stops) {
      final target = _anchorMapByStopId[stop.stopId];
      if (target == null) continue;
      anchors.add(
        _AnchorPair(
          longitude: stop.longitude,
          latitude: stop.latitude,
          mapX: target.dx,
          mapY: target.dy,
        ),
      );
    }

    final affine = _MapTransform.fromAnchors(anchors);
    if (affine != null) {
      return affine;
    }

    final minLat = stops.map((stop) => stop.latitude).reduce(math.min);
    final maxLat = stops.map((stop) => stop.latitude).reduce(math.max);
    final minLon = stops.map((stop) => stop.longitude).reduce(math.min);
    final maxLon = stops.map((stop) => stop.longitude).reduce(math.max);
    return _MapTransform.fallback(
      minLongitude: minLon,
      maxLongitude: maxLon,
      minLatitude: minLat,
      maxLatitude: maxLat,
      marginX: _mapMarginX,
      marginY: _mapMarginY,
    );
  }

  Map<String, Offset> _projectStopOffsets({
    required List<_StopNode> rawStops,
    required _MapTransform transform,
  }) {
    final points = <String, Offset>{};
    for (final stop in rawStops) {
      points[stop.stopId] = transform.project(stop.longitude, stop.latitude);
    }

    for (final stop in rawStops) {
      final anchor = _anchorMapByStopId[stop.stopId];
      if (anchor != null) {
        points[stop.stopId] = anchor;
      }
    }

    final byLine = <String, List<_StopNode>>{};
    for (final stop in rawStops) {
      final line = _resolvedRouteId(stop);
      if (line == 'N/A') continue;
      byLine.putIfAbsent(line, () => <_StopNode>[]).add(stop);
    }

    for (final lineStops in byLine.values) {
      final ordered = List<_StopNode>.from(lineStops)
        ..sort((a, b) => _compareStopCode(a.stopId, b.stopId));
      final anchorIndices = <int>[];
      for (var i = 0; i < ordered.length; i++) {
        if (_anchorMapByStopId.containsKey(ordered[i].stopId)) {
          anchorIndices.add(i);
        }
      }
      if (anchorIndices.length < 2) continue;

      for (var i = 0; i < ordered.length; i++) {
        final current = ordered[i];
        if (_anchorMapByStopId.containsKey(current.stopId)) continue;

        int? previousAnchorIndex;
        int? nextAnchorIndex;
        for (final anchorIndex in anchorIndices) {
          if (anchorIndex < i) {
            previousAnchorIndex = anchorIndex;
          } else if (anchorIndex > i) {
            nextAnchorIndex = anchorIndex;
            break;
          }
        }
        if (previousAnchorIndex == null || nextAnchorIndex == null) {
          continue;
        }

        final prevStopId = ordered[previousAnchorIndex].stopId;
        final nextStopId = ordered[nextAnchorIndex].stopId;
        final prevPoint = points[prevStopId];
        final nextPoint = points[nextStopId];
        if (prevPoint == null || nextPoint == null) continue;

        final segmentLength = nextAnchorIndex - previousAnchorIndex;
        if (segmentLength <= 0) continue;
        final t = (i - previousAnchorIndex) / segmentLength;
        final interpolated = Offset.lerp(prevPoint, nextPoint, t);
        if (interpolated != null) {
          points[current.stopId] = interpolated;
        }
      }
    }

    final clamped = <String, Offset>{};
    for (final entry in points.entries) {
      clamped[entry.key] = Offset(
        entry.value.dx.clamp(0.0, 1.0),
        entry.value.dy.clamp(0.0, 1.0),
      );
    }
    return clamped;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  _StopNode? _stopAtCanvasPoint(Offset localPosition, Size size) {
    _StopNode? closest;
    var closestDistance = double.infinity;
    for (final stop in _stopsById.values) {
      final point = Offset(stop.mapX * size.width, stop.mapY * size.height);
      final distance = (point - localPosition).distance;
      if (distance < 22 && distance < closestDistance) {
        closest = stop;
        closestDistance = distance;
      }
    }
    return closest;
  }

  Future<void> _handleStationTap(_StopNode stop) async {
    if (mounted) {
      setState(() => _focusedStopId = stop.stopId);
    }
    _StationOption? option;
    for (final candidate in _stationOptions) {
      if (candidate.stationName.toUpperCase() == stop.stopName.toUpperCase()) {
        option = candidate;
        break;
      }
    }

    if (option == null || !mounted) {
      _showMessage('This station is not ready for routing yet.');
      return;
    }
    _onDestinationSelected(option);
    /* final selected = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.stopName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${stop.stopId} • ${stop.routeId}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.alt_route_rounded),
                    label: const Text('Use As Destination'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != true || option == null || !mounted) return;
    _onDestinationSelected(option);
    */
  }

  List<Widget> _buildStationMarkers(Size size) {
    return _stopsById.values.map((stop) {
      final left = (stop.mapX * size.width).clamp(0.0, size.width);
      final top = (stop.mapY * size.height).clamp(0.0, size.height);
      final isOrigin = _resolvedRoute?.originStopId == stop.stopId;
      final isDestination = _resolvedRoute?.destinationStopId == stop.stopId;
      final isInterchange = _resolvedRoute?.interchangeMarkers.any(
            (marker) => marker.stopId == stop.stopId,
          ) ==
          true;
      final isRouteStop = isOrigin ||
          isInterchange ||
          isDestination ||
          _resolvedRoute?.edges.any(
                (edge) =>
                    edge.fromStopId == stop.stopId ||
                    edge.toStopId == stop.stopId,
              ) ==
              true;
      final isFocused = _focusedStopId == stop.stopId;
      final markerSize = isOrigin || isDestination
          ? 17.0
          : isInterchange
              ? 16.0
              : isRouteStop || isFocused
                  ? 15.0
                  : 11.0;
      final showLabel = isFocused || isOrigin || isDestination || isInterchange;

      return Positioned(
        left: left - 22,
        top: top - 22,
        child: Tooltip(
          message: '${stop.stopName} • ${stop.stopId}',
          child: GestureDetector(
            onTap: () => _handleStationTap(stop),
            child: SizedBox(
              width: showLabel ? 128 : 44,
              height: showLabel ? 58 : 44,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  if (isRouteStop || isFocused)
                    Positioned(
                      top: 8,
                      child: Container(
                        width: markerSize + 12,
                        height: markerSize + 12,
                        decoration: BoxDecoration(
                          color: getRouteColor(stop.routeId)
                              .withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 14,
                    child: Container(
                      width: markerSize,
                      height: markerSize,
                      decoration: BoxDecoration(
                        color: isFocused || isOrigin || isDestination
                            ? getRouteColor(stop.routeId)
                            : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: getRouteColor(stop.routeId),
                          width: isRouteStop || isFocused ? 3.5 : 2.2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x220F172A),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (showLabel)
                    Positioned(
                      top: 34,
                      child: _StationMapLabel(
                        stopName: isOrigin
                            ? 'Start  ${stop.stopName}'
                            : isDestination
                                ? 'End  ${stop.stopName}'
                                : isInterchange
                                    ? 'Change  ${stop.stopName}'
                                    : stop.stopName,
                        stopId: stop.stopId,
                        highlighted: isRouteStop || isFocused,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.map_rounded,
          leadingText: 'Rail',
          accentText: 'Pulse',
          badgeText: 'MAP',
          subtitle: 'Interactive overlay',
        ),
      ),
      body: TrainLoadingTransition(
        isLoading: _isLoading,
        loadingLabel: 'Drawing network map...',
        arrivalLabel: 'Map ready',
        child: _errorText != null
            ? _MapErrorState(errorText: _errorText!, onRetry: _bootstrap)
            : Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.white,
                      child: InteractiveViewer(
                        transformationController: _mapController,
                        minScale: 1.0,
                        maxScale: 5.0,
                        panEnabled: true,
                        boundaryMargin: const EdgeInsets.all(80),
                        child: AspectRatio(
                          aspectRatio: _mapAspectRatio,
                          child: AnimatedBuilder(
                            animation: _blinkController,
                            builder: (context, _) {
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = Size(
                                    constraints.maxWidth,
                                    constraints.maxHeight,
                                  );
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (details) {
                                      final stop = _stopAtCanvasPoint(
                                        details.localPosition,
                                        size,
                                      );
                                      if (stop != null) {
                                        _handleStationTap(stop);
                                      } else if (_focusedStopId != null) {
                                        setState(() => _focusedStopId = null);
                                      }
                                    },
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.asset(
                                          'assets/images/klang_valley_map.png',
                                          fit: BoxFit.cover,
                                        ),
                                        CustomPaint(
                                          painter: _RouteHighlightPainter(
                                            stopsById: _stopsById,
                                            route: _resolvedRoute,
                                            blinkValue: _blinkController.value,
                                          ),
                                        ),
                                        ..._buildStationMarkers(size),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_isRouting)
                    const SafeArea(
                      minimum: EdgeInsets.only(top: 12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: _MapRoutingPill(),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _MapRoutingPill extends StatelessWidget {
  const _MapRoutingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F101828),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Drawing route...',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationMapLabel extends StatelessWidget {
  final String stopName;
  final String stopId;
  final bool highlighted;

  const _StationMapLabel({
    required this.stopName,
    required this.stopId,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF0A3A8B) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              highlighted ? const Color(0xFF0A3A8B) : const Color(0xFFDCE6F5),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14101828),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '$stopId  $stopName',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: highlighted ? Colors.white : const Color(0xFF344054),
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _MapErrorState extends StatelessWidget {
  final String errorText;
  final VoidCallback onRetry;

  const _MapErrorState({
    required this.errorText,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 34,
              color: Color(0xFFB42318),
            ),
            const SizedBox(height: 10),
            Text(
              errorText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF475467),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteHighlightPainter extends CustomPainter {
  final Map<String, _StopNode> stopsById;
  final _ResolvedRoute? route;
  final double blinkValue;

  const _RouteHighlightPainter({
    required this.stopsById,
    required this.route,
    required this.blinkValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final data = route;
    if (data == null) return;

    final pulse = 0.55 + (blinkValue * 0.45);

    for (final edge in data.edges) {
      final from = stopsById[edge.fromStopId];
      final to = stopsById[edge.toStopId];
      if (from == null || to == null) continue;

      final baseColor = edge.isTransfer
          ? const Color(0xFF94A3B8)
          : getRouteColor(edge.routeId);
      final brightColor =
          Color.lerp(baseColor, Colors.white, pulse * 0.35) ?? baseColor;
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = edge.isTransfer ? 2.0 : 2.8
        ..color = brightColor.withValues(alpha: 0.80 + (pulse * 0.15));

      final p1 = Offset(from.mapX * size.width, from.mapY * size.height);
      final p2 = Offset(to.mapX * size.width, to.mapY * size.height);
      canvas.drawLine(p1, p2, line);
    }

    for (final marker in data.interchangeMarkers) {
      final stop = stopsById[marker.stopId];
      if (stop == null) continue;
      final center = Offset(stop.mapX * size.width, stop.mapY * size.height);
      final radius = 7.2 + (pulse * 2.0);
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.95);
      if (marker.colors.length < 2) {
        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = marker.colors.first.withValues(alpha: 0.85);
        canvas.drawCircle(center, radius, fill);
      } else {
        final arcRect = Rect.fromCircle(center: center, radius: radius);
        final p0 = Paint()
          ..style = PaintingStyle.fill
          ..color = marker.colors[0].withValues(alpha: 0.9);
        final p1 = Paint()
          ..style = PaintingStyle.fill
          ..color = marker.colors[1].withValues(alpha: 0.9);
        canvas.drawArc(arcRect, -math.pi / 2, math.pi, true, p0);
        canvas.drawArc(arcRect, math.pi / 2, math.pi, true, p1);
      }
      canvas.drawCircle(center, radius, border);
    }

    final origin = stopsById[data.originStopId];
    final destination = stopsById[data.destinationStopId];
    if (origin != null) {
      _paintTerminal(
        canvas: canvas,
        center: Offset(origin.mapX * size.width, origin.mapY * size.height),
        color: const Color(0xFF0A84FF),
        label: 'S',
        pulse: pulse,
      );
    }
    if (destination != null) {
      _paintTerminal(
        canvas: canvas,
        center: Offset(
            destination.mapX * size.width, destination.mapY * size.height),
        color: const Color(0xFFEF4444),
        label: 'D',
        pulse: pulse,
      );
    }
  }

  static void _paintTerminal({
    required Canvas canvas,
    required Offset center,
    required Color color,
    required String label,
    required double pulse,
  }) {
    final glow = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.28 + (pulse * 0.12));
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawCircle(center, 12 + (pulse * 3), glow);
    canvas.drawCircle(center, 9, fill);

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - (textPainter.width / 2),
        center.dy - (textPainter.height / 2),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _RouteHighlightPainter oldDelegate) {
    return oldDelegate.route != route || oldDelegate.blinkValue != blinkValue;
  }
}

class _AnchorPair {
  final double longitude;
  final double latitude;
  final double mapX;
  final double mapY;

  const _AnchorPair({
    required this.longitude,
    required this.latitude,
    required this.mapX,
    required this.mapY,
  });
}

class _MapTransform {
  final double x0;
  final double xLon;
  final double xLat;
  final double y0;
  final double yLon;
  final double yLat;

  const _MapTransform({
    required this.x0,
    required this.xLon,
    required this.xLat,
    required this.y0,
    required this.yLon,
    required this.yLat,
  });

  Offset project(double lon, double lat) {
    return Offset(
      x0 + (xLon * lon) + (xLat * lat),
      y0 + (yLon * lon) + (yLat * lat),
    );
  }

  static _MapTransform? fromAnchors(List<_AnchorPair> anchors) {
    if (anchors.length < 3) return null;

    var s1 = 0.0;
    var sLon = 0.0;
    var sLat = 0.0;
    var sLon2 = 0.0;
    var sLat2 = 0.0;
    var sLonLat = 0.0;
    var sx = 0.0;
    var sxLon = 0.0;
    var sxLat = 0.0;
    var sy = 0.0;
    var syLon = 0.0;
    var syLat = 0.0;

    for (final anchor in anchors) {
      s1 += 1.0;
      sLon += anchor.longitude;
      sLat += anchor.latitude;
      sLon2 += anchor.longitude * anchor.longitude;
      sLat2 += anchor.latitude * anchor.latitude;
      sLonLat += anchor.longitude * anchor.latitude;
      sx += anchor.mapX;
      sxLon += anchor.mapX * anchor.longitude;
      sxLat += anchor.mapX * anchor.latitude;
      sy += anchor.mapY;
      syLon += anchor.mapY * anchor.longitude;
      syLat += anchor.mapY * anchor.latitude;
    }

    final matrix = <List<double>>[
      <double>[s1, sLon, sLat],
      <double>[sLon, sLon2, sLonLat],
      <double>[sLat, sLonLat, sLat2],
    ];
    final xVector = <double>[sx, sxLon, sxLat];
    final yVector = <double>[sy, syLon, syLat];

    final xCoeffs = _solveLinear3(matrix, xVector);
    final yCoeffs = _solveLinear3(matrix, yVector);
    if (xCoeffs == null || yCoeffs == null) return null;

    return _MapTransform(
      x0: xCoeffs[0],
      xLon: xCoeffs[1],
      xLat: xCoeffs[2],
      y0: yCoeffs[0],
      yLon: yCoeffs[1],
      yLat: yCoeffs[2],
    );
  }

  static _MapTransform fallback({
    required double minLongitude,
    required double maxLongitude,
    required double minLatitude,
    required double maxLatitude,
    required double marginX,
    required double marginY,
  }) {
    final lonSpan = (maxLongitude - minLongitude).abs();
    final latSpan = (maxLatitude - minLatitude).abs();
    final safeLonSpan = lonSpan < 0.000001 ? 1.0 : lonSpan;
    final safeLatSpan = latSpan < 0.000001 ? 1.0 : latSpan;

    final xLon = (1 - (marginX * 2)) / safeLonSpan;
    final x0 = marginX - (xLon * minLongitude);
    final yLat = -(1 - (marginY * 2)) / safeLatSpan;
    final y0 = marginY + ((1 - (marginY * 2)) * (maxLatitude / safeLatSpan));

    return _MapTransform(
      x0: x0,
      xLon: xLon,
      xLat: 0,
      y0: y0,
      yLon: 0,
      yLat: yLat,
    );
  }
}

List<double>? _solveLinear3(List<List<double>> matrix, List<double> vector) {
  final a = <List<double>>[
    <double>[matrix[0][0], matrix[0][1], matrix[0][2], vector[0]],
    <double>[matrix[1][0], matrix[1][1], matrix[1][2], vector[1]],
    <double>[matrix[2][0], matrix[2][1], matrix[2][2], vector[2]],
  ];

  for (var col = 0; col < 3; col++) {
    var pivot = col;
    for (var row = col + 1; row < 3; row++) {
      if (a[row][col].abs() > a[pivot][col].abs()) {
        pivot = row;
      }
    }
    if (a[pivot][col].abs() < 1e-12) {
      return null;
    }
    if (pivot != col) {
      final temp = a[col];
      a[col] = a[pivot];
      a[pivot] = temp;
    }

    final pivotValue = a[col][col];
    for (var j = col; j < 4; j++) {
      a[col][j] /= pivotValue;
    }
    for (var row = 0; row < 3; row++) {
      if (row == col) continue;
      final factor = a[row][col];
      for (var j = col; j < 4; j++) {
        a[row][j] -= factor * a[col][j];
      }
    }
  }

  return <double>[a[0][3], a[1][3], a[2][3]];
}

String _inferRouteIdFromStopId(String stopId) {
  final match = RegExp(r'^[A-Za-z]+').firstMatch(stopId.trim());
  return (match?.group(0) ?? 'N/A').toUpperCase();
}

class _StopIdParts {
  final String prefix;
  final int number;
  final String suffix;

  const _StopIdParts({
    required this.prefix,
    required this.number,
    required this.suffix,
  });

  static _StopIdParts? tryParse(String stopId) {
    final cleaned = stopId.trim().toUpperCase();
    final match = RegExp(r'^([A-Z]+)(\d+)([A-Z]*)$').firstMatch(cleaned);
    if (match == null) return null;
    final number = int.tryParse(match.group(2) ?? '');
    if (number == null) return null;
    return _StopIdParts(
      prefix: match.group(1) ?? '',
      number: number,
      suffix: match.group(3) ?? '',
    );
  }
}

class _StopNode {
  final String stopId;
  final String stopName;
  final String routeId;
  final double latitude;
  final double longitude;
  final double mapX;
  final double mapY;

  const _StopNode({
    required this.stopId,
    required this.stopName,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.mapX,
    required this.mapY,
  });

  _StopNode copyWith({
    double? mapX,
    double? mapY,
  }) {
    return _StopNode(
      stopId: stopId,
      stopName: stopName,
      routeId: routeId,
      latitude: latitude,
      longitude: longitude,
      mapX: mapX ?? this.mapX,
      mapY: mapY ?? this.mapY,
    );
  }
}

class _RouteConnection {
  final String fromStopId;
  final String toStopId;
  final String routeId;
  final String connectionType;
  final int travelMinutes;

  const _RouteConnection({
    required this.fromStopId,
    required this.toStopId,
    required this.routeId,
    required this.connectionType,
    required this.travelMinutes,
  });

  bool get isTransfer => connectionType.toLowerCase().contains('transfer');

  _RouteConnection reversed() {
    return _RouteConnection(
      fromStopId: toStopId,
      toStopId: fromStopId,
      routeId: routeId,
      connectionType: connectionType,
      travelMinutes: travelMinutes,
    );
  }
}

class _StationOption {
  final String stationName;
  final List<String> stopIds;
  final List<String> routeIds;
  final List<String> stopCodes;

  const _StationOption({
    required this.stationName,
    required this.stopIds,
    required this.routeIds,
    required this.stopCodes,
  });
}

class _DijkstraResult {
  final String destinationStopId;
  final List<_RouteConnection> path;
  final int totalMinutes;

  const _DijkstraResult({
    required this.destinationStopId,
    required this.path,
    required this.totalMinutes,
  });
}

class _ResolvedRoute {
  final String originStopId;
  final String destinationStopId;
  final List<_RouteConnection> edges;
  final int totalMinutes;
  final List<String> routeLines;
  final List<_InterchangeMarker> interchangeMarkers;

  const _ResolvedRoute({
    required this.originStopId,
    required this.destinationStopId,
    required this.edges,
    required this.totalMinutes,
    required this.routeLines,
    required this.interchangeMarkers,
  });
}

class _InterchangeMarker {
  final String stopId;
  final List<Color> colors;

  const _InterchangeMarker({
    required this.stopId,
    required this.colors,
  });
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
