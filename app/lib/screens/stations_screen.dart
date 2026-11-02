import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/crowd_reports_service.dart';
import '../services/database_service.dart';
import '../services/fare_service.dart';
import '../services/station_service.dart';
import '../services/transit_network_service.dart';
import '../widgets/scheduled_arrivals_panel.dart';

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
  final TransitNetworkService _transitNetworkService = TransitNetworkService();
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

  Future<void> _loadStations({bool forceRefresh = false}) async {
    final network = await _transitNetworkService.loadNetwork(
      forceRefresh: forceRefresh,
    );
    final stations = network.stopsById.values
        .map((stop) => <String, dynamic>{
              'stop_id': stop.stopId,
              'stop_name': stop.stopName,
              'stop_lat': stop.latitude,
              'stop_lon': stop.longitude,
              'route_id': stop.routeId,
            })
        .toList();
    _routeEdgesCache = network.connections
        .map(
          (edge) => _RouteEdge(
            fromStopId: edge.fromStopId,
            toStopId: edge.toStopId,
            routeId: edge.routeId,
            travelMinutes: edge.travelMinutes,
            connectionType: edge.connectionType,
          ),
        )
        .toList();
    await _syncUniqueStations();
    _setStations(stations);
    await _loadLatestCrowdReports();
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
      _stationsFuture = _loadStations(forceRefresh: true);
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
    final l10n = AppLocalizations.of(context);
    setState(() => _isFindingNearest = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage(l10n.stationsLocationServicesDisabled);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showMessage(l10n.stationsLocationPermissionDenied);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage(l10n.stationsLocationPermissionDeniedForever);
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
        _showMessage(l10n.stationsNoValidCoordinates);
        return;
      }
      final nearestName = _stationName(nearest);
      final nearestDistance = _distanceMeters(nearest, position)!;
      _showMessage(
        l10n.stationsNearestMessage(
          nearestName,
          _StationCard._formatDistance(nearestDistance),
          position.latitude.toStringAsFixed(5),
          position.longitude.toStringAsFixed(5),
        ),
      );
    } catch (e) {
      _showMessage(l10n.stationsLocationFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _isFindingNearest = false);
    }
  }

  Future<Position?> _ensureCurrentPosition() async {
    if (_userPosition != null) return _userPosition;

    final l10n = AppLocalizations.of(context);
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showMessage(l10n.stationsLocationServicesDisabled);
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showMessage(l10n.stationsLocationPermissionDenied);
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      _showMessage(l10n.stationsLocationPermissionDeniedForever);
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
      final synced = _mapRowsToEdges(maps);
      final merged = <String, _RouteEdge>{};
      for (final edge in synced) {
        merged[_routeEdgeKey(edge)] = edge;
      }
      for (final edge in _routeEdgesCache ?? const <_RouteEdge>[]) {
        merged.putIfAbsent(_routeEdgeKey(edge), () => edge);
      }
      _routeEdgesCache = merged.values.toList();
    } catch (_) {
      // Keep silent. Offline fallback reads existing local cache.
    }
  }

  String _routeEdgeKey(_RouteEdge edge) {
    return '${edge.fromStopId.trim().toUpperCase()}|'
        '${edge.toStopId.trim().toUpperCase()}|'
        '${normalizeRouteId(edge.routeId)}';
  }

  Future<List<_RouteEdge>> _mergeWithBundledNetwork(
    List<_RouteEdge> edges,
  ) async {
    final merged = <String, _RouteEdge>{};
    for (final edge in edges) {
      merged[_routeEdgeKey(edge)] = edge;
    }
    try {
      final network = await _transitNetworkService.loadNetwork();
      for (final connection in network.connections) {
        final edge = _RouteEdge(
          fromStopId: connection.fromStopId,
          toStopId: connection.toStopId,
          routeId: connection.routeId,
          travelMinutes: connection.travelMinutes,
          connectionType: connection.connectionType,
        );
        merged.putIfAbsent(_routeEdgeKey(edge), () => edge);
      }
    } catch (_) {
      return edges;
    }
    return merged.values.toList();
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
    final l10n = AppLocalizations.of(context);
    setState(() => _isPlanningRoute = true);
    try {
      final destinationStopIds =
          _destinationStopIdsForStation(destinationStation);
      if (destinationStopIds.isEmpty) {
        _showMessage(l10n.stationsMissingStopId);
        return;
      }

      final position = await _ensureCurrentPosition();
      if (position == null) return;

      final originStation = _nearestStationFromPosition(position);
      if (originStation == null) {
        _showMessage(l10n.stationsNearestOriginFailed);
        return;
      }

      final originStopId = _stationStopId(originStation);
      if (destinationStopIds.contains(originStopId)) {
        _showMessage(l10n.stationsAlreadyAtStation);
        return;
      }

      final departureTime = await _pickDepartureDateTime();
      if (departureTime == null) return;
      final activeDisruptions = _activeDisruptionsFor(departureTime);
      final disruptionPenaltyByLine =
          _disruptionPenaltyByLine(activeDisruptions);

      // Keep local cache fresh when online. Failures are ignored.
      await _syncRouteConnectionsCache();
      final cachedEdges = await _mergeWithBundledNetwork(
        await _loadRouteConnections(),
      );

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
        if (bestLocalPlan != null &&
            (localImpact < rpcImpact ||
                (localImpact == rpcImpact &&
                    bestLocalPlan.totalMinutes <
                        rpcResult.plan.totalMinutes))) {
          plan = bestLocalPlan;
          resolvedDestinationStopId =
              bestLocalDestination ?? destinationStopIds.first;
          routeSource = l10n.stationsRouteSourceDisruptionLocal;
          usedDisruptionReroute = true;
        } else {
          plan = rpcResult.plan;
          resolvedDestinationStopId = rpcResult.destinationStopId;
          routeSource = activeDisruptions.isNotEmpty
              ? l10n.stationsRouteSourceRpcAlerts
              : l10n.stationsRouteSourceRpc;
        }
      } else {
        if (cachedEdges.isEmpty) {
          _showMessage(l10n.stationsNoOfflineRouteCache);
          return;
        }
        plan = bestLocalPlan;
        resolvedDestinationStopId =
            bestLocalDestination ?? destinationStopIds.first;
        usedDisruptionReroute = activeDisruptions.isNotEmpty;
        routeSource = activeDisruptions.isNotEmpty
            ? l10n.stationsRouteSourceDisruptionGraph
            : l10n.stationsRouteSourceGraphCache;
      }
      final resolvedPlan = plan;
      if (resolvedPlan == null) {
        _showMessage(
            l10n.stationsNoRouteFoundFromTo(originStopId, destinationStopIds.first));
        return;
      }

      final walkMeters = _distanceMeters(originStation, position);
      final namesByStopId = _stationNamesByStopId();
      final groupedSegments = _buildRouteSegments(resolvedPlan.edges);
      final fareBreakdown = _fareBreakdownForSegments(
        groupedSegments,
        _stopCoordinatesById(),
      );
      final baseRouteMinutes =
          groupedSegments.fold<int>(0, (sum, segment) => sum + segment.minutes);
      final normalizedWalkMeters = _normalizeWalkMeters(walkMeters);
      if (walkMeters != null && normalizedWalkMeters == null) {
        _showMessage(l10n.stationsWalkHiddenFarFromStations);
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
            fare: fareBreakdown,
            routeSource: routeSource,
            activeDisruptions: activeDisruptions,
            usedDisruptionReroute: usedDisruptionReroute,
          );
        },
      );
    } catch (e) {
      _showMessage(l10n.stationsPlanRouteFailed(e.toString()));
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
    final l10n = AppLocalizations.of(context);
    final disruptions = <_ServiceDisruption>[];
    final hour = departureTime.hour;
    final isWeekend = departureTime.weekday == DateTime.saturday ||
        departureTime.weekday == DateTime.sunday;

    if (!isWeekend &&
        ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19))) {
      disruptions.add(
        _ServiceDisruption(
          routeId: 'KJ',
          title: l10n.stationsDisruptionKjTitle,
          detail: l10n.stationsDisruptionKjDetail,
          penaltyMinutes: 8,
        ),
      );
    }

    if (!isWeekend && hour >= 12 && hour <= 14) {
      disruptions.add(
        _ServiceDisruption(
          routeId: 'AG',
          title: l10n.stationsDisruptionAgTitle,
          detail: l10n.stationsDisruptionAgDetail,
          penaltyMinutes: 5,
        ),
      );
    }

    if (hour >= 21 || hour <= 5) {
      disruptions.add(
        _ServiceDisruption(
          routeId: 'MR',
          title: l10n.stationsDisruptionMrTitle,
          detail: l10n.stationsDisruptionMrDetail,
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
    final l10n = AppLocalizations.of(context);
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
                  l10n.stationsWhenDepartTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.stationsChooseDepartSubtitle,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop('now'),
                    icon: const Icon(Icons.access_time_rounded),
                    label: Text(l10n.stationsLeaveNowButton),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('pick'),
                    icon: const Icon(Icons.event_rounded),
                    label: Text(l10n.stationsChooseDateTimeButton),
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
      _showMessage(l10n.stationsSelectedTimeInPast);
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

  Map<String, ({double lat, double lon})> _stopCoordinatesById() {
    final coordinates = <String, ({double lat, double lon})>{};
    for (final row in _allStopsRaw) {
      final id = _stationStopId(row);
      if (id.isEmpty || id == 'N/A') continue;
      final lat = _toDouble(row['stop_lat']);
      final lon = _toDouble(row['stop_lon']);
      if (lat == null || lon == null) continue;
      coordinates[id] = (lat: lat, lon: lon);
    }
    return coordinates;
  }

  FareBreakdown _fareBreakdownForSegments(
    List<_RouteSegment> segments,
    Map<String, ({double lat, double lon})> coordinates,
  ) {
    final inputs = <FareSegmentInput>[];
    for (final segment in segments) {
      if (segment.connectionType.toLowerCase().contains('transfer')) continue;
      final from = coordinates[segment.fromStopId];
      final to = coordinates[segment.toStopId];
      var distanceKm = 0.0;
      if (from != null && to != null) {
        distanceKm = Geolocator.distanceBetween(
              from.lat,
              from.lon,
              to.lat,
              to.lon,
            ) /
            1000;
      }
      inputs.add(
        FareSegmentInput(
          line: segment.routeId,
          fromStopId: segment.fromStopId,
          toStopId: segment.toStopId,
          distanceKm: distanceKm,
        ),
      );
    }
    return FareService.forSegments(inputs);
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stationsTitle),
        actions: [
          IconButton(
            onPressed: _isFindingNearest ? null : _findNearestStations,
            icon: const Icon(Icons.my_location_rounded),
            tooltip: l10n.stationsNearestTooltip,
          ),

          if (_isPlanningRoute)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Icon(Icons.route_rounded, size: 16),
              ),
            ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          return _buildStationsContent(snapshot);
        },
      ),
    );
  }

  Widget _buildStationsContent(AsyncSnapshot<void> snapshot) {
    final l10n = AppLocalizations.of(context);
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const _StationsSkeleton();
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: l10n.stationsSearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        FocusScope.of(context).unfocus();
                      },
                      icon: const Icon(Icons.close_rounded),
                      tooltip: l10n.stationsClearSearch,
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
    final l10n = AppLocalizations.of(context);
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
            Text(
              l10n.stationsLoadFailed,
              style: const TextStyle(fontWeight: FontWeight.w700),
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
              child: Text(l10n.tryAgain),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildLoadedBody() {
    final l10n = AppLocalizations.of(context);
    if (_allStations.isEmpty) {
      return Center(
        child: Text(l10n.stationsEmptyTable),
      );
    }

    if (_filteredStations.isEmpty) {
      return Center(child: Text(l10n.stationsNoMatch));
    }

    return ClipRect(
      child: RefreshIndicator(
        onRefresh: () => _loadStations(forceRefresh: true),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
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
              onTap:
                  _isPlanningRoute ? () {} : () => _planRouteToStation(station),
              onArrivalsTap: () => _showScheduledArrivals(station),
              onReportTap: () => _reportCrowdLevel(station),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showScheduledArrivals(Map<String, dynamic> station) async {
    final stopIds = _destinationStopIdsForStation(station);
    final stopId = stopIds.isEmpty ? _stationStopId(station) : stopIds.first;
    if (stopId.isEmpty || stopId == 'N/A') {
      _showMessage(AppLocalizations.of(context).stationsMissingGtfsStopId);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: ScheduledArrivalsPanel(
              stopId: stopId,
              stationName: _stationName(station),
            ),
          ),
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

  String _stationName(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['stop_name', 'station_name', 'name', 'station'],
        fallback: AppLocalizations.of(context).stationsUnnamedStation,
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
    final l10n = AppLocalizations.of(context);
    final label = localizedCrowdLevelLabel(l10n, level);
    if (level < 1 || level > 5) {
      return _CrowdLevelUi(
        label: l10n.stationsUnknownCrowdLevel,
        color: const Color(0xFF64748B),
      );
    }
    return _CrowdLevelUi(
        label: label, color: crowdLevelStyleFromIndex(level).color);
  }

  Future<void> _reportCrowdLevel(Map<String, dynamic> station) async {
    final l10n = AppLocalizations.of(context);
    final codes = _stationCodeList(station);
    if (codes.isEmpty) {
      _showMessage(l10n.stationsNoCodeForReport);
      return;
    }

    var selectedCode = codes.first;
    var selectedLevel = 3;
    var geoWarning = '';

    final distance = _userPosition == null
        ? null
        : _distanceMeters(station, _userPosition!);
    if (distance != null && distance > 500) {
      geoWarning = l10n.stationsTooFarFromStation(distance.round());
    } else if (distance == null) {
      geoWarning = l10n.stationsEnableLocationToReport;
    }

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final tooFar = distance != null && distance > 500;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.stationsReportCrowdLevel,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _stationName(station),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (geoWarning.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: tooFar
                              ? const Color(0xFFFEF3F2)
                              : const Color(0xFFF0F5FF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: tooFar
                                ? const Color(0xFFFECDCA)
                                : const Color(0xFFB2DDFF),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              tooFar
                                  ? Icons.warning_amber_rounded
                                  : Icons.info_outline_rounded,
                              size: 16,
                              color: tooFar
                                  ? const Color(0xFFB42318)
                                  : const Color(0xFF0F6FFF),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                geoWarning,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: tooFar
                                      ? const Color(0xFFB42318)
                                      : const Color(0xFF344054),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedCode),
                      initialValue: selectedCode,
                      decoration: InputDecoration(
                        labelText: l10n.stationsStationCodeLabel,
                        border: const OutlineInputBorder(),
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
                    Text(l10n.stationsHowCrowdedNow),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: List<Widget>.generate(5, (offset) {
                        final level = offset + 1;
                        final ui = _crowdUiByLevel(level);
                        return ChoiceChip(
                          label: Text(
                            l10n.stationsCrowdLevelOption(level, ui.label),
                          ),
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
                        onPressed: tooFar ? null : () => Navigator.of(context).pop(true),
                        child: Text(
                          tooFar
                              ? l10n.stationsMoveCloser
                              : l10n.stationsSubmitReport,
                        ),
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
        latitude: _userPosition?.latitude,
        longitude: _userPosition?.longitude,
      );
      unawaited(HapticFeedback.mediumImpact());
      await _loadLatestCrowdReports();
      _showMessage(l10n.stationsReportSubmitted(selectedCode));
    } catch (e) {
      _showMessage(l10n.stationsReportSubmitFailed(e.toString()));
    }
  }

  _CrowdLevelUi _crowdUiByLevel(int level) {
    final l10n = AppLocalizations.of(context);
    if (level < 1 || level > 5) {
      return _CrowdLevelUi(
        label: l10n.stationsUnknown,
        color: const Color(0xFF64748B),
      );
    }
    return _CrowdLevelUi(
        label: localizedCrowdLevelLabel(l10n, level),
        color: crowdLevelStyleFromIndex(level).color);
  }
}

class _StationsSkeleton extends StatelessWidget {
  const _StationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return Container(
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2F7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 180,
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE4F0),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: 110,
                  height: 12,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE4F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
  final VoidCallback onArrivalsTap;
  final VoidCallback onReportTap;

  const _StationCard({
    required this.name,
    required this.codes,
    required this.routeIds,
    required this.crowdLevelUi,
    required this.distanceMeters,
    required this.onTap,
    required this.onArrivalsTap,
    required this.onReportTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE6E9EF)),
        ),
        child: Row(
          children: [
            _RouteBadge(routeIds: routeIds),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.2,
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
                  onPressed: onArrivalsTap,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.schedule_rounded, size: 14),
                  label: Text(
                    l10n.stationsArrivalsButton,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
                TextButton.icon(
                  onPressed: onReportTap,
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.campaign_rounded, size: 14),
                  label: Text(
                    l10n.trackReport,
                    style: const TextStyle(fontSize: 11),
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
      return Container(
        width: 44,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: getRouteColor(route),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          normalizeRouteId(route),
          style: TextStyle(
            color: getRouteOnColor(route),
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.2,
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
    _LegendEntry(label: 'KTM Seremban', routeId: 'KT1'),
    _LegendEntry(label: 'KTM Port Klang', routeId: 'KT2'),
    _LegendEntry(label: 'KLIA Ekspres', routeId: 'ER6'),
    _LegendEntry(label: 'KLIA Transit', routeId: 'ER7'),
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
          Text(
            AppLocalizations.of(context).stationsLineColors,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
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

class _FareTicketStub extends StatelessWidget {
  final FareBreakdown fare;

  const _FareTicketStub({required this.fare});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD4E2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.stationsFareTicketCount(fare.ticketCount),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fare.legs
                      .map((leg) => getRouteDisplayName(leg.line))
                      .toSet()
                      .join(' · '),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8B97AB),
                  ),
                ),
              ],
            ),
          ),
          Text(
            l10n.stationsSegmentFare(fare.total.toStringAsFixed(2)),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePlanSheet extends StatelessWidget {  final String originName;
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
  final FareBreakdown fare;
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
    required this.fare,
    required this.routeSource,
    required this.activeDisruptions,
    required this.usedDisruptionReroute,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final estimatedWalk =
        walkMeters == null ? null : (walkMeters! / 75).round();
    final baseEta =
        estimatedWalk == null ? totalMinutes : totalMinutes + estimatedWalk;
    final crowdEta = estimatedWalk == null
        ? crowdAdjustedMinutes
        : crowdAdjustedMinutes + estimatedWalk;
    final tripCrowdUi = _crowdUiByLevel(l10n, highestCrowdLevel);
    final overallConfidence = _overallForecastConfidence(segmentPlans);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.stationsSuggestedRoute,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.stationsRouteSummary(
                originName,
                originStopId,
                destinationName,
                destinationStopId,
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.stationsDepartAt(_formatDateTime(departureTime)),
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            Text(
              l10n.stationsArriveAt(_formatDateTime(arrivalTime)),
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  label: l10n.stationsBaseEta(_formatDuration(l10n, baseEta)),
                ),
                _InfoChip(
                  label: l10n.stationsCrowdEta(_formatDuration(l10n, crowdEta)),
                ),
                _InfoChip(
                  label: l10n.stationsForecastConfidenceChip(
                    _formatPercent(overallConfidence),
                  ),
                ),
                _InfoChip(
                  label: l10n.stationsTripCrowd(tripCrowdUi.label),
                  textColor: tripCrowdUi.color,
                  borderColor: tripCrowdUi.color.withValues(alpha: 0.45),
                ),
                _InfoChip(label: l10n.stationsStopCount(totalStops)),
                if (usedDisruptionReroute)
                  _InfoChip(
                    label: l10n.stationsReroutedAroundDisruption,
                    textColor: const Color(0xFFD92D20),
                    borderColor: const Color(0xFFFDB0AC),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.stationsRouteSource(routeSource),
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            if (activeDisruptions.isNotEmpty)
              Text(
                l10n.stationsServiceAlerts(
                  _disruptionSummary(activeDisruptions),
                ),
                style: const TextStyle(
                  color: Color(0xFFB42318),
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (walkMeters != null)
              Text(
                l10n.stationsWalkToOrigin(_formatWalk(walkMeters!)),
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            const SizedBox(height: 12),
            if (segmentPlans.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.stationsNoRouteSegments,
                  style: const TextStyle(color: Color(0xFF667085)),
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
                    final crowdUi = _crowdUiByLevel(l10n, plan.occupancyLevel);
                    final confidence = _segmentForecastConfidence(plan);
                    final disruptionNote =
                        _disruptionNoteFor(segment, activeDisruptions);
                    final fareLeg = segment.connectionType
                            .toLowerCase()
                            .contains('transfer')
                        ? null
                        : fare.legFor(
                            segment.routeId,
                            segment.fromStopId,
                            segment.toStopId,
                          );
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
                                    l10n: l10n,
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
                                  l10n.stationsSegmentTimeRange(
                                    _formatTime(plan.departAt),
                                    _formatTime(plan.arriveAt),
                                    crowdUi.label,
                                  ),
                                  style: TextStyle(
                                    color: crowdUi.color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  l10n.stationsForecastConfidence(
                                    _formatPercent(confidence),
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF475467),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _forecastReason(l10n, plan),
                                  style: const TextStyle(
                                    color: Color(0xFF667085),
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  l10n.stationsBoardingTip(
                                    _boardingTipFor(
                                      l10n,
                                      index,
                                      segmentPlans,
                                      namesByStopId,
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF344054),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (disruptionNote != null)
                                  Text(
                                    l10n.stationsServiceAlert(disruptionNote),
                                    style: const TextStyle(
                                      color: Color(0xFFD92D20),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                if (plan.waitMinutes > 0)
                                  Text(
                                    l10n.stationsIncludesWaitingTime(
                                      plan.waitMinutes,
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatDuration(l10n, plan.adjustedMinutes),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF344054),
                                ),
                              ),
                              if (fareLeg != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  l10n.stationsSegmentFare(
                                    fareLeg.fare.toStringAsFixed(2),
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                    color: fareLeg.separateTicket
                                        ? const Color(0xFF99168C)
                                        : const Color(0xFF475467),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (fare.legs.isNotEmpty) ...[
              const SizedBox(height: 14),
              _FareTicketStub(fare: fare),
            ],
          ],
        ),
      ),
    );
  }

  static _RouteCrowdUi _crowdUiByLevel(AppLocalizations l10n, int level) {
    if (level < 1 || level > 5) {
      return _RouteCrowdUi(
        label: l10n.stationsUnknown,
        color: const Color(0xFF64748B),
      );
    }
    return _RouteCrowdUi(
        label: localizedCrowdLevelLabel(l10n, level),
        color: crowdLevelStyleFromIndex(level).color);
  }

  static String _segmentText({
    required AppLocalizations l10n,
    required String routeId,
    required String connectionType,
    required String fromName,
    required String toName,
    required int baseMinutes,
    required int adjustedMinutes,
  }) {
    final base = _formatDuration(l10n, baseMinutes);
    final forecast = _formatDuration(l10n, adjustedMinutes);
    if (connectionType.toLowerCase().contains('transfer')) {
      return l10n.stationsSegmentTransfer(fromName, toName, base, forecast);
    }
    return l10n.stationsSegmentRide(
      getRouteDisplayName(routeId),
      fromName,
      toName,
      base,
      forecast,
    );
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

  static String _forecastReason(
    AppLocalizations l10n,
    _RouteSegmentPlan plan,
  ) {
    final source = plan.sourceType.toLowerCase();
    if (CrowdReportsService.isClosedHoursSource(source)) {
      return l10n.stationsForecastReasonClosed;
    }
    final reasons = <String>[];
    if (source.contains('user')) {
      reasons.add(l10n.stationsForecastReasonRecentReports);
    } else if (source.contains('trend') || source.contains('forecast')) {
      reasons.add(l10n.stationsForecastReasonHourlyForecast);
    } else if (source.contains('simulated')) {
      reasons.add(l10n.stationsForecastReasonSimulation);
    } else {
      reasons.add(l10n.stationsForecastReasonOfflineFallback);
    }
    if (plan.waitMinutes > 0) {
      reasons.add(l10n.stationsForecastReasonTransferWait);
    }
    if (plan.occupancyLevel >= 3) {
      reasons.add(l10n.stationsForecastReasonPeakLoad);
    } else if (plan.occupancyLevel == 2) {
      reasons.add(l10n.stationsForecastReasonStandingDemand);
    }
    return reasons.join(' • ');
  }

  static String _boardingTipFor(
    AppLocalizations l10n,
    int index,
    List<_RouteSegmentPlan> plans,
    Map<String, String> namesByStopId,
  ) {
    final plan = plans[index];
    final segment = plan.segment;
    final toName = namesByStopId[segment.toStopId] ?? segment.toStopId;
    if (segment.connectionType.toLowerCase().contains('transfer')) {
      return l10n.stationsBoardingTipTransfer(toName);
    }
    final nextPlan = index + 1 < plans.length ? plans[index + 1] : null;
    if (nextPlan != null &&
        nextPlan.segment.connectionType.toLowerCase().contains('transfer')) {
      return l10n.stationsBoardingTipMiddleRear(toName);
    }
    if (index == plans.length - 1) {
      return l10n.stationsBoardingTipNearDoors(toName);
    }
    return l10n.stationsBoardingTipPlatformSigns(toName);
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

  static String _formatDuration(AppLocalizations l10n, int totalMinutes) {
    final safeMinutes = totalMinutes < 0 ? 0 : totalMinutes;
    final hours = safeMinutes ~/ 60;
    final minutes = safeMinutes % 60;
    if (hours <= 0) return l10n.homeDurationMinutesShort(minutes);
    if (minutes == 0) return l10n.homeDurationHoursShort(hours);
    return l10n.homeDurationHoursMinutesShort(hours, minutes);
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
