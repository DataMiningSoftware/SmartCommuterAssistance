import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../services/crowd_reports_service.dart';
import '../services/database_service.dart';
import '../services/station_service.dart';
import '../widgets/train_loading_transition.dart';

class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  static const double _maxWalkMetersForEta = 6000;
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  final DatabaseService _databaseService = DatabaseService();
  final StationService _stationService = StationService();
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allStopsRaw = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _allStations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _filteredStations = <Map<String, dynamic>>[];
  Map<String, List<String>> _uniqueStationLines = <String, List<String>>{};
  Map<String, List<String>> _stationCodesByName = <String, List<String>>{};
  Map<String, List<String>> _stationRoutesByName = <String, List<String>>{};
  Map<String, CrowdReport> _latestCrowdByStopId = <String, CrowdReport>{};
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
      final rows =
          await Supabase.instance.client.from('train_stops_kl').select();
      final stations = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      await _databaseService.cacheTrainStops(stations);
      await _syncUniqueStations();
      await _syncRouteConnectionsCache();
      _setStations(stations);
      await _loadLatestCrowdReports();
      return;
    } catch (_) {
      final cachedStations = await _databaseService.getCachedTrainStops();
      if (cachedStations.isNotEmpty) {
        _setStations(cachedStations);
        await _loadLatestCrowdReports();
        _showMessage('Using offline cached stations.');
        return;
      }
      rethrow;
    }
  }

  Future<void> _loadLatestCrowdReports() async {
    final stopIds = <String>{
      for (final stop in _allStopsRaw)
        if (_stationStopId(stop).isNotEmpty && _stationStopId(stop) != 'N/A')
          _stationStopId(stop),
    }.toList();

    if (stopIds.isEmpty) {
      if (!mounted) return;
      setState(() => _latestCrowdByStopId = <String, CrowdReport>{});
      return;
    }

    try {
      final latest =
          await _crowdReportsService.fetchLatestCrowdReportsForStops(stopIds);
      if (!mounted) return;
      setState(() => _latestCrowdByStopId = latest);
    } catch (_) {
      if (!mounted) return;
      setState(() => _latestCrowdByStopId = <String, CrowdReport>{});
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
            ? linesRaw
                .map((line) => line.toString().trim().toUpperCase())
                .where((line) => line.isNotEmpty)
                .toList()
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
        codesByName
            .putIfAbsent(key, () => <String>{})
            .add(stopCode.toUpperCase());
      }
      final routeId = _stationRouteId(stop);
      if (routeId.isNotEmpty && routeId != 'N/A') {
        routesByName
            .putIfAbsent(key, () => <String>{})
            .add(routeId.toUpperCase());
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
      setState(() =>
          _filteredStations = List<Map<String, dynamic>>.from(_allStations));
      if (_userPosition != null) {
        _sortByDistance(_userPosition!);
      }
      return;
    }

    final filtered = _allStations.where((station) {
      final name = _stationName(station).toLowerCase();
      final line = _stationLineLabel(station).toLowerCase();
      final code = _stationCodeLabel(station).toLowerCase();
      return name.contains(query) ||
          line.contains(query) ||
          code.contains(query);
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
        _showMessage(
            'Location permission denied forever. Enable it in settings.');
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
      _showMessage(
          'Location permission denied forever. Enable it in settings.');
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
      final rows = await Supabase.instance.client.from('route_connections').select(
          'from_stop_id,to_stop_id,route_id,travel_time_minutes,connection_type');
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
      final connectionType =
          map['connection_type']?.toString() ?? 'standard_stop';
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

  Future<void> _planRouteToStation(
      Map<String, dynamic> destinationStation) async {
    if (_isPlanningRoute) return;
    setState(() => _isPlanningRoute = true);
    try {
      final destinationStopIds =
          _destinationStopIdsForStation(destinationStation);
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

      final departureTime = await _pickDepartureDateTime();
      if (departureTime == null) return;
      final activeDisruptions = _activeDisruptionsFor(departureTime);
      final disruptionPenaltyByLine =
          _disruptionPenaltyByLine(activeDisruptions);

      // Keep local cache fresh when online. Failures are ignored.
      await _syncRouteConnectionsCache();
      final cachedEdges = await _loadRouteConnections();

      final rpcResult = await _tryBestRpcRoute(
        originStopId: originStopId,
        destinationStopIds: destinationStopIds,
      );

      final _RoutePathResult? plan;
      final String routeSource;
      bool usedDisruptionReroute = false;
      String resolvedDestinationStopId;
      _RoutePathResult? bestLocalPlan;
      String? bestLocalDestination;
      if (cachedEdges.isNotEmpty) {
        for (final destinationStopId in destinationStopIds) {
          final candidate = _findShortestPath(
            originStopId: originStopId,
            destinationStopId: destinationStopId,
            edges: cachedEdges,
            routePenaltyMinutesByLine: disruptionPenaltyByLine,
          );
          if (candidate == null) continue;
          if (bestLocalPlan == null ||
              candidate.totalMinutes < bestLocalPlan.totalMinutes) {
            bestLocalPlan = candidate;
            bestLocalDestination = destinationStopId;
          }
        }
      }

      if (rpcResult != null) {
        final rpcImpact =
            _planDisruptionImpact(rpcResult.plan.edges, activeDisruptions);
        final localImpact = _planDisruptionImpact(
            bestLocalPlan?.edges ?? const <_RouteEdge>[], activeDisruptions);
        if (activeDisruptions.isNotEmpty &&
            bestLocalPlan != null &&
            (localImpact < rpcImpact ||
                (localImpact == rpcImpact &&
                    bestLocalPlan.totalMinutes <
                        rpcResult.plan.totalMinutes))) {
          plan = bestLocalPlan;
          resolvedDestinationStopId =
              bestLocalDestination ?? destinationStopIds.first;
          routeSource = 'Disruption-aware reroute (local)';
          usedDisruptionReroute = true;
        } else {
          plan = rpcResult.plan;
          resolvedDestinationStopId = rpcResult.destinationStopId;
          routeSource = activeDisruptions.isNotEmpty
              ? 'Supabase RPC (service alerts active)'
              : 'Supabase RPC';
        }
      } else {
        if (cachedEdges.isEmpty) {
          _showMessage(
            'No offline route cache available. Go online once to sync route_connections.',
          );
          return;
        }
        plan = bestLocalPlan;
        resolvedDestinationStopId =
            bestLocalDestination ?? destinationStopIds.first;
        usedDisruptionReroute = activeDisruptions.isNotEmpty;
        routeSource = activeDisruptions.isNotEmpty
            ? 'Disruption-aware route graph'
            : 'Supabase route graph cache (RPC unavailable)';
      }
      final resolvedPlan = plan;
      if (resolvedPlan == null) {
        _showMessage(
            'No route found from $originStopId to ${destinationStopIds.first}.');
        return;
      }

      final walkMeters = _distanceMeters(originStation, position);
      final namesByStopId = _stationNamesByStopId();
      final groupedSegments = _buildRouteSegments(resolvedPlan.edges);
      final baseRouteMinutes =
          groupedSegments.fold<int>(0, (sum, segment) => sum + segment.minutes);
      final normalizedWalkMeters = _normalizeWalkMeters(walkMeters);
      if (walkMeters != null && normalizedWalkMeters == null) {
        _showMessage(
          'Current location is far from supported stations. Walk distance is hidden from ETA.',
        );
      }
      final timeline = await _buildRouteTimeline(
        originStopId: originStopId,
        segments: groupedSegments,
        departureTime: departureTime,
      );
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
            walkMeters: normalizedWalkMeters,
            totalMinutes: baseRouteMinutes,
            crowdAdjustedMinutes: timeline.crowdAdjustedMinutes,
            highestCrowdLevel: timeline.highestCrowdLevel,
            departureTime: departureTime,
            arrivalTime: timeline.arrivalTime,
            totalStops: resolvedPlan.edges.length,
            segmentPlans: timeline.segmentPlans,
            namesByStopId: namesByStopId,
            routeSource: routeSource,
            activeDisruptions: activeDisruptions,
            usedDisruptionReroute: usedDisruptionReroute,
          );
        },
      );
    } catch (e) {
      _showMessage('Failed to plan route: $e');
    } finally {
      if (mounted) setState(() => _isPlanningRoute = false);
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
      final response = await Supabase.instance.client.rpc(
        'find_route',
        params: {
          'start_stop': originStopId,
          'end_stop': destinationStopId,
        },
      ).timeout(const Duration(seconds: 5));

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
      final edges =
          await _edgesFromPathArray(pathArray, totalTimeHint: totalTime);
      if (edges.isEmpty) return null;

      final computedTotal =
          edges.fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
      final resolvedTotal = _resolveRouteTotalMinutes(
        rpcTotalMinutes: totalTime,
        computedTotalMinutes: computedTotal,
        edgeCount: edges.length,
      );
      return _RoutePathResult(
        edges: edges,
        totalMinutes: resolvedTotal,
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
    Map<String, int>? routePenaltyMinutesByLine,
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
        final penalty = routePenaltyMinutesByLine == null
            ? 0
            : (routePenaltyMinutesByLine[normalizeRouteId(edge.routeId)] ?? 0);
        final alt = currentDistance + edge.travelMinutes + penalty;
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
    final total =
        orderedEdges.fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
    return _RoutePathResult(edges: orderedEdges, totalMinutes: total);
  }

  List<_ServiceDisruption> _activeDisruptionsFor(DateTime departureTime) {
    final disruptions = <_ServiceDisruption>[];
    final hour = departureTime.hour;
    final isWeekend = departureTime.weekday == DateTime.saturday ||
        departureTime.weekday == DateTime.sunday;

    if (!isWeekend &&
        ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19))) {
      disruptions.add(
        const _ServiceDisruption(
          routeId: 'KJ',
          title: 'Peak crowd control on Kelana Jaya Line',
          detail: 'Expect longer dwell times during rush-hour boarding.',
          penaltyMinutes: 8,
        ),
      );
    }

    if (!isWeekend && hour >= 12 && hour <= 14) {
      disruptions.add(
        const _ServiceDisruption(
          routeId: 'AG',
          title: 'Platform congestion on Ampang Line',
          detail: 'Midday crowding may slow boarding and transfers.',
          penaltyMinutes: 5,
        ),
      );
    }

    if (hour >= 21 || hour <= 5) {
      disruptions.add(
        const _ServiceDisruption(
          routeId: 'MR',
          title: 'Reduced Monorail frequency',
          detail: 'Late-evening headways are wider than usual.',
          penaltyMinutes: 6,
        ),
      );
    }

    return disruptions;
  }

  Map<String, int> _disruptionPenaltyByLine(
    List<_ServiceDisruption> disruptions,
  ) {
    final penalties = <String, int>{};
    for (final disruption in disruptions) {
      penalties[normalizeRouteId(disruption.routeId)] =
          disruption.penaltyMinutes;
    }
    return penalties;
  }

  int _planDisruptionImpact(
    List<_RouteEdge> edges,
    List<_ServiceDisruption> disruptions,
  ) {
    if (edges.isEmpty || disruptions.isEmpty) return 0;
    final usedLines = <String>{
      for (final edge in edges) normalizeRouteId(edge.routeId),
    };
    var impact = 0;
    for (final disruption in disruptions) {
      if (usedLines.contains(normalizeRouteId(disruption.routeId))) {
        impact += disruption.penaltyMinutes;
      }
    }
    return impact;
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

  Future<DateTime?> _pickDepartureDateTime() async {
    final mode = await showModalBottomSheet<String>(
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
                  'When do you want to depart?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Choose now or pick a specific date and time.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop('now'),
                    icon: const Icon(Icons.access_time_rounded),
                    label: const Text('Leave Now'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('pick'),
                    icon: const Icon(Icons.event_rounded),
                    label: const Text('Choose Date & Time'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (mode == null) return null;
    if (mode == 'now') {
      return DateTime.now();
    }
    if (!mounted) return null;

    final now = DateTime.now();
    final initial = now.add(const Duration(minutes: 5));
    final firstDay = DateTime(now.year, now.month, now.day);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDay,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (pickedDate == null) return null;

    if (!mounted) return null;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null) return null;

    final selected = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (selected.isBefore(now)) {
      _showMessage('Selected time is in the past. Using current time instead.');
      return now;
    }
    return selected;
  }

  Future<_RouteTimeline> _buildRouteTimeline({
    required String originStopId,
    required List<_RouteSegment> segments,
    required DateTime departureTime,
  }) async {
    if (segments.isEmpty) {
      return _RouteTimeline(
        segmentPlans: const <_RouteSegmentPlan>[],
        crowdAdjustedMinutes: 0,
        highestCrowdLevel: 0,
        arrivalTime: departureTime,
      );
    }

    final stopIds = <String>{originStopId};
    final probeTimes = <DateTime>[departureTime];
    var elapsedBaseMinutes = 0;
    for (final segment in segments) {
      stopIds.add(segment.fromStopId.toUpperCase());
      stopIds.add(segment.toStopId.toUpperCase());
      probeTimes.add(departureTime.add(Duration(minutes: elapsedBaseMinutes)));
      elapsedBaseMinutes += segment.minutes;
    }

    final forecastGrid = await _crowdReportsService.fetchForecastGrid(
      stopIds: stopIds.toList(),
      times: probeTimes,
    );

    final segmentPlans = <_RouteSegmentPlan>[];
    var cursor = departureTime;
    var highestLevel = 0;
    var totalMinutes = 0;
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final forecast = _forecastForSegmentAtTime(
        segment: segment,
        time: cursor,
        grid: forecastGrid,
      );
      final level = forecast?.occupancyLevel.clamp(0, 5) ?? 2;
      highestLevel = math.max(highestLevel, level);

      final etaMultiplier =
          forecast?.etaMultiplier ?? _fallbackEtaMultiplier(level);
      final baseTravel = segment.minutes;
      final movementMinutes = math.max(
        baseTravel,
        (baseTravel * etaMultiplier).round(),
      );
      final includeWait = index == 0 ||
          segment.connectionType.toLowerCase().contains('transfer');
      final waitMinutes = includeWait
          ? (forecast?.expectedWaitMinutes ?? _fallbackWaitMinutes(level))
          : 0;
      final adjustedMinutes = movementMinutes + waitMinutes;

      final departAt = cursor;
      final arriveAt = cursor.add(Duration(minutes: adjustedMinutes));
      segmentPlans.add(
        _RouteSegmentPlan(
          segment: segment,
          departAt: departAt,
          arriveAt: arriveAt,
          occupancyLevel: level,
          sourceType: forecast?.sourceType ?? 'fallback',
          adjustedMinutes: adjustedMinutes,
          waitMinutes: waitMinutes,
        ),
      );

      cursor = arriveAt;
      totalMinutes += adjustedMinutes;
    }

    return _RouteTimeline(
      segmentPlans: segmentPlans,
      crowdAdjustedMinutes: totalMinutes,
      highestCrowdLevel: highestLevel,
      arrivalTime: cursor,
    );
  }

  StopCrowdForecast? _forecastForSegmentAtTime({
    required _RouteSegment segment,
    required DateTime time,
    required Map<String, StopCrowdForecast> grid,
  }) {
    final fromKey = CrowdReportsService.forecastKeyForTime(
      stopId: segment.fromStopId,
      time: time,
    );
    final toKey = CrowdReportsService.forecastKeyForTime(
      stopId: segment.toStopId,
      time: time,
    );
    return grid[fromKey] ?? grid[toKey];
  }

  static int _fallbackWaitMinutes(int level) {
    switch (level) {
      case 1:
        return 2;
      case 2:
        return 4;
      case 3:
        return 6;
      case 4:
        return 8;
      case 5:
        return 10;
      default:
        return 4;
    }
  }

  static double _fallbackEtaMultiplier(int level) {
    switch (level) {
      case 1:
        return 1.00;
      case 2:
        return 1.05;
      case 3:
        return 1.12;
      case 4:
        return 1.22;
      case 5:
        return 1.35;
      default:
        return 1.10;
    }
  }

  static int _resolveRouteTotalMinutes({
    required int? rpcTotalMinutes,
    required int computedTotalMinutes,
    required int edgeCount,
  }) {
    if (computedTotalMinutes <= 0) {
      return rpcTotalMinutes ?? 0;
    }
    if (rpcTotalMinutes == null || rpcTotalMinutes <= 0) {
      return computedTotalMinutes;
    }

    final maxReasonableFromGraph = (computedTotalMinutes * 3).clamp(30, 720);
    final maxReasonableFromEdges = (edgeCount * 12).clamp(24, 720);
    final maxReasonable =
        math.max(maxReasonableFromGraph, maxReasonableFromEdges);
    if (rpcTotalMinutes > maxReasonable) {
      return computedTotalMinutes;
    }
    return rpcTotalMinutes;
  }

  static double? _normalizeWalkMeters(double? meters) {
    if (meters == null) return null;
    if (meters.isNaN || meters.isInfinite || meters < 0) return null;
    if (meters > _maxWalkMetersForEta) return null;
    return meters;
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
        title: const Text('Station Atlas'),
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
      body: FutureBuilder<void>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          final isWaiting = snapshot.connectionState == ConnectionState.waiting;
          return TrainLoadingTransition(
            isLoading: isWaiting,
            loadingLabel: 'Loading train stations...',
            arrivalLabel: 'Stations ready',
            child: _buildStationsContent(snapshot),
          );
        },
      ),
    );
  }

  Widget _buildStationsContent(AsyncSnapshot<void> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox.shrink();
    }

    return Column(
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
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _RouteLegend(),
        ),
        Expanded(
          child: snapshot.hasError
              ? _buildStationsErrorState(snapshot.error.toString())
              : _buildLoadedBody(),
        ),
      ],
    );
  }

  Widget _buildStationsErrorState(String errorText) {
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
              errorText,
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
        final crowdUi = _stationCrowdLevelUi(station);
        return _StationCard(
          name: _stationName(station),
          codes: _stationCodeList(station),
          routeIds: _stationRouteIdList(station),
          crowdLevelUi: crowdUi,
          distanceMeters: _userPosition == null
              ? null
              : _distanceMeters(station, _userPosition!),
          onTap: _isPlanningRoute ? () {} : () => _planRouteToStation(station),
          onReportTap: () => _reportCrowdLevel(station),
        );
      },
    );
  }

  static String _pickValue(Map<String, dynamic> row, List<String> keys,
      {String fallback = 'N/A'}) {
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
        const <String>[
          'stop_id',
          'station_code',
          'code',
          'stop_code',
          'route_id',
          'id'
        ],
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

  List<String> _stationCodeList(Map<String, dynamic> row) {
    final codeLabel = _stationCodeLabel(row);
    return codeLabel
        .split('/')
        .map((part) => part.trim().toUpperCase())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  List<String> _stationRouteIdList(Map<String, dynamic> row) {
    final nameKey = _stationName(row).toUpperCase();
    final candidates = <String>[
      ...?_uniqueStationLines[nameKey],
      ...?_stationRoutesByName[nameKey],
    ];

    final fromCodes = _stationCodeList(row).map((code) {
      final match = RegExp(r'^[A-Za-z]+').firstMatch(code);
      return normalizeRouteId((match?.group(0) ?? 'N/A').toUpperCase());
    }).where((id) => id != 'N/A');
    candidates.addAll(fromCodes);

    final output = <String>[];
    final seen = <String>{};
    for (final id in candidates) {
      final normalized = normalizeRouteId(id);
      if (normalized == 'N/A') continue;
      if (seen.add(normalized)) {
        output.add(normalized);
      }
    }
    if (output.isEmpty) {
      output.add(normalizeRouteId(_stationRouteId(row)));
    }
    return output;
  }

  _CrowdLevelUi? _stationCrowdLevelUi(Map<String, dynamic> station) {
    final codes = _stationCodeList(station);
    final reports = codes
        .map((code) => _latestCrowdByStopId[code])
        .whereType<CrowdReport>()
        .toList();
    if (reports.isEmpty) return null;

    reports.sort((a, b) {
      if (a.occupancyLevel != b.occupancyLevel) {
        return b.occupancyLevel.compareTo(a.occupancyLevel);
      }
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });

    final level = reports.first.occupancyLevel;
    final crowd = crowdLevelStyleFromIndex(level);
    if (crowd.label == 'Unknown') {
      return const _CrowdLevelUi(
        label: 'Unknown crowd level',
        color: Color(0xFF64748B),
      );
    }
    return _CrowdLevelUi(label: crowd.label, color: crowd.color);
  }

  Future<void> _reportCrowdLevel(Map<String, dynamic> station) async {
    final codes = _stationCodeList(station);
    if (codes.isEmpty) {
      _showMessage('No station code found for reporting.');
      return;
    }

    var selectedCode = codes.first;
    var selectedLevel = 3;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Crowd Level',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stationName(station),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedCode),
                      initialValue: selectedCode,
                      decoration: const InputDecoration(
                        labelText: 'Station Code',
                        border: OutlineInputBorder(),
                      ),
                      items: codes
                          .map(
                            (code) => DropdownMenuItem<String>(
                              value: code,
                              child: Text(code),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selectedCode = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('How crowded is it now?'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List<Widget>.generate(5, (offset) {
                        final level = offset + 1;
                        final ui = _crowdUiByLevel(level);
                        return ChoiceChip(
                          label: Text('L$level ${ui.label}'),
                          selected: selectedLevel == level,
                          selectedColor: ui.color.withValues(alpha: 0.18),
                          onSelected: (_) =>
                              setModalState(() => selectedLevel = level),
                        );
                      }),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Submit Report'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (submitted != true) return;

    try {
      await _crowdReportsService.insertUserCrowdReport(
        stopId: selectedCode,
        occupancyLevel: selectedLevel,
      );
      await _loadLatestCrowdReports();
      _showMessage('Thanks. Crowd report submitted for $selectedCode.');
    } catch (e) {
      _showMessage('Failed to submit report: $e');
    }
  }

  static _CrowdLevelUi _crowdUiByLevel(int level) {
    final crowd = crowdLevelStyleFromIndex(level);
    if (crowd.label == 'Unknown') {
      return const _CrowdLevelUi(label: 'Unknown', color: Color(0xFF64748B));
    }
    return _CrowdLevelUi(label: crowd.label, color: crowd.color);
  }
}

class _CrowdLevelUi {
  final String label;
  final Color color;

  const _CrowdLevelUi({
    required this.label,
    required this.color,
  });
}

class _StationCard extends StatelessWidget {
  final String name;
  final List<String> codes;
  final List<String> routeIds;
  final _CrowdLevelUi? crowdLevelUi;
  final double? distanceMeters;
  final VoidCallback onTap;
  final VoidCallback onReportTap;

  const _StationCard({
    required this.name,
    required this.codes,
    required this.routeIds,
    required this.crowdLevelUi,
    required this.distanceMeters,
    required this.onTap,
    required this.onReportTap,
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
          boxShadow: appCardShadows(context),
        ),
        child: Row(
          children: [
            _RouteBadge(routeIds: routeIds),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  if (crowdLevelUi != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: crowdLevelUi!.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            crowdLevelUi!.label,
                            style: TextStyle(
                              color: crowdLevelUi!.color,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: codes
                      .map((code) => _StationCodeChip(code: code))
                      .toList(),
                ),
                if (distanceMeters != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    _formatDistance(distanceMeters!),
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
                const SizedBox(height: 2),
                TextButton.icon(
                  onPressed: onReportTap,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.campaign_rounded, size: 14),
                  label: const Text(
                    'Report',
                    style: TextStyle(fontSize: 11),
                  ),
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

class _RouteBadge extends StatelessWidget {
  final List<String> routeIds;

  const _RouteBadge({required this.routeIds});

  @override
  Widget build(BuildContext context) {
    final ids = routeIds.where((id) => id.isNotEmpty && id != 'N/A').toList();
    if (ids.length <= 1) {
      final route = ids.isEmpty ? 'N/A' : ids.first;
      return CircleAvatar(
        radius: 22,
        backgroundColor: getRouteColor(route),
        child: Text(
          normalizeRouteId(route),
          style: TextStyle(
            color: getRouteOnColor(route),
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
    }

    final colors = ids.map(getRouteColor).toList();
    return SizedBox(
      width: 44,
      height: 44,
      child: CustomPaint(
        painter: _RouteSegmentsPainter(colors: colors),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteSegmentsPainter extends CustomPainter {
  final List<Color> colors;

  const _RouteSegmentsPainter({
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    final segmentAngle = (2 * math.pi) / colors.length;
    var start = -math.pi / 2;

    for (final color in colors) {
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = color;
      canvas.drawArc(arcRect, start, segmentAngle, true, paint);
      start += segmentAngle;
    }

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFDDE6F5);
    canvas.drawCircle(center, radius - 0.6, border);
  }

  @override
  bool shouldRepaint(covariant _RouteSegmentsPainter oldDelegate) {
    if (oldDelegate.colors.length != colors.length) return true;
    for (var i = 0; i < colors.length; i++) {
      if (oldDelegate.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

class _RouteLegend extends StatelessWidget {
  const _RouteLegend();

  static const List<_LegendEntry> _entries = <_LegendEntry>[
    _LegendEntry(label: 'KJ', routeId: 'KJ'),
    _LegendEntry(label: 'MRT / KG', routeId: 'MRT'),
    _LegendEntry(label: 'PYL / PY', routeId: 'PYL'),
    _LegendEntry(label: 'AG', routeId: 'AG'),
    _LegendEntry(label: 'PH / SP', routeId: 'PH'),
    _LegendEntry(label: 'MR', routeId: 'MR'),
    _LegendEntry(label: 'BRT', routeId: 'BRT'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Line Colors',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children:
                _entries.map((entry) => _LegendChip(entry: entry)).toList(),
          ),
        ],
      ),
    );
  }
}

class _LegendEntry {
  final String label;
  final String routeId;

  const _LegendEntry({
    required this.label,
    required this.routeId,
  });
}

class _LegendChip extends StatelessWidget {
  final _LegendEntry entry;

  const _LegendChip({
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDE6F5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: getRouteColor(entry.routeId),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            entry.label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StationCodeChip extends StatelessWidget {
  final String code;

  const _StationCodeChip({
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final routePrefixMatch = RegExp(r'^[A-Za-z]+').firstMatch(code);
    final routeId =
        normalizeRouteId((routePrefixMatch?.group(0) ?? 'N/A').toUpperCase());
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: getRouteColor(routeId),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: getRouteOnColor(routeId),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
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

class _RouteSegmentPlan {
  final _RouteSegment segment;
  final DateTime departAt;
  final DateTime arriveAt;
  final int occupancyLevel;
  final String sourceType;
  final int adjustedMinutes;
  final int waitMinutes;

  const _RouteSegmentPlan({
    required this.segment,
    required this.departAt,
    required this.arriveAt,
    required this.occupancyLevel,
    required this.sourceType,
    required this.adjustedMinutes,
    required this.waitMinutes,
  });
}

class _RouteTimeline {
  final List<_RouteSegmentPlan> segmentPlans;
  final int crowdAdjustedMinutes;
  final int highestCrowdLevel;
  final DateTime arrivalTime;

  const _RouteTimeline({
    required this.segmentPlans,
    required this.crowdAdjustedMinutes,
    required this.highestCrowdLevel,
    required this.arrivalTime,
  });
}

class _RoutePlanSheet extends StatelessWidget {
  final String originName;
  final String originStopId;
  final String destinationName;
  final String destinationStopId;
  final double? walkMeters;
  final int totalMinutes;
  final int crowdAdjustedMinutes;
  final int highestCrowdLevel;
  final DateTime departureTime;
  final DateTime arrivalTime;
  final int totalStops;
  final List<_RouteSegmentPlan> segmentPlans;
  final Map<String, String> namesByStopId;
  final String routeSource;
  final List<_ServiceDisruption> activeDisruptions;
  final bool usedDisruptionReroute;

  const _RoutePlanSheet({
    required this.originName,
    required this.originStopId,
    required this.destinationName,
    required this.destinationStopId,
    required this.walkMeters,
    required this.totalMinutes,
    required this.crowdAdjustedMinutes,
    required this.highestCrowdLevel,
    required this.departureTime,
    required this.arrivalTime,
    required this.totalStops,
    required this.segmentPlans,
    required this.namesByStopId,
    required this.routeSource,
    required this.activeDisruptions,
    required this.usedDisruptionReroute,
  });

  @override
  Widget build(BuildContext context) {
    final estimatedWalk =
        walkMeters == null ? null : (walkMeters! / 75).round();
    final baseEta =
        estimatedWalk == null ? totalMinutes : totalMinutes + estimatedWalk;
    final crowdEta = estimatedWalk == null
        ? crowdAdjustedMinutes
        : crowdAdjustedMinutes + estimatedWalk;
    final tripCrowdUi = _crowdUiByLevel(highestCrowdLevel);
    final overallConfidence = _overallForecastConfidence(segmentPlans);

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
              'Depart: ${_formatDateTime(departureTime)}',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            Text(
              'Arrive: ${_formatDateTime(arrivalTime)}',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: 'Base ETA ~ ${_formatDuration(baseEta)}'),
                _InfoChip(label: 'Crowd ETA ~ ${_formatDuration(crowdEta)}'),
                _InfoChip(
                  label:
                      'Forecast confidence ${_formatPercent(overallConfidence)}',
                ),
                _InfoChip(
                  label: 'Trip Crowd: ${tripCrowdUi.label}',
                  textColor: tripCrowdUi.color,
                  borderColor: tripCrowdUi.color.withValues(alpha: 0.45),
                ),
                _InfoChip(label: '$totalStops stops'),
                if (usedDisruptionReroute)
                  const _InfoChip(
                    label: 'Rerouted around disruption',
                    textColor: Color(0xFFD92D20),
                    borderColor: Color(0xFFFDB0AC),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Source: $routeSource',
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            if (activeDisruptions.isNotEmpty)
              Text(
                'Service alerts: ${_disruptionSummary(activeDisruptions)}',
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (walkMeters != null)
              Text(
                'Walk to origin: ${_formatWalk(walkMeters!)}',
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            const SizedBox(height: 12),
            if (segmentPlans.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'No route segments available.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: segmentPlans.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final plan = segmentPlans[index];
                    final segment = plan.segment;
                    final fromName =
                        namesByStopId[segment.fromStopId] ?? segment.fromStopId;
                    final toName =
                        namesByStopId[segment.toStopId] ?? segment.toStopId;
                    final crowdUi = _crowdUiByLevel(plan.occupancyLevel);
                    final confidence = _segmentForecastConfidence(plan);
                    final disruptionNote =
                        _disruptionNoteFor(segment, activeDisruptions);
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE3EAF7)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _segmentText(
                                    routeId: segment.routeId,
                                    connectionType: segment.connectionType,
                                    fromName: fromName,
                                    toName: toName,
                                    baseMinutes: segment.minutes,
                                    adjustedMinutes: plan.adjustedMinutes,
                                  ),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatTime(plan.departAt)} to ${_formatTime(plan.arriveAt)} - ${crowdUi.label}',
                                  style: TextStyle(
                                    color: crowdUi.color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Forecast confidence: ${_formatPercent(confidence)}',
                                  style: const TextStyle(
                                    color: Color(0xFF475467),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _forecastReason(plan),
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Coach/platform tip: ${_boardingTipFor(index, segmentPlans, namesByStopId)}',
                                  style: const TextStyle(
                                    color: Color(0xFF344054),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (disruptionNote != null)
                                  Text(
                                    'Service alert: $disruptionNote',
                                    style: const TextStyle(
                                      color: Color(0xFFD92D20),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (plan.waitMinutes > 0)
                                  Text(
                                    'Includes approx. ${plan.waitMinutes} min waiting time',
                                    style: const TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(plan.adjustedMinutes),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF344054),
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

  static _RouteCrowdUi _crowdUiByLevel(int level) {
    final crowd = crowdLevelStyleFromIndex(level);
    if (crowd.label == 'Unknown') {
      return const _RouteCrowdUi(label: 'Unknown', color: Color(0xFF64748B));
    }
    return _RouteCrowdUi(label: crowd.label, color: crowd.color);
  }

  static String _segmentText({
    required String routeId,
    required String connectionType,
    required String fromName,
    required String toName,
    required int baseMinutes,
    required int adjustedMinutes,
  }) {
    if (connectionType.toLowerCase().contains('transfer')) {
      return 'Transfer from $fromName to $toName (${_formatDuration(baseMinutes)} base, ~${_formatDuration(adjustedMinutes)} forecast)';
    }
    return 'Take ${normalizeRouteId(routeId)} from $fromName to $toName (${_formatDuration(baseMinutes)} base, ~${_formatDuration(adjustedMinutes)} forecast)';
  }

  static double _overallForecastConfidence(List<_RouteSegmentPlan> plans) {
    if (plans.isEmpty) return 0.0;
    final total = plans.fold<double>(
      0,
      (sum, plan) => sum + _segmentForecastConfidence(plan),
    );
    return total / plans.length;
  }

  static double _segmentForecastConfidence(_RouteSegmentPlan plan) {
    final source = plan.sourceType.toLowerCase();
    if (CrowdReportsService.isClosedHoursSource(source)) {
      return 0.99;
    }
    double base;
    if (source.contains('user')) {
      base = 0.92;
    } else if (source.contains('trend') || source.contains('forecast')) {
      base = 0.84;
    } else if (source.contains('simulated')) {
      base = 0.66;
    } else {
      base = 0.58;
    }
    if (plan.waitMinutes > 0) {
      base -= 0.03;
    }
    if (plan.occupancyLevel >= 3) {
      base -= 0.04;
    }
    return base.clamp(0.50, 0.97);
  }

  static String _forecastReason(_RouteSegmentPlan plan) {
    final source = plan.sourceType.toLowerCase();
    if (CrowdReportsService.isClosedHoursSource(source)) {
      return 'Train service is currently outside operating hours.';
    }
    final reasons = <String>[];
    if (source.contains('user')) {
      reasons.add('recent rider reports');
    } else if (source.contains('trend') || source.contains('forecast')) {
      reasons.add('hourly ridership forecast');
    } else if (source.contains('simulated')) {
      reasons.add('10-minute simulation fallback');
    } else {
      reasons.add('offline fallback estimate');
    }
    if (plan.waitMinutes > 0) {
      reasons.add('transfer wait included');
    }
    if (plan.occupancyLevel >= 3) {
      reasons.add('peak-load conditions likely');
    } else if (plan.occupancyLevel == 2) {
      reasons.add('standing demand likely');
    }
    return reasons.join(' • ');
  }

  static String _boardingTipFor(
    int index,
    List<_RouteSegmentPlan> plans,
    Map<String, String> namesByStopId,
  ) {
    final plan = plans[index];
    final segment = plan.segment;
    final toName = namesByStopId[segment.toStopId] ?? segment.toStopId;
    if (segment.connectionType.toLowerCase().contains('transfer')) {
      return 'Follow interchange signs promptly at $toName.';
    }
    final nextPlan = index + 1 < plans.length ? plans[index + 1] : null;
    if (nextPlan != null &&
        nextPlan.segment.connectionType.toLowerCase().contains('transfer')) {
      return 'Board middle-rear coach for a faster transfer at $toName.';
    }
    if (index == plans.length - 1) {
      return 'Board near the doors for a quicker exit at $toName.';
    }
    return 'Follow platform signs toward $toName-bound service.';
  }

  static String? _disruptionNoteFor(
    _RouteSegment segment,
    List<_ServiceDisruption> disruptions,
  ) {
    final routeId = normalizeRouteId(segment.routeId);
    for (final disruption in disruptions) {
      if (normalizeRouteId(disruption.routeId) == routeId) {
        return disruption.title;
      }
    }
    return null;
  }

  static String _disruptionSummary(List<_ServiceDisruption> disruptions) {
    return disruptions
        .map((disruption) =>
            '${normalizeRouteId(disruption.routeId)} ${disruption.title}')
        .join(' • ');
  }

  static String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month ${_formatTime(local)}';
  }

  static String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _formatWalk(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }

  static String _formatDuration(int totalMinutes) {
    final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
    final hours = safeMinutes ~/ 60;
    final minutes = safeMinutes % 60;
    if (hours <= 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  static String _formatPercent(double value) {
    return '${(value * 100).round()}%';
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color? textColor;
  final Color? borderColor;

  const _InfoChip({
    required this.label,
    this.textColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor ?? const Color(0xFFDDE6F5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor ?? const Color(0xFF344054),
        ),
      ),
    );
  }
}

class _RouteCrowdUi {
  final String label;
  final Color color;

  const _RouteCrowdUi({
    required this.label,
    required this.color,
  });
}

class _ServiceDisruption {
  final String routeId;
  final String title;
  final String detail;
  final int penaltyMinutes;

  const _ServiceDisruption({
    required this.routeId,
    required this.title,
    required this.detail,
    required this.penaltyMinutes,
  });
}
