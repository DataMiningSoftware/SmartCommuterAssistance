import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/route_colors.dart';
import '../services/database_service.dart';
import '../services/station_service.dart';

class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final StationService _stationService = StationService();
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allStopsRaw = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _allStations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _filteredStations = <Map<String, dynamic>>[];
  Map<String, List<String>> _uniqueStationLines = <String, List<String>>{};
  Map<String, List<String>> _stationCodesByName = <String, List<String>>{};
  Map<String, List<String>> _stationRoutesByName = <String, List<String>>{};
  late Future<void> _stationsFuture;
  bool _isFindingNearest = false;
  bool _isPlanningRoute = false;
  Position? _userPosition;
  List<_RouteEdge>? _routeEdgesCache;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _stationsFuture = _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    try {
      final rows = await Supabase.instance.client.from('train_stops_kl').select();
      final stations = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      await _databaseService.cacheTrainStops(stations);
      await _syncUniqueStations();
      await _syncRouteConnectionsCache();
      _setStations(stations);
      return;
    } catch (_) {
      final cachedStations = await _databaseService.getCachedTrainStops();
      if (cachedStations.isNotEmpty) {
        _setStations(cachedStations);
        _showMessage('Using offline cached stations.');
        return;
      }
      rethrow;
    }
  }

  Future<void> _syncUniqueStations() async {
    try {
      final uniqueStations = await _stationService.getUniqueStations();
      final mapped = <String, List<String>>{};
      for (final row in uniqueStations) {
        final stationName = row['station_name']?.toString().trim();
        if (stationName == null || stationName.isEmpty) continue;
        final linesRaw = row['lines'];
        final lines = linesRaw is List
            ? linesRaw.map((line) => line.toString().trim().toUpperCase()).where((line) => line.isNotEmpty).toList()
            : <String>[];
        mapped[stationName.toUpperCase()] = lines;
      }
      if (!mounted) return;
      setState(() => _uniqueStationLines = mapped);
    } catch (_) {
      // RPC is optional; UI falls back to regular line label.
    }
  }

  void _setStations(List<Map<String, dynamic>> stations) {
    final mutableStops = stations
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: true);

    final byName = <String, Map<String, dynamic>>{};
    final codesByName = <String, Set<String>>{};
    final routesByName = <String, Set<String>>{};
    for (final stop in mutableStops) {
      final name = _stationName(stop);
      final key = name.toUpperCase();
      byName.putIfAbsent(key, () => Map<String, dynamic>.from(stop));
      final representative = byName[key]!;

      final stopCode = _stationStopId(stop);
      if (stopCode.isNotEmpty && stopCode != 'N/A') {
        codesByName.putIfAbsent(key, () => <String>{}).add(stopCode.toUpperCase());
      }
      final routeId = _stationRouteId(stop);
      if (routeId.isNotEmpty && routeId != 'N/A') {
        routesByName.putIfAbsent(key, () => <String>{}).add(routeId.toUpperCase());
      }

      // If RPC grouped lines exists, keep a stable primary route id for color badge.
      final lines = _uniqueStationLines[key];
      if (lines != null && lines.isNotEmpty) {
        representative['route_id'] = lines.first;
      }
      representative['stop_name'] = name;
    }

    final mutableStations = byName.values.toList(growable: true);
    mutableStations.sort((a, b) {
      final aName = _stationName(a).toLowerCase();
      final bName = _stationName(b).toLowerCase();
      return aName.compareTo(bName);
    });

    final normalizedCodesByName = <String, List<String>>{};
    for (final entry in codesByName.entries) {
      final values = entry.value.toList()..sort();
      normalizedCodesByName[entry.key] = values;
    }

    final normalizedRoutesByName = <String, List<String>>{};
    for (final entry in routesByName.entries) {
      final values = entry.value.toList()..sort();
      normalizedRoutesByName[entry.key] = values;
    }

    if (!mounted) return;
    setState(() {
      _allStopsRaw
        ..clear()
        ..addAll(mutableStops);
      _allStations
        ..clear()
        ..addAll(mutableStations);
      _stationCodesByName = normalizedCodesByName;
      _stationRoutesByName = normalizedRoutesByName;
      _filteredStations = List<Map<String, dynamic>>.from(_allStations);
    });
    _applyFilter();
  }

  void _refreshStations() {
    setState(() {
      _stationsFuture = _loadStations();
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredStations = List<Map<String, dynamic>>.from(_allStations));
      if (_userPosition != null) {
        _sortByDistance(_userPosition!);
      }
      return;
    }

    final filtered = _allStations.where((station) {
      final name = _stationName(station).toLowerCase();
      final line = _stationLineLabel(station).toLowerCase();
      final code = _stationCodeLabel(station).toLowerCase();
      return name.contains(query) || line.contains(query) || code.contains(query);
    }).toList();

    setState(() => _filteredStations = filtered);
    if (_userPosition != null) {
      _sortByDistance(_userPosition!);
    }
  }

  Future<void> _findNearestStations() async {
    setState(() => _isFindingNearest = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Location services are disabled.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showMessage('Location permission denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Location permission denied forever. Enable it in settings.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() => _userPosition = position);
      final nearest = _sortByDistance(position);
      if (nearest == null) {
        _showMessage('No valid stop_lat/stop_lon found to calculate distance.');
        return;
      }
      final nearestName = _stationName(nearest);
      final nearestDistance = _distanceMeters(nearest, position)!;
      _showMessage(
        'Nearest: $nearestName (${_StationCard._formatDistance(nearestDistance)}) '
        'at ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
      );
    } catch (e) {
      _showMessage('Failed to get location: $e');
    } finally {
      if (mounted) setState(() => _isFindingNearest = false);
    }
  }

  Future<Position?> _ensureCurrentPosition() async {
    if (_userPosition != null) return _userPosition;

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMessage('Location services are disabled.');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showMessage('Location permission denied.');
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      _showMessage('Location permission denied forever. Enable it in settings.');
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 12),
    );
    if (!mounted) return null;
    setState(() => _userPosition = position);
    return position;
  }

  Future<List<_RouteEdge>> _loadRouteConnections() async {
    if (_routeEdgesCache != null && _routeEdgesCache!.isNotEmpty) {
      return _routeEdgesCache!;
    }

    final cachedRows = await _databaseService.getCachedRouteConnections();
    if (cachedRows.isNotEmpty) {
      final edges = _mapRowsToEdges(cachedRows);
      _routeEdgesCache = edges;
      return edges;
    }

    await _syncRouteConnectionsCache();
    return _routeEdgesCache ?? const <_RouteEdge>[];
  }

  Future<void> _syncRouteConnectionsCache() async {
    try {
      final rows = await Supabase.instance.client
          .from('route_connections')
          .select('from_stop_id,to_stop_id,route_id,travel_time_minutes,connection_type');
      final maps = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (maps.isEmpty) return;
      await _databaseService.cacheRouteConnections(maps);
      _routeEdgesCache = _mapRowsToEdges(maps);
    } catch (_) {
      // Keep silent. Offline fallback reads existing local cache.
    }
  }

  List<_RouteEdge> _mapRowsToEdges(List<Map<String, dynamic>> rows) {
    final edges = <_RouteEdge>[];
    for (final map in rows) {
      final from = map['from_stop_id']?.toString() ?? '';
      final to = map['to_stop_id']?.toString() ?? '';
      final routeId = map['route_id']?.toString() ?? '';
      final minutesValue = map['travel_time_minutes'];
      final minutes = minutesValue is num
          ? minutesValue.toInt()
          : int.tryParse(minutesValue?.toString() ?? '') ?? 2;
      final connectionType = map['connection_type']?.toString() ?? 'standard_stop';
      if (from.isEmpty || to.isEmpty || routeId.isEmpty) continue;
      edges.add(
        _RouteEdge(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          travelMinutes: minutes,
          connectionType: connectionType,
        ),
      );
    }
    return edges;
  }

  Future<void> _planRouteToStation(Map<String, dynamic> destinationStation) async {
    if (_isPlanningRoute) return;
    setState(() => _isPlanningRoute = true);
    try {
      final destinationStopIds = _destinationStopIdsForStation(destinationStation);
      if (destinationStopIds.isEmpty) {
        _showMessage('Selected station is missing stop_id.');
        return;
      }

      final position = await _ensureCurrentPosition();
      if (position == null) return;

      final originStation = _nearestStationFromPosition(position);
      if (originStation == null) {
        _showMessage('Could not determine nearest origin station.');
        return;
      }

      final originStopId = _stationStopId(originStation);
      if (destinationStopIds.contains(originStopId)) {
        _showMessage('You are already nearest to this station.');
        return;
      }

      // Keep local cache fresh when online. Failures are ignored.
      await _syncRouteConnectionsCache();

      final hasInternet = await _hasInternetConnection();
      final rpcResult = hasInternet
          ? await _tryBestRpcRoute(
              originStopId: originStopId,
              destinationStopIds: destinationStopIds,
            )
          : null;

      final _RoutePathResult? plan;
      final String routeSource;
      String resolvedDestinationStopId;
      if (rpcResult != null) {
        plan = rpcResult.plan;
        resolvedDestinationStopId = rpcResult.destinationStopId;
        routeSource = 'Supabase RPC';
      } else {
        final edges = await _loadRouteConnections();
        if (edges.isEmpty) {
          _showMessage(
            'No offline route cache available. Go online once to sync route_connections.',
          );
          return;
        }
        _RoutePathResult? bestLocalPlan;
        String? bestLocalDestination;
        for (final destinationStopId in destinationStopIds) {
          final candidate = _findShortestPath(
            originStopId: originStopId,
            destinationStopId: destinationStopId,
            edges: edges,
          );
          if (candidate == null) continue;
          if (bestLocalPlan == null || candidate.totalMinutes < bestLocalPlan.totalMinutes) {
            bestLocalPlan = candidate;
            bestLocalDestination = destinationStopId;
          }
        }
        plan = bestLocalPlan;
        resolvedDestinationStopId = bestLocalDestination ?? destinationStopIds.first;
        routeSource = hasInternet
            ? 'Offline Fallback (RPC unavailable)'
            : 'Offline Fallback (No internet)';
      }
      final resolvedPlan = plan;
      if (resolvedPlan == null) {
        _showMessage('No route found from $originStopId to ${destinationStopIds.first}.');
        return;
      }

      final walkMeters = _distanceMeters(originStation, position);
      final namesByStopId = _stationNamesByStopId();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) {
          return _RoutePlanSheet(
            originName: _stationName(originStation),
            originStopId: originStopId,
            destinationName: _stationName(destinationStation),
            destinationStopId: resolvedDestinationStopId,
            walkMeters: walkMeters,
            totalMinutes: resolvedPlan.totalMinutes,
            totalStops: resolvedPlan.edges.length,
            segments: _buildRouteSegments(resolvedPlan.edges),
            namesByStopId: namesByStopId,
            routeSource: routeSource,
          );
        },
      );
    } catch (e) {
      _showMessage('Failed to plan route: $e');
    } finally {
      if (mounted) setState(() => _isPlanningRoute = false);
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  List<String> _destinationStopIdsForStation(Map<String, dynamic> station) {
    final selectedName = _stationName(station).toUpperCase();
    final ids = <String>{};

    for (final row in _allStopsRaw) {
      if (_stationName(row).toUpperCase() != selectedName) continue;
      final id = _stationStopId(row);
      if (id.isNotEmpty && id != 'N/A') {
        ids.add(id);
      }
    }

    if (ids.isEmpty) {
      final id = _stationStopId(station);
      if (id.isNotEmpty && id != 'N/A') {
        ids.add(id);
      }
    }
    return ids.toList();
  }

  Future<_RpcRouteResult?> _tryBestRpcRoute({
    required String originStopId,
    required List<String> destinationStopIds,
  }) async {
    _RoutePathResult? bestPlan;
    String? bestDestination;

    for (final destinationStopId in destinationStopIds) {
      final candidate = await _tryRpcRoute(
        originStopId: originStopId,
        destinationStopId: destinationStopId,
      );
      if (candidate == null) continue;
      if (bestPlan == null || candidate.totalMinutes < bestPlan.totalMinutes) {
        bestPlan = candidate;
        bestDestination = destinationStopId;
      }
    }

    if (bestPlan == null || bestDestination == null) return null;
    return _RpcRouteResult(
      destinationStopId: bestDestination,
      plan: bestPlan,
    );
  }

  Future<_RoutePathResult?> _tryRpcRoute({
    required String originStopId,
    required String destinationStopId,
  }) async {
    try {
      final response = await Supabase.instance.client
          .rpc(
            'find_route',
            params: {
              'start_stop': originStopId,
              'end_stop': destinationStopId,
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response == null) return null;
      final rows = response is List ? response : <dynamic>[response];
      if (rows.isEmpty || rows.first is! Map) return null;

      final first = Map<String, dynamic>.from(rows.first as Map);
      final pathArray = (first['path_array'] as List<dynamic>?)
              ?.map((item) => item.toString())
              .toList() ??
          const <String>[];
      if (pathArray.length < 2) return null;

      final totalTimeRaw = first['total_time'];
      final totalTime = totalTimeRaw is num
          ? totalTimeRaw.toInt()
          : int.tryParse(totalTimeRaw?.toString() ?? '');
      final edges = await _edgesFromPathArray(pathArray, totalTimeHint: totalTime);
      if (edges.isEmpty) return null;

      final computedTotal = edges.fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
      return _RoutePathResult(
        edges: edges,
        totalMinutes: totalTime ?? computedTotal,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<_RouteEdge>> _edgesFromPathArray(
    List<String> pathArray, {
    int? totalTimeHint,
  }) async {
    final knownEdges = await _loadRouteConnections();
    final byPair = <String, _RouteEdge>{};
    for (final edge in knownEdges) {
      byPair['${edge.fromStopId}->${edge.toStopId}'] = edge;
    }

    final totalPairs = pathArray.length - 1;
    final fallbackMinutes = totalTimeHint == null || totalPairs <= 0
        ? 2
        : (totalTimeHint / totalPairs).ceil().clamp(1, 10);

    final result = <_RouteEdge>[];
    for (var i = 0; i < pathArray.length - 1; i++) {
      final from = pathArray[i];
      final to = pathArray[i + 1];
      final matched = byPair['$from->$to'];
      if (matched != null) {
        result.add(matched);
        continue;
      }
      result.add(
        _RouteEdge(
          fromStopId: from,
          toStopId: to,
          routeId: _inferRouteIdFromStopId(to),
          travelMinutes: fallbackMinutes,
          connectionType: 'standard_stop',
        ),
      );
    }
    return result;
  }

  Map<String, dynamic>? _nearestStationFromPosition(Position position) {
    Map<String, dynamic>? nearest;
    var bestDistance = double.infinity;

    for (final station in _allStopsRaw) {
      final distance = _distanceMeters(station, position);
      if (distance == null) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = station;
      }
    }
    return nearest;
  }

  _RoutePathResult? _findShortestPath({
    required String originStopId,
    required String destinationStopId,
    required List<_RouteEdge> edges,
  }) {
    final adjacency = <String, List<_RouteEdge>>{};
    final nodes = <String>{};
    for (final edge in edges) {
      adjacency.putIfAbsent(edge.fromStopId, () => <_RouteEdge>[]).add(edge);
      nodes.add(edge.fromStopId);
      nodes.add(edge.toStopId);
    }
    nodes.add(originStopId);
    nodes.add(destinationStopId);

    final distances = <String, int>{
      for (final node in nodes) node: 1 << 30,
    };
    final previousNode = <String, String>{};
    final previousEdge = <String, _RouteEdge>{};
    final visited = <String>{};
    distances[originStopId] = 0;

    while (visited.length < nodes.length) {
      String? current;
      var currentDistance = 1 << 30;
      for (final node in nodes) {
        if (visited.contains(node)) continue;
        final d = distances[node] ?? (1 << 30);
        if (d < currentDistance) {
          currentDistance = d;
          current = node;
        }
      }

      if (current == null || currentDistance >= (1 << 29)) break;
      if (current == destinationStopId) break;
      visited.add(current);

      for (final edge in adjacency[current] ?? const <_RouteEdge>[]) {
        if (visited.contains(edge.toStopId)) continue;
        final alt = currentDistance + edge.travelMinutes;
        if (alt < (distances[edge.toStopId] ?? (1 << 30))) {
          distances[edge.toStopId] = alt;
          previousNode[edge.toStopId] = current;
          previousEdge[edge.toStopId] = edge;
        }
      }
    }

    if (!previousEdge.containsKey(destinationStopId)) return null;

    final pathEdges = <_RouteEdge>[];
    var cursor = destinationStopId;
    while (cursor != originStopId) {
      final edge = previousEdge[cursor];
      final prev = previousNode[cursor];
      if (edge == null || prev == null) break;
      pathEdges.add(edge);
      cursor = prev;
    }
    if (cursor != originStopId) return null;
    final orderedEdges = pathEdges.reversed.toList();
    final total = orderedEdges.fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
    return _RoutePathResult(edges: orderedEdges, totalMinutes: total);
  }

  List<_RouteSegment> _buildRouteSegments(List<_RouteEdge> edges) {
    if (edges.isEmpty) return const <_RouteSegment>[];

    final segments = <_RouteSegment>[];
    var currentRoute = edges.first.routeId;
    var segmentStartStop = edges.first.fromStopId;
    var segmentEndStop = edges.first.toStopId;
    var segmentMinutes = edges.first.travelMinutes;
    var segmentType = edges.first.connectionType;

    for (var i = 1; i < edges.length; i++) {
      final edge = edges[i];
      if (edge.routeId == currentRoute && edge.connectionType == segmentType) {
        segmentEndStop = edge.toStopId;
        segmentMinutes += edge.travelMinutes;
        continue;
      }

      segments.add(
        _RouteSegment(
          routeId: currentRoute,
          connectionType: segmentType,
          fromStopId: segmentStartStop,
          toStopId: segmentEndStop,
          minutes: segmentMinutes,
        ),
      );

      currentRoute = edge.routeId;
      segmentType = edge.connectionType;
      segmentStartStop = edge.fromStopId;
      segmentEndStop = edge.toStopId;
      segmentMinutes = edge.travelMinutes;
    }

    segments.add(
      _RouteSegment(
        routeId: currentRoute,
        connectionType: segmentType,
        fromStopId: segmentStartStop,
        toStopId: segmentEndStop,
        minutes: segmentMinutes,
      ),
    );
    return segments;
  }

  Map<String, String> _stationNamesByStopId() {
    final output = <String, String>{};
    for (final station in _allStopsRaw) {
      final stopId = _stationStopId(station);
      if (stopId.isEmpty || stopId == 'N/A') continue;
      output[stopId] = _stationName(station);
    }
    return output;
  }

  Map<String, dynamic>? _sortByDistance(Position position) {
    final sorted = List<Map<String, dynamic>>.from(_filteredStations);
    sorted.sort((a, b) {
      final aDistance = _distanceMeters(a, position) ?? double.infinity;
      final bDistance = _distanceMeters(b, position) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    Map<String, dynamic>? nearest;
    for (final station in sorted) {
      if (_distanceMeters(station, position) != null) {
        nearest = station;
        break;
      }
    }
    if (!mounted) return nearest;
    setState(() => _filteredStations = sorted);
    return nearest;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _distanceMeters(Map<String, dynamic> station, Position position) {
    final lat = _toDouble(station['stop_lat']);
    final lon = _toDouble(station['stop_lon']);
    if (lat == null || lon == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lon,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Train Stations'),
        actions: [
          IconButton(
            onPressed: _isFindingNearest ? null : _findNearestStations,
            icon: _isFindingNearest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            tooltip: 'Nearest',
          ),
          IconButton(
            onPressed: _refreshStations,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          if (_isPlanningRoute)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by station, line, or code',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<void>(
              future: _stationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: Color(0xFFD7263D),
                            size: 30,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Failed to load stations from Supabase',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF667085)),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _refreshStations,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return _buildLoadedBody();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadedBody() {
    if (_allStations.isEmpty) {
      return const Center(
        child: Text('Connected, but table train_stops_kl has 0 rows.'),
      );
    }

    if (_filteredStations.isEmpty) {
      return const Center(child: Text('No stations match your search.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: _filteredStations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final station = _filteredStations[index];
        return _StationCard(
          name: _stationName(station),
          line: _stationLineLabel(station),
          code: _stationCodeLabel(station),
          routeId: _stationRouteId(station),
          distanceMeters:
              _userPosition == null ? null : _distanceMeters(station, _userPosition!),
          onTap: _isPlanningRoute
              ? () {}
              : () => _planRouteToStation(station),
        );
      },
    );
  }

  static String _pickValue(Map<String, dynamic> row, List<String> keys, {String fallback = 'N/A'}) {
    for (final key in keys) {
      final value = row[key];
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return fallback;
  }

  static String _stationName(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['stop_name', 'station_name', 'name', 'station'],
        fallback: 'Unnamed Station',
      );

  static String _stationLine(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['category', 'line', 'line_name', 'route', 'route_name'],
      );

  static String _stationCode(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['stop_id', 'station_code', 'code', 'stop_code', 'route_id', 'id'],
      );

  static String _stationStopId(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['stop_id', 'station_code', 'code', 'stop_code', 'id'],
      );

  static String _stationRouteId(Map<String, dynamic> row) {
    final routeId = _pickValue(
      row,
      const <String>['route_id', 'line_id', 'route'],
      fallback: '',
    );
    if (routeId.isNotEmpty) return routeId;

    final stopId = _pickValue(
      row,
      const <String>['stop_id', 'station_code', 'code'],
      fallback: '',
    );
    return _inferRouteIdFromStopId(stopId);
  }

  static String _inferRouteIdFromStopId(String stopId) {
    final match = RegExp(r'^[A-Za-z]+').firstMatch(stopId);
    return (match?.group(0) ?? 'N/A').toUpperCase();
  }

  String _stationLineLabel(Map<String, dynamic> row) {
    final nameKey = _stationName(row).toUpperCase();
    final lines = _uniqueStationLines[nameKey];
    if (lines != null && lines.isNotEmpty) {
      return lines.join(' / ');
    }
    final fallbackLines = _stationRoutesByName[nameKey];
    if (fallbackLines != null && fallbackLines.isNotEmpty) {
      return fallbackLines.join(' / ');
    }
    return _stationLine(row);
  }

  String _stationCodeLabel(Map<String, dynamic> row) {
    final nameKey = _stationName(row).toUpperCase();
    final codes = _stationCodesByName[nameKey];
    if (codes != null && codes.isNotEmpty) {
      return codes.join(' / ');
    }
    return _stationCode(row);
  }
}

class _StationCard extends StatelessWidget {
  final String name;
  final String line;
  final String code;
  final String routeId;
  final double? distanceMeters;
  final VoidCallback onTap;

  const _StationCard({
    required this.name,
    required this.line,
    required this.code,
    required this.routeId,
    required this.distanceMeters,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE3EAF7)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: getRouteColor(routeId),
              child: Text(
                normalizeRouteId(routeId),
                style: TextStyle(
                  color: getRouteOnColor(routeId),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    line,
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7FC),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFDDE6F5)),
                  ),
                  child: Text(
                    code,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (distanceMeters != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    _formatDistance(distanceMeters!),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
                const SizedBox(height: 2),
                const Text(
                  'Tap for route',
                  style: TextStyle(fontSize: 11, color: Color(0xFF98A2B3)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }
}

class _RpcRouteResult {
  final String destinationStopId;
  final _RoutePathResult plan;

  const _RpcRouteResult({
    required this.destinationStopId,
    required this.plan,
  });
}

class _RouteEdge {
  final String fromStopId;
  final String toStopId;
  final String routeId;
  final int travelMinutes;
  final String connectionType;

  const _RouteEdge({
    required this.fromStopId,
    required this.toStopId,
    required this.routeId,
    required this.travelMinutes,
    required this.connectionType,
  });
}

class _RoutePathResult {
  final List<_RouteEdge> edges;
  final int totalMinutes;

  const _RoutePathResult({
    required this.edges,
    required this.totalMinutes,
  });
}

class _RouteSegment {
  final String routeId;
  final String connectionType;
  final String fromStopId;
  final String toStopId;
  final int minutes;

  const _RouteSegment({
    required this.routeId,
    required this.connectionType,
    required this.fromStopId,
    required this.toStopId,
    required this.minutes,
  });
}

class _RoutePlanSheet extends StatelessWidget {
  final String originName;
  final String originStopId;
  final String destinationName;
  final String destinationStopId;
  final double? walkMeters;
  final int totalMinutes;
  final int totalStops;
  final List<_RouteSegment> segments;
  final Map<String, String> namesByStopId;
  final String routeSource;

  const _RoutePlanSheet({
    required this.originName,
    required this.originStopId,
    required this.destinationName,
    required this.destinationStopId,
    required this.walkMeters,
    required this.totalMinutes,
    required this.totalStops,
    required this.segments,
    required this.namesByStopId,
    required this.routeSource,
  });

  @override
  Widget build(BuildContext context) {
    final estimatedWalk = walkMeters == null ? null : (walkMeters! / 75).round();
    final totalDisplayMinutes = estimatedWalk == null ? totalMinutes : totalMinutes + estimatedWalk;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suggested Route',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '$originName ($originStopId) -> $destinationName ($destinationStopId)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'ETA ~ $totalDisplayMinutes min • $totalStops stops',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            Text(
              'Source: $routeSource',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            if (walkMeters != null)
              Text(
                'Walk to origin: ${_formatWalk(walkMeters!)}',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: segments.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final segment = segments[index];
                  final fromName = namesByStopId[segment.fromStopId] ?? segment.fromStopId;
                  final toName = namesByStopId[segment.toStopId] ?? segment.toStopId;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE3EAF7)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: getRouteColor(segment.routeId),
                          child: Text(
                            normalizeRouteId(segment.routeId),
                            style: TextStyle(
                              color: getRouteOnColor(segment.routeId),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _segmentText(
                              routeId: segment.routeId,
                              connectionType: segment.connectionType,
                              fromName: fromName,
                              toName: toName,
                              minutes: segment.minutes,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
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

  static String _segmentText({
    required String routeId,
    required String connectionType,
    required String fromName,
    required String toName,
    required int minutes,
  }) {
    if (connectionType.toLowerCase().contains('transfer')) {
      return 'Transfer from $fromName to $toName ($minutes min)';
    }
    return 'Take ${normalizeRouteId(routeId)} from $fromName to $toName ($minutes min)';
  }

  static String _formatWalk(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }
}
