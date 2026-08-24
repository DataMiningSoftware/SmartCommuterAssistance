// ignore_for_file: unused_element

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../services/active_trip_service.dart';
import '../services/crowd_reports_service.dart';
import '../services/navigation_state.dart';
import '../services/notification_service.dart';
import '../services/operating_hours_service.dart';
import '../services/transit_network_service.dart';
import '../widgets/app_page_title.dart';

class TrackRouteScreen extends StatefulWidget {
  final String? startStopId;
  final String? destStopId;
  final String? startName;
  final String? destName;

  const TrackRouteScreen({
    super.key,
    this.startStopId,
    this.destStopId,
    this.startName,
    this.destName,
  });

  @override
  State<TrackRouteScreen> createState() => _TrackRouteScreenState();
}

class _TrackRouteScreenState extends State<TrackRouteScreen>
    with TickerProviderStateMixin {
  final ActiveTripService _tripService = ActiveTripService.instance;
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  final NotificationService _notificationService = NotificationService();
  final TransitNetworkService _transitNetworkService = TransitNetworkService();
  final TextEditingController _emptyTripSearchController =
      TextEditingController();

  final Map<String, _StopNode> _stopsById = <String, _StopNode>{};
  final List<_RouteConnection> _connections = <_RouteConnection>[];
  final Set<String> _sentNotificationKeys = <String>{};

  Timer? _pollTimer;
  late final AnimationController _pulseController;
  late final AnimationController _reportRevealController;
  ActiveTrip? _trip;
  bool _arrived = false;
  int? _estimatedTotalMinutes;
  int _nearestIndex = -1;
  List<_StopNode> _routeStops = <_StopNode>[];
  List<_RouteConnection> _routeEdges = <_RouteConnection>[];
  List<_TrackStationOption> _stationOptions = <_TrackStationOption>[];
  Map<String, int> _crowdByStopId = <String, int>{};
  Map<String, bool> _closedByStopId = <String, bool>{};
  Map<String, StopCrowdForecast> _adaptiveForecastByStopId =
      <String, StopCrowdForecast>{};
  int? _adaptiveRemainingMinutes;
  DateTime? _adaptiveArrivalTime;
  int _adaptiveHighestCrowdLevel = 0;
  DateTime? _lastAdaptiveRefreshAt;
  int _lastAdaptiveRefreshIndex = -1;
  bool _isRefreshingAdaptiveForecasts = false;
  bool _reportMenuVisible = false;
  bool _isSubmittingReport = false;
  bool _isCreatingTrip = false;
  bool _cancelTripPromptOpen = false;
  bool _isRerouting = false;
  int _rerouteCount = 0;
  DateTime? _lastRerouteTime;

  bool _etaPinned = false;
  int _walkMinutesToOrigin = 0;
  int _delaysReported = 0;
  int _crowdsReported = 0;
  String? _weatherAtStart;
  bool _proximityChecked = false;

  _PositionRecord? _lastMovement;
  bool _inactivityDialogOpen = false;

  _TrackStationOption? _pendingSearchOption;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat(reverse: true);
    _reportRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    unawaited(_bootstrap().timeout(const Duration(seconds: 20), onTimeout: () {
      if (mounted && _trip != null) _startTracking();
    }));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _emptyTripSearchController.dispose();
    _pulseController.dispose();
    _reportRevealController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _notificationService.requestPermissions();
    await _loadTrip();
    await _loadNetworkData();
    if (mounted) {
      setState(() {});
    }
    try {
      await _loadCrowdForecasts().timeout(const Duration(seconds: 10));
    } catch (_) {
      // Crowd forecasts unavailable offline — will use fallback defaults.
    }
    if (mounted) {
      setState(() {});
    }
    if (_trip != null) {
      await _computeRouteStops();
    }
    try {
      await _refreshAdaptiveForecasts(force: true).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Adaptive forecasts unavailable offline — tracking continues with fallbacks.
    }
    if (!mounted) return;
    if (_trip != null) {
      _startTracking();
    }
  }

  Future<void> _loadTrip() async {
    final storedTrip = _tripService.activeTrip.value;
    if (storedTrip != null) {
      _trip = storedTrip;
      return;
    }

    if (widget.startStopId == null || widget.destStopId == null) {
      return;
    }

    _trip = ActiveTrip(
      originStopId: widget.startStopId!,
      destinationStopId: widget.destStopId!,
      originName: widget.startName ?? widget.startStopId!,
      destinationName: widget.destName ?? widget.destStopId!,
      routePreference: 'efficiency',
      highestCrowdLevel: 0,
      createdAt: DateTime.now(),
      estimatedTotalMinutes: null,
      stops: <ActiveTripStop>[
        ActiveTripStop(
          stopId: widget.startStopId!,
          stopName: widget.startName ?? widget.startStopId!,
          routeId:
              normalizeRouteId(_inferRouteIdFromStopId(widget.startStopId!)),
        ),
        ActiveTripStop(
          stopId: widget.destStopId!,
          stopName: widget.destName ?? widget.destStopId!,
          routeId:
              normalizeRouteId(_inferRouteIdFromStopId(widget.destStopId!)),
        ),
      ],
    );
    await _tripService.saveTrip(_trip!);
  }

  Future<void> _loadNetworkData() async {
    final network = await _transitNetworkService.loadNetwork();

    _stopsById
      ..clear()
      ..addEntries(
        network.stopsById.entries.map(
          (entry) => MapEntry(
            entry.key,
            _StopNode(
              stopId: entry.value.stopId,
              stopName: entry.value.stopName,
              routeId: entry.value.routeId,
              latitude: entry.value.latitude,
              longitude: entry.value.longitude,
            ),
          ),
        ),
      );

    _connections
      ..clear()
      ..addAll(
        network.connections.map(
          (edge) => _RouteConnection(
            fromStopId: edge.fromStopId,
            toStopId: edge.toStopId,
            routeId: edge.routeId,
            connectionType: edge.connectionType,
            travelMinutes: edge.travelMinutes,
          ),
        ),
      );

    _stationOptions = network.stationOptions
        .map(
          (option) => _TrackStationOption(
            stationName: option.stationName,
            stopIds: option.stopIds,
            routeIds: option.routeIds,
          ),
        )
        .toList();
  }

  List<_RouteConnection> _buildFallbackConnections(List<_StopNode> stops) {
    final edges = <_RouteConnection>[];
    final seen = <String>{};

    void addEdge({
      required String from,
      required String to,
      required String routeId,
      required String type,
      required int minutes,
    }) {
      final key = '$from|$to|$routeId|$type';
      if (!seen.add(key)) return;
      edges.add(
        _RouteConnection(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          connectionType: type,
          travelMinutes: minutes,
        ),
      );
    }

    final byLine = <String, List<_StopNode>>{};
    for (final stop in stops) {
      byLine.putIfAbsent(stop.routeId, () => <_StopNode>[]).add(stop);
    }
    for (final entry in byLine.entries) {
      final ordered = List<_StopNode>.from(entry.value)
        ..sort((a, b) => a.stopId.compareTo(b.stopId));
      for (var i = 0; i < ordered.length - 1; i++) {
        addEdge(
          from: ordered[i].stopId,
          to: ordered[i + 1].stopId,
          routeId: entry.key,
          type: 'standard_stop',
          minutes: 2,
        );
        addEdge(
          from: ordered[i + 1].stopId,
          to: ordered[i].stopId,
          routeId: entry.key,
          type: 'standard_stop',
          minutes: 2,
        );
      }
    }

    final byStation = <String, List<_StopNode>>{};
    for (final stop in stops) {
      byStation
          .putIfAbsent(stop.stopName.toUpperCase(), () => <_StopNode>[])
          .add(stop);
    }
    for (final stationStops in byStation.values) {
      if (stationStops.length < 2) continue;
      for (var i = 0; i < stationStops.length - 1; i++) {
        for (var j = i + 1; j < stationStops.length; j++) {
          if (stationStops[i].routeId == stationStops[j].routeId) continue;
          addEdge(
            from: stationStops[i].stopId,
            to: stationStops[j].stopId,
            routeId: stationStops[j].routeId,
            type: 'interchange_transfer',
            minutes: 3,
          );
          addEdge(
            from: stationStops[j].stopId,
            to: stationStops[i].stopId,
            routeId: stationStops[i].routeId,
            type: 'interchange_transfer',
            minutes: 3,
          );
        }
      }
    }

    return edges;
  }

  void _rebuildStationOptions() {
    final grouped = <String, List<_StopNode>>{};
    for (final stop in _stopsById.values) {
      grouped.putIfAbsent(stop.stopName.toUpperCase(), () => <_StopNode>[]).add(
            stop,
          );
    }

    _stationOptions = grouped.values.map((stops) {
      final sorted = List<_StopNode>.from(stops)
        ..sort((a, b) => a.stopId.compareTo(b.stopId));
      final routeIds =
          <String>{for (final stop in sorted) stop.routeId}.toList()..sort();
      return _TrackStationOption(
        stationName: sorted.first.stopName,
        stopIds: sorted.map((stop) => stop.stopId).toList(),
        routeIds: routeIds,
      );
    }).toList()
      ..sort((a, b) => a.stationName.compareTo(b.stationName));
  }

  Future<void> _loadCrowdForecasts() async {
    if (_stopsById.isEmpty) return;
    final forecasts = await _crowdReportsService.fetchForecastForStopsAtTime(
      _stopsById.keys.toList(),
      DateTime.now(),
    );
    _crowdByStopId = <String, int>{
      for (final entry in forecasts.entries)
        entry.key.toUpperCase(): entry.value.occupancyLevel,
    };
    _closedByStopId = <String, bool>{
      for (final entry in forecasts.entries)
        entry.key.toUpperCase(): entry.value.isClosedHours,
    };
  }

  bool _isStationOptionClosed(_TrackStationOption option) {
    for (final stopId in option.stopIds) {
      if (_closedByStopId[stopId.trim().toUpperCase()] ?? false) {
        return true;
      }
    }
    return false;
  }

  _StopNode? _nearestStop(double latitude, double longitude) {
    _StopNode? nearest;
    var nearestMeters = double.infinity;
    for (final stop in _stopsById.values) {
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

  Future<void> _computeRouteStops() async {
    final trip = _trip;
    if (trip == null) return;
    final result = _bestPathToStops(
      originStopId: trip.originStopId,
      destinationStopIds: <String>[trip.destinationStopId],
      preferComfort: trip.routePreference == 'comfort',
    );
    if (result == null) return;
    await _applyResolvedTrip(baseTrip: trip, result: result);
  }

  Future<void> _applyResolvedTrip({
    required ActiveTrip baseTrip,
    required _DijkstraResult result,
  }) async {
    final routeStops = <_StopNode>[];
    final activeTripStops = <ActiveTripStop>[];
    final originStop = _stopsById[baseTrip.originStopId];
    if (originStop != null) {
      routeStops.add(originStop);
      activeTripStops.add(
        ActiveTripStop(
          stopId: originStop.stopId,
          stopName: originStop.stopName,
          routeId: result.path.isEmpty
              ? originStop.routeId
              : result.path.first.routeId,
        ),
      );
    }

    for (final edge in result.path) {
      final stop = _stopsById[edge.toStopId];
      if (stop == null) continue;
      routeStops.add(stop);
      activeTripStops.add(
        ActiveTripStop(
          stopId: stop.stopId,
          stopName: stop.stopName,
          routeId: edge.routeId,
        ),
      );
    }

    _routeStops = routeStops;
    _routeEdges = result.path;
    _estimatedTotalMinutes = result.totalMinutes;
    _adaptiveForecastByStopId = <String, StopCrowdForecast>{};
    _adaptiveRemainingMinutes = null;
    _adaptiveArrivalTime = null;
    _adaptiveHighestCrowdLevel = _highestRouteCrowdLevel(activeTripStops);
    _lastAdaptiveRefreshAt = null;
    _lastAdaptiveRefreshIndex = -1;
    ActiveTripService.instance.clearPinnedEta();
    _etaPinned = false;
    _proximityChecked = false;
    _walkMinutesToOrigin = 0;
    _lastMovement = null;
    _inactivityDialogOpen = false;
    _trip = ActiveTrip(
      originStopId: baseTrip.originStopId,
      destinationStopId: result.destinationStopId,
      originName: baseTrip.originName,
      destinationName: baseTrip.destinationName,
      routePreference: baseTrip.routePreference,
      highestCrowdLevel: _highestRouteCrowdLevel(activeTripStops),
      createdAt: baseTrip.createdAt,
      estimatedTotalMinutes: result.totalMinutes,
      stops: activeTripStops,
    );
    await _tripService.saveTrip(_trip!);
  }

  int _highestRouteCrowdLevel(List<ActiveTripStop> stops) {
    var highest = 0;
    for (final stop in stops) {
      final level = _crowdByStopId[stop.stopId] ?? 0;
      if (level > highest) highest = level;
    }
    return highest;
  }

  _DijkstraResult? _bestPathToStops({
    required String originStopId,
    required List<String> destinationStopIds,
    required bool preferComfort,
  }) {
    _DijkstraResult? bestResult;
    for (final destinationStopId in destinationStopIds) {
      final result = _shortestPath(
        originStopId: originStopId,
        destinationStopId: destinationStopId,
        preferComfort: preferComfort,
      );
      if (result == null) continue;
      if (bestResult == null ||
          result.weightedMinutes < bestResult.weightedMinutes ||
          (result.weightedMinutes == bestResult.weightedMinutes &&
              result.totalMinutes < bestResult.totalMinutes)) {
        bestResult = result;
      }
    }
    return bestResult;
  }

  _DijkstraResult? _shortestPath({
    required String originStopId,
    required String destinationStopId,
    required bool preferComfort,
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
        final crowdPenalty =
            preferComfort ? _crowdPenaltyForStop(edge.toStopId) : 0;
        final candidate = currentDistance + edge.travelMinutes + crowdPenalty;
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
      weightedMinutes: distances[destinationStopId] ?? total,
    );
  }

  int _crowdPenaltyForStop(String stopId) {
    switch (_crowdByStopId[stopId] ?? 0) {
      case 2:
        return 4;
      case 3:
        return 10;
      case 4:
        return 18;
      case 5:
        return 24;
      default:
        return 0;
    }
  }

  Future<void> _refreshAdaptiveForecasts({
    bool force = false,
  }) async {
    final trip = _trip;
    if (trip == null || _routeStops.isEmpty) return;
    if (_isRefreshingAdaptiveForecasts && !force) return;

    final now = DateTime.now();
    final currentIndex = _resolvedCurrentIndex;
    final lastRefreshAt = _lastAdaptiveRefreshAt;
    final movedAlongRoute = currentIndex != _lastAdaptiveRefreshIndex;
    final refreshAge = lastRefreshAt == null
        ? const Duration(days: 1)
        : now.difference(lastRefreshAt);
    if (!force &&
        !movedAlongRoute &&
        refreshAge < const Duration(seconds: 45)) {
      return;
    }

    final remainingEdges = currentIndex >= _routeEdges.length
        ? const <_RouteConnection>[]
        : _routeEdges.sublist(currentIndex);
    if (_arrived || remainingEdges.isEmpty) {
      if (!mounted) return;
      setState(() {
        _adaptiveForecastByStopId = <String, StopCrowdForecast>{};
        _adaptiveRemainingMinutes = 0;
        _adaptiveArrivalTime = now;
        _adaptiveHighestCrowdLevel =
            _crowdByStopId[trip.destinationStopId.trim().toUpperCase()] ?? 0;
        _lastAdaptiveRefreshAt = now;
        _lastAdaptiveRefreshIndex = currentIndex;
      });
      return;
    }

    _isRefreshingAdaptiveForecasts = true;
    try {
      final stopIds = <String>{
        for (final stop in _routeStops.skip(currentIndex))
          stop.stopId.trim().toUpperCase(),
      }.toList();
      final probeTimes = <DateTime>[now];
      var elapsedBaseMinutes = 0;
      for (final edge in remainingEdges) {
        probeTimes.add(now.add(Duration(minutes: elapsedBaseMinutes)));
        elapsedBaseMinutes += edge.travelMinutes;
      }

      final grid = await _crowdReportsService.fetchForecastGrid(
        stopIds: stopIds,
        times: probeTimes,
      );

      final forecastByStop = <String, StopCrowdForecast>{};
      var cursor = now;
      var highestCrowdLevel = 0;

      final currentStop = _routeStops[currentIndex];
      final currentForecast = _bestForecastForStopAtTime(
        stopId: currentStop.stopId,
        time: now,
        grid: grid,
      );
      if (currentForecast != null) {
        forecastByStop[currentStop.stopId.trim().toUpperCase()] =
            currentForecast;
        highestCrowdLevel =
            math.max(highestCrowdLevel, currentForecast.occupancyLevel);
      }

      for (var index = 0; index < remainingEdges.length; index++) {
        final edge = remainingEdges[index];
        final forecast = _forecastForConnectionAtTime(
          connection: edge,
          time: cursor,
          grid: grid,
        );
        final fallbackLevel =
            _crowdByStopId[edge.toStopId.trim().toUpperCase()] ?? 2;
        final level = forecast?.occupancyLevel.clamp(0, 5) ?? fallbackLevel;
        highestCrowdLevel = math.max(highestCrowdLevel, level);

        forecastByStop[edge.toStopId.trim().toUpperCase()] = forecast ??
            _fallbackForecastForStop(
              stopId: edge.toStopId,
              time: cursor,
              level: level,
            );

        final etaMultiplier =
            forecast?.etaMultiplier ?? _fallbackEtaMultiplier(level);
        final movementMinutes = math.max(
          edge.travelMinutes,
          (edge.travelMinutes * etaMultiplier).round(),
        );
        final includeWait = index == 0 ||
            edge.connectionType.toLowerCase().contains('transfer');
        final waitMinutes = includeWait
            ? (forecast?.expectedWaitMinutes ?? _fallbackWaitMinutes(level))
            : 0;
        final adjustedMinutes = movementMinutes + waitMinutes;
        cursor = cursor.add(Duration(minutes: adjustedMinutes));
      }

      if (!mounted) return;
      setState(() {
        _crowdByStopId = <String, int>{
          ..._crowdByStopId,
          for (final entry in forecastByStop.entries)
            entry.key: entry.value.occupancyLevel,
        };
        _adaptiveForecastByStopId = forecastByStop;
        _adaptiveHighestCrowdLevel = _adaptiveHighestCrowdLevel > highestCrowdLevel
            ? _adaptiveHighestCrowdLevel
            : highestCrowdLevel;
        _lastAdaptiveRefreshAt = now;
        _lastAdaptiveRefreshIndex = currentIndex;
      });
    } catch (_) {
      // Keep tracking resilient when the forecast refresh fails.
    } finally {
      _isRefreshingAdaptiveForecasts = false;
    }
  }

  StopCrowdForecast? _forecastForConnectionAtTime({
    required _RouteConnection connection,
    required DateTime time,
    required Map<String, StopCrowdForecast> grid,
  }) {
    final fromKey = CrowdReportsService.forecastKeyForTime(
      stopId: connection.fromStopId,
      time: time,
    );
    final toKey = CrowdReportsService.forecastKeyForTime(
      stopId: connection.toStopId,
      time: time,
    );
    return grid[fromKey] ?? grid[toKey];
  }

  StopCrowdForecast? _bestForecastForStopAtTime({
    required String stopId,
    required DateTime time,
    required Map<String, StopCrowdForecast> grid,
  }) {
    final key = CrowdReportsService.forecastKeyForTime(
      stopId: stopId,
      time: time,
    );
    return grid[key];
  }

  StopCrowdForecast _fallbackForecastForStop({
    required String stopId,
    required DateTime time,
    required int level,
  }) {
    return StopCrowdForecast(
      stopId: stopId.trim().toUpperCase(),
      forecastHour: time.hour,
      dayOfWeek:
          time.weekday == DateTime.sunday ? 6 : time.weekday - 1,
      occupancyLevel: level.clamp(0, 5),
      expectedWaitMinutes: _fallbackWaitMinutes(level),
      etaMultiplier: _fallbackEtaMultiplier(level),
      sourceType: 'fallback',
      updatedAt: null,
    );
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

  void _showTrackMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool?> _showPackedRoutePrompt(String destinationName) {
    return showModalBottomSheet<bool>(
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
                const Row(
                  children: [
                    Icon(
                      Icons.sentiment_dissatisfied_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Looks like your route is crowded.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'A calmer trip to $destinationName is available, but it may take longer.',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Take a more relaxed route'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Keep with crowded route'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showScheduleAheadSheet() async {
    _TrackStationOption? origin;
    _TrackStationOption? destination;
    DateTime? targetTime;
    var originQuery = '';
    var destQuery = '';
    var focusOrigin = true;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var step = 0;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizedBox(
                  height: step == 0 ? 520 : 480,
                  child: step == 0
                      ? _buildPlannerRoutePicker(
                          setSheetState: setSheetState,
                           origin: origin,
                           destination: destination,
                           originQuery: originQuery,
                           destQuery: destQuery,
                           focusOrigin: focusOrigin,
                           onOriginChanged: (opt) {
                             origin = opt;
                           },
                           onDestinationChanged: (opt) {
                             destination = opt;
                           },
                           onOriginQueryChanged: (value) => originQuery = value,
                           onDestinationQueryChanged: (value) => destQuery = value,
                           onFocusOriginChanged: (value) => focusOrigin = value,
                           onNext: () {
                             if (origin == null || destination == null) return;
                            step = 1;
                            setSheetState(() {});
                          },
                        )
                      : _buildPlannerTimePicker(
                          setSheetState: setSheetState,
                          onConfirm: (time) {
                            targetTime = time;
                            Navigator.of(context).pop({
                              'origin': origin,
                              'destination': destination,
                              'targetTime': time,
                            });
                          },
                        ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || origin == null || destination == null || targetTime == null) return;

    await _computeScheduleAheadPlan(
      origin: origin!,
      destination: destination!,
      targetArrivalTime: targetTime!,
    );
  }

  Widget _buildPlannerRoutePicker({
    required void Function(void Function()) setSheetState,
    required _TrackStationOption? origin,
    required _TrackStationOption? destination,
    required String originQuery,
    required String destQuery,
    required bool focusOrigin,
    required ValueChanged<_TrackStationOption> onOriginChanged,
    required ValueChanged<_TrackStationOption> onDestinationChanged,
    required ValueChanged<String> onOriginQueryChanged,
    required ValueChanged<String> onDestinationQueryChanged,
    required ValueChanged<bool> onFocusOriginChanged,
    required VoidCallback onNext,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Plan Your Trip',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Select origin and destination stations.',
          style: TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: const Color(0xFF0A3A8B),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: origin?.stationName ?? 'From',
              prefixIcon: const Icon(Icons.trip_origin_rounded),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (value) {
              setSheetState(() {
                onFocusOriginChanged(true);
                onOriginQueryChanged(value);
              });
            },
            onTap: () => setSheetState(() => onFocusOriginChanged(true)),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: !focusOrigin ? const Color(0xFF0A3A8B) : const Color(0xFFDCE6F5),
              width: !focusOrigin ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            decoration: InputDecoration(
              hintText: destination?.stationName ?? 'To',
              prefixIcon: const Icon(Icons.location_on_rounded),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (value) {
              setSheetState(() {
                onFocusOriginChanged(false);
                onDestinationQueryChanged(value);
              });
            },
            onTap: () => setSheetState(() => onFocusOriginChanged(false)),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView.separated(
            itemCount: _stationOptions.length,
            separatorBuilder: (_, __) => const Divider(height: 1, thickness: 0.6),
            itemBuilder: (context, index) {
              final option = _stationOptions[index];
              final query = (focusOrigin ? originQuery : destQuery).trim().toLowerCase();
              if (query.isNotEmpty &&
                  !option.stationName.toLowerCase().contains(query) &&
                  !option.stopIds.any((id) => id.toLowerCase().contains(query))) {
                return const SizedBox.shrink();
              }
              if (_isStationOptionClosed(option)) {
                return const SizedBox.shrink();
              }
              final alreadySelected = option == origin || option == destination;
              return Opacity(
                opacity: alreadySelected ? 0.5 : 1,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _TrackSearchRouteBadge(routeIds: option.routeIds),
                  title: Text(
                    option.stationName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    option.stopIds.join(', '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Icon(
                    focusOrigin ? Icons.trip_origin_rounded : Icons.location_on_rounded,
                    size: 18,
                    color: focusOrigin
                        ? const Color(0xFF0A3A8B)
                        : const Color(0xFFDC2626),
                  ),
                  onTap: alreadySelected
                      ? null
                      : () => setSheetState(() {
                            if (focusOrigin) {
                              onOriginChanged(option);
                              onOriginQueryChanged('');
                              onFocusOriginChanged(false);
                            } else {
                              onDestinationChanged(option);
                              onDestinationQueryChanged('');
                            }
                          }),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: origin != null && destination != null ? onNext : null,
            child: const Text('Set arrival time'),
          ),
        ),
      ],
    );
  }

  Widget _buildPlannerTimePicker({
    required void Function(void Function()) setSheetState,
    required ValueChanged<DateTime> onConfirm,
  }) {
    var date = DateTime.now().add(const Duration(hours: 1));
    var time = TimeOfDay(hour: date.hour, minute: date.minute);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'When do you want to arrive?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Set your target arrival time and we\'ll calculate when to leave.',
          style: TextStyle(
            color: Color(0xFF667085),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (picked != null) {
                    setSheetState(() => date = picked);
                  }
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                  );
                  if (picked != null) {
                    setSheetState(() => time = picked);
                  }
                },
                icon: const Icon(Icons.access_time_rounded, size: 16),
                label: Text(
                  time.format(context),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              onConfirm(DateTime(
                date.year, date.month, date.day, time.hour, time.minute,
              ));
            },
            child: const Text('Calculate'),
          ),
        ),
      ],
    );
  }

  Future<void> _computeScheduleAheadPlan({
    required _TrackStationOption origin,
    required _TrackStationOption destination,
    required DateTime targetArrivalTime,
  }) async {
    _showTrackMessage('Calculating schedule...');

    try {
      final originStopId = origin.stopIds.first;

      final result = _bestPathToStops(
        originStopId: originStopId,
        destinationStopIds: destination.stopIds,
        preferComfort: false,
      );
      if (result == null) {
        _showTrackMessage('No route found to ${destination.stationName}.');
        return;
      }

      const walkMinutes = 0;

      final stopIds = <String>{
        originStopId.trim().toUpperCase(),
        for (final edge in result.path) edge.toStopId.trim().toUpperCase(),
      }.toList();

      final probeTimes = <DateTime>[targetArrivalTime];
      var elapsed = 0;
      for (final edge in result.path) {
        probeTimes.add(targetArrivalTime.subtract(Duration(minutes: elapsed)));
        elapsed += edge.travelMinutes;
      }

      final grid = await _crowdReportsService.fetchForecastGrid(
        stopIds: stopIds,
        times: probeTimes,
      );

      var totalMinutes = walkMinutes;
      var cursor = targetArrivalTime.subtract(Duration(minutes: totalMinutes));

      for (final edge in result.path) {
        final forecast = _bestForecastForStopAtTime(
          stopId: edge.toStopId,
          time: cursor,
          grid: grid,
        );
        final level = forecast?.occupancyLevel.clamp(0, 5) ?? 2;
        final etaMultiplier = forecast?.etaMultiplier ?? _fallbackEtaMultiplier(level);
        final movementMinutes = math.max(
          edge.travelMinutes,
          (edge.travelMinutes * etaMultiplier).round(),
        );
        final waitMinutes = edge.connectionType.toLowerCase().contains('transfer')
            ? (forecast?.expectedWaitMinutes ?? _fallbackWaitMinutes(level))
            : 0;
        totalMinutes += movementMinutes + waitMinutes;
        cursor = cursor.add(Duration(minutes: movementMinutes + waitMinutes));
      }

      final leaveByTime = targetArrivalTime.subtract(
        Duration(minutes: totalMinutes),
      );
      final now = DateTime.now();

      if (!mounted) return;
      _showScheduleAheadResult(
        destination: destination,
        originStopName: origin.stationName,
        leaveByTime: leaveByTime,
        targetArrivalTime: targetArrivalTime,
        totalMinutes: totalMinutes,
        walkMinutes: walkMinutes,
        result: result,
        canStartNow: leaveByTime.isBefore(now) || leaveByTime.isAtSameMomentAs(now),
      );
    } catch (e) {
      _showTrackMessage('Could not plan ahead: $e');
    }
  }

  void _showScheduleAheadResult({
    required _TrackStationOption destination,
    required String originStopName,
    required DateTime leaveByTime,
    required DateTime targetArrivalTime,
    required int totalMinutes,
    required int walkMinutes,
    required _DijkstraResult result,
    required bool canStartNow,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final localizations = MaterialLocalizations.of(context);
        final leaveLabel = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(leaveByTime),
        );
        final arriveLabel = localizations.formatTimeOfDay(
          TimeOfDay.fromDateTime(targetArrivalTime),
        );

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: Color(0xFF0A3A8B)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Trip Plan',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F5FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _PlanRow(
                        icon: Icons.departure_board_rounded,
                        label: 'Leave by',
                        value: leaveLabel,
                      ),
                      const SizedBox(height: 8),
                      _PlanRow(
                        icon: Icons.directions_walk_rounded,
                        label: 'Walk to $originStopName',
                        value: '$walkMinutes min',
                      ),
                      const SizedBox(height: 8),
                      _PlanRow(
                        icon: Icons.train_rounded,
                        label: 'Via ${result.path.map((e) => e.routeId).toSet().join(' → ')}',
                        value: '${totalMinutes - walkMinutes} min',
                      ),
                      const SizedBox(height: 8),
                      _PlanRow(
                        icon: Icons.location_on_rounded,
                        label: 'Arrive at ${destination.stationName}',
                        value: arriveLabel,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Estimated total: $totalMinutes min',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
                if (canStartNow) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(_startTripFromSearch(destination));
                      },
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start this trip now'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _startTripFromSearch(_TrackStationOption option) async {
    if (_isCreatingTrip || option.stopIds.isEmpty) return;
    if (_isStationOptionClosed(option)) {
      _showTrackMessage(
        '${option.stationName} is unavailable during closing hours.',
      );
      return;
    }

    setState(() => _isCreatingTrip = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showTrackMessage('Enable location services before starting a trip.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showTrackMessage('Location permission is required to start a trip.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final originStop = _nearestStop(position.latitude, position.longitude);
      if (originStop == null) {
        _showTrackMessage('Could not determine your nearest station yet.');
        return;
      }

      final forecasts = await _crowdReportsService.fetchForecastForStopsAtTime(
        option.stopIds,
        DateTime.now(),
      );
      var highestCrowdLevel = 0;
      for (final forecast in forecasts.values) {
        if (forecast.occupancyLevel > highestCrowdLevel) {
          highestCrowdLevel = forecast.occupancyLevel;
        }
      }

      var routePreference = 'efficiency';
      if (highestCrowdLevel >= 4) {
        final useComfort = await _showPackedRoutePrompt(option.stationName);
        if (useComfort == null) return;
        routePreference = useComfort ? 'comfort' : 'efficiency';
      }

      final newTrip = ActiveTrip(
        originStopId: originStop.stopId,
        destinationStopId: option.stopIds.first,
        originName: originStop.stopName,
        destinationName: option.stationName,
        routePreference: routePreference,
        highestCrowdLevel: highestCrowdLevel,
        createdAt: DateTime.now(),
        estimatedTotalMinutes: null,
        stops: <ActiveTripStop>[
          ActiveTripStop(
            stopId: originStop.stopId,
            stopName: originStop.stopName,
            routeId: originStop.routeId,
          ),
          ActiveTripStop(
            stopId: option.stopIds.first,
            stopName: option.stationName,
            routeId: option.routeIds.isEmpty ? 'N/A' : option.routeIds.first,
          ),
        ],
      );

      await _tripService.saveTrip(newTrip);
      _trip = newTrip;
      await _loadCrowdForecasts();
      await _computeRouteStops();
      await _refreshAdaptiveForecasts(force: true);
      _startTracking();

      if (!mounted) return;
      setState(() {
        _emptyTripSearchController.clear();
        _pendingSearchOption = null;
        _nearestIndex = 0;
        _arrived = false;
        _etaPinned = false;
        _walkMinutesToOrigin = 0;
        _delaysReported = 0;
        _crowdsReported = 0;
        _weatherAtStart = null;
        _proximityChecked = false;
        _lastMovement = null;
        _inactivityDialogOpen = false;
        _reportMenuVisible = false;
      });
    } catch (e) {
      _showTrackMessage('Could not start trip: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreatingTrip = false);
      }
    }
  }

  Future<void> _changeDestinationFromCurrentStation() async {
    final trip = _trip;
    if (trip == null || _routeStops.isEmpty || _stationOptions.isEmpty) return;

    final currentStop = _routeStops[_resolvedCurrentIndex];
    final option = await _showDestinationPicker(currentStop);
    if (option == null) return;

    final candidateStopIds =
        option.stopIds.where((stopId) => stopId != currentStop.stopId).toList();
    if (candidateStopIds.isEmpty) {
      _showTrackMessage('Choose a destination beyond ${currentStop.stopName}.');
      return;
    }

    final result = _bestPathToStops(
      originStopId: currentStop.stopId,
      destinationStopIds: candidateStopIds,
      preferComfort: trip.routePreference == 'comfort',
    );
    if (result == null) {
      _showTrackMessage('No route found for ${option.stationName}.');
      return;
    }

    await _applyResolvedTrip(
      baseTrip: ActiveTrip(
        originStopId: currentStop.stopId,
        destinationStopId: result.destinationStopId,
        originName: currentStop.stopName,
        destinationName: option.stationName,
        routePreference: trip.routePreference,
        highestCrowdLevel: trip.highestCrowdLevel,
        createdAt: DateTime.now(),
        estimatedTotalMinutes: result.totalMinutes,
        stops: trip.stops,
      ),
      result: result,
    );
    await _refreshAdaptiveForecasts(force: true);

    if (!mounted) return;
    setState(() {
      _nearestIndex = 0;
      _arrived = false;
      _reportMenuVisible = false;
    });
    _sentNotificationKeys.clear();
  }

  Future<_TrackStationOption?> _showDestinationPicker(_StopNode currentStop) {
    final availableOptions = _stationOptions
        .where(
          (option) =>
              option.stationName.toUpperCase() !=
              currentStop.stopName.toUpperCase(),
        )
        .toList();

    return showModalBottomSheet<_TrackStationOption>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filteredOptions = availableOptions.where((option) {
              final search = query.trim().toLowerCase();
              if (search.isEmpty) return true;
              final inName = option.stationName.toLowerCase().contains(search);
              final inStopId = option.stopIds.any(
                (stopId) => stopId.toLowerCase().contains(search),
              );
              final inRouteId = option.routeIds.any(
                (routeId) => routeId.toLowerCase().contains(search),
              );
              return inName || inStopId || inRouteId;
            }).toList()
              ..sort((a, b) {
                final aClosed = _isStationOptionClosed(a);
                final bClosed = _isStationOptionClosed(b);
                if (aClosed == bClosed) {
                  return a.stationName.compareTo(b.stationName);
                }
                return aClosed ? 1 : -1;
              });

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  16 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: SizedBox(
                  height: 460,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Switch destination from ${currentStop.stopName}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Pick a new target station and the route will restart from where you are now.',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search station or code',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) =>
                            setSheetState(() => query = value),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: ListView.separated(
                          itemCount: filteredOptions.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, thickness: 0.6),
                          itemBuilder: (context, index) {
                            final option = filteredOptions[index];
                            final isClosed = _isStationOptionClosed(option);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              enabled: !isClosed,
                              leading: _TrackSearchRouteBadge(
                                routeIds: option.routeIds,
                              ),
                              title: Text(
                                option.stationName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color:
                                      isClosed ? const Color(0xFF98A2B3) : null,
                                ),
                              ),
                              subtitle: Text(
                                '${option.routeIds.join(' • ')}  |  ${option.stopIds.join(', ')}',
                              ),
                              trailing: Icon(
                                Icons.north_east_rounded,
                                color:
                                    isClosed ? const Color(0xFF98A2B3) : null,
                              ),
                              onTap: isClosed
                                  ? null
                                  : () => Navigator.of(context).pop(option),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _startTracking() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _trackingTick();
    });
    unawaited(_trackingTick());
  }

  Future<void> _trackingTick() async {
    final trip = _trip;
    if (trip == null || _routeStops.isEmpty) return;
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      if (!mounted) return;

      final destination = _stopsById[trip.destinationStopId];
      int nearestIndex = -1;
      var bestDistance = double.infinity;
      for (var i = 0; i < _routeStops.length; i++) {
        final stop = _routeStops[i];
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          stop.latitude,
          stop.longitude,
        );
        if (distance < bestDistance) {
          bestDistance = distance;
          nearestIndex = i;
        }
      }

      final distanceToDestination = destination == null
          ? null
          : Geolocator.distanceBetween(
              position.latitude,
              position.longitude,
              destination.latitude,
              destination.longitude,
            );

      final previousIndex = _nearestIndex;
      setState(() {
        _nearestIndex = nearestIndex;
        _arrived = distanceToDestination != null && distanceToDestination <= 80;
      });

      if (_arrived) {
        await _handleArrivalWithFeedback();
        return;
      }

      if (!_etaPinned && !_proximityChecked) {
        await _checkProximityAndPinEta(position);
      }

      final shouldReroute = await _checkOffRoute(
        position.latitude,
        position.longitude,
        bestDistance,
      );
      if (shouldReroute) return;

      if (_etaPinned && !_inactivityDialogOpen) {
        await _checkInactivity(position);
      }

      if (nearestIndex != previousIndex) {
        await _handleProgressNotifications(nearestIndex);
      }
      await _refreshAdaptiveForecasts(force: nearestIndex != previousIndex);
    } catch (_) {
      // Keep tracking silent when location lookup fails.
    }
  }

  Future<void> _handleProgressNotifications(int nearestIndex) async {
    if (nearestIndex < 0 || nearestIndex >= _routeStops.length) return;
    final currentStop = _routeStops[nearestIndex];
    final nextStop = nearestIndex + 1 < _routeStops.length
        ? _routeStops[nearestIndex + 1]
        : null;

    if (nextStop != null && currentStop.routeId != nextStop.routeId) {
      final key = 'change:${currentStop.stopId}:${nextStop.routeId}';
      if (_sentNotificationKeys.add(key)) {
        await _notificationService.showNotification(
          title: 'Change line at ${currentStop.stopName}',
          body: 'Switch to the ${nextStop.routeId} line after this station.',
          type: NotificationType.trainArrival,
        );
      }
    }
  }

  Future<void> _handleArrivalWithFeedback() async {
    final trip = _trip;
    if (trip == null) return;
    final key = 'arrived:${trip.destinationStopId}';
    if (!_sentNotificationKeys.add(key)) return;

    await _notificationService.showNotification(
      title: 'You have reached ${trip.destinationName}',
      body: 'Your trip has ended.',
      type: NotificationType.info,
    );

    final predictedMinutes = trip.estimatedTotalMinutes;
    if (predictedMinutes != null) {
      final actualMinutes = DateTime.now().difference(trip.createdAt).inMinutes;
      final predictedWithWalk = predictedMinutes + _walkMinutesToOrigin;
      await _crowdReportsService.submitTripFeedback(
        routeId: _routeStops.isEmpty ? '' : _routeStops.last.routeId,
        originStop: trip.originStopId,
        destStop: trip.destinationStopId,
        predictedMinutes: predictedWithWalk > 0 ? predictedWithWalk : predictedMinutes,
        actualMinutes: actualMinutes > 0 ? actualMinutes : 1,
        crowdAtStart: trip.highestCrowdLevel,
        delaysReported: _delaysReported,
        crowdsReported: _crowdsReported,
        walkDistanceM: _walkMinutesToOrigin * 80.0,
        weather: _weatherAtStart,
      );
    }

    ActiveTripService.instance.clearPinnedEta();
    _pollTimer?.cancel();
    await _tripService.clearTrip();
    if (!mounted) return;
    setState(() {
      _trip = null;
      _routeStops = <_StopNode>[];
      _routeEdges = <_RouteConnection>[];
      _adaptiveForecastByStopId = <String, StopCrowdForecast>{};
      _nearestIndex = -1;
      _arrived = false;
      _estimatedTotalMinutes = null;
      _adaptiveRemainingMinutes = null;
      _adaptiveArrivalTime = null;
      _adaptiveHighestCrowdLevel = 0;
      _etaPinned = false;
      _walkMinutesToOrigin = 0;
      _delaysReported = 0;
      _crowdsReported = 0;
      _weatherAtStart = null;
      _proximityChecked = false;
      _lastMovement = null;
      _inactivityDialogOpen = false;
      _lastAdaptiveRefreshAt = null;
      _lastAdaptiveRefreshIndex = -1;
      _reportMenuVisible = false;
    });
  }

  Future<void> _checkProximityAndPinEta(Position position) async {
    final trip = _trip;
    if (trip == null || _routeEdges.isEmpty) return;
    _proximityChecked = true;

    final originStop = _stopsById[trip.originStopId];
    if (originStop == null) return;

    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      originStop.latitude,
      originStop.longitude,
    );

    if (distance > 100) {
      final walkMinutes = (distance / 80).round().clamp(1, 30);
      if (walkMinutes != _walkMinutesToOrigin) {
        setState(() => _walkMinutesToOrigin = walkMinutes);
      }
      _proximityChecked = false;
      return;
    }

    var totalMinutes = 0;
    for (final edge in _routeEdges) {
      final level = _crowdByStopId[edge.toStopId.trim().toUpperCase()] ?? 2;
      final etaMultiplier = _fallbackEtaMultiplier(level);
      final movementMinutes = math.max(
        edge.travelMinutes,
        (edge.travelMinutes * etaMultiplier).round(),
      );
      final waitMinutes = edge.connectionType.toLowerCase().contains('transfer')
          ? _fallbackWaitMinutes(level)
          : 0;
      totalMinutes += movementMinutes + waitMinutes;
    }

    final arrivalTime = DateTime.now().add(Duration(minutes: totalMinutes));
    ActiveTripService.instance.pinEta(
      remainingMinutes: totalMinutes,
      arrivalTime: arrivalTime,
    );
    if (!mounted) return;
    setState(() => _etaPinned = true);
  }

  Future<void> _checkInactivity(Position position) async {
    if (position.accuracy > 100) return;
    final now = DateTime.now();

    final record = _lastMovement;
    if (record == null) {
      _lastMovement = _PositionRecord(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: now,
      );
      return;
    }

    final distance = record.distanceTo(position.latitude, position.longitude);
    if (distance > 20) {
      _lastMovement = _PositionRecord(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: now,
      );
      return;
    }

    final idleMinutes = now.difference(record.timestamp).inMinutes;
    if (idleMinutes < 30) return;

    _inactivityDialogOpen = true;
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.help_outline_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 10),
              Text('Are you okay?'),
            ],
          ),
          content: const Text(
            'You haven\'t moved in a while. Is everything alright?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('fine'),
              child: const Text(
                'I\'m fine',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('emergency'),
              child: Text(
                'Call emergency contact',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.red[700],
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text(
                'Cancel trip',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    _inactivityDialogOpen = false;

    switch (action) {
      case 'fine':
        _lastMovement = _PositionRecord(
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
        );
      case 'emergency':
        _showTrackMessage('Emergency contact dialer would open here.');
        _lastMovement = _PositionRecord(
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: DateTime.now(),
        );
      case 'cancel':
        unawaited(_cancelTrip());
    }
  }

  Future<bool> _checkOffRoute(
    double latitude,
    double longitude,
    double bestRouteDistance,
  ) async {
    if (_isRerouting) return false;
    final now = DateTime.now();
    if (_lastRerouteTime != null &&
        now.difference(_lastRerouteTime!) < const Duration(seconds: 30)) {
      return false;
    }

    if (bestRouteDistance <= 500) return false;

    _StopNode? globalNearest;
    var globalBest = double.infinity;
    for (final stop in _stopsById.values) {
      final d = Geolocator.distanceBetween(
        latitude, longitude, stop.latitude, stop.longitude,
      );
      if (d < globalBest) {
        globalBest = d;
        globalNearest = stop;
      }
    }

    if (globalNearest == null || globalBest > 500) return false;

    final nearest = globalNearest;
    final onRoute = _routeStops.any(
      (s) => s.stopId == nearest.stopId,
    );

    if (!onRoute && globalBest < bestRouteDistance * 0.7) {
      await _rerouteFromCurrentPosition(nearest);
      return true;
    }
    return false;
  }

  Future<void> _rerouteFromCurrentPosition(_StopNode currentStop) async {
    final trip = _trip;
    if (trip == null || _isRerouting) return;
    setState(() => _isRerouting = true);

    try {
      final result = _bestPathToStops(
        originStopId: currentStop.stopId,
        destinationStopIds: <String>[trip.destinationStopId],
        preferComfort: trip.routePreference == 'comfort',
      );
      if (result == null) return;

      await _applyResolvedTrip(baseTrip: trip, result: result);
      await _refreshAdaptiveForecasts(force: true);

      _rerouteCount++;
      _lastRerouteTime = DateTime.now();

      if (!mounted) return;
      setState(() {
        _nearestIndex = 0;
        _sentNotificationKeys.clear();
      });

      _showTrackMessage('Route recalculated');

      if (_rerouteCount >= 3) {
        await _showReroutePrompt();
      }
    } finally {
      if (mounted) setState(() => _isRerouting = false);
    }
  }

  Future<void> _showReroutePrompt() async {
    final trip = _trip;
    if (trip == null) return;

    final option = await showModalBottomSheet<_TrackStationOption>(
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
                const Row(
                  children: [
                    Icon(Icons.alt_route_rounded, color: Color(0xFFDC2626)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You\'ve deviated from your route a few times.',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Would you like to pick a new destination instead?',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Continue to current destination'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(null);
                      _changeDestinationFromCurrentStation();
                    },
                    child: const Text('Choose a new destination'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (option != null) {
      _rerouteCount = 0;
    }
  }

  int get _resolvedCurrentIndex {
    if (_routeStops.isEmpty) return 0;
    if (_nearestIndex < 0) return 0;
    if (_nearestIndex >= _routeStops.length) return _routeStops.length - 1;
    return _nearestIndex;
  }

  int get _remainingStops {
    if (_routeStops.isEmpty) return 0;
    return math.max(_routeStops.length - _resolvedCurrentIndex - 1, 0);
  }

  int? get _remainingMinutes {
    if (_etaPinned) {
      final pinned = ActiveTripService.instance.pinnedArrivalTime.value;
      if (pinned != null) {
        return pinned.difference(DateTime.now()).inMinutes.clamp(0, 9999);
      }
    }
    final walk = _etaPinned ? 0 : _walkMinutesToOrigin;
    final adaptive = _adaptiveRemainingMinutes;
    if (adaptive != null) return adaptive + walk;
    if (_routeEdges.isEmpty) return (_estimatedTotalMinutes ?? 0) + walk;
    if (_resolvedCurrentIndex >= _routeEdges.length) return walk;
    return walk + _routeEdges
        .skip(_resolvedCurrentIndex)
        .fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
  }

  DateTime? get _estimatedArrivalTime {
    if (_arrived) return DateTime.now();
    if (_etaPinned) {
      final pinned = ActiveTripService.instance.pinnedArrivalTime.value;
      if (pinned != null) return pinned;
    }
    if (_adaptiveArrivalTime != null) return _adaptiveArrivalTime;
    final remainingMinutes = _remainingMinutes;
    if (remainingMinutes == null) return null;
    return DateTime.now().add(
      Duration(minutes: remainingMinutes < 0 ? 0 : remainingMinutes),
    );
  }

  int get _displayHighestCrowdLevel {
    if (_adaptiveHighestCrowdLevel > 0) return _adaptiveHighestCrowdLevel;
    return _trip?.highestCrowdLevel ?? 0;
  }

  int? get _etaDriftMinutes {
    if (_etaPinned) {
      final pinned = ActiveTripService.instance.pinnedRemainingMinutes.value;
      if (pinned == null || _routeEdges.isEmpty) return null;
      final base = _resolvedCurrentIndex >= _routeEdges.length
          ? 0
          : _routeEdges
              .skip(_resolvedCurrentIndex)
              .fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
      return pinned - base;
    }
    final adaptive = _adaptiveRemainingMinutes;
    if (adaptive == null || _routeEdges.isEmpty) return null;
    final base = _resolvedCurrentIndex >= _routeEdges.length
        ? 0
        : _routeEdges
            .skip(_resolvedCurrentIndex)
            .fold<int>(0, (sum, edge) => sum + edge.travelMinutes);
    return adaptive - base;
  }

  int? _crowdLevelForTimelineItem(_TrackTimelineItem item) {
    final primaryKey = item.primaryStop.stopId.trim().toUpperCase();
    final secondaryKey = item.secondaryStop?.stopId.trim().toUpperCase();
    final levels = <int>[
      _adaptiveForecastByStopId[primaryKey]?.occupancyLevel ??
          _crowdByStopId[primaryKey] ??
          0,
      if (secondaryKey != null)
        _adaptiveForecastByStopId[secondaryKey]?.occupancyLevel ??
            _crowdByStopId[secondaryKey] ??
            0,
    ]..removeWhere((level) => level <= 0);
    if (levels.isEmpty) return null;
    return levels.reduce(math.max);
  }

  List<_TrackTimelineItem> _buildTimelineItems() {
    final items = <_TrackTimelineItem>[];
    var index = 0;
    while (index < _routeStops.length) {
      final stop = _routeStops[index];
      final nextStop =
          index + 1 < _routeStops.length ? _routeStops[index + 1] : null;
      final previousRouteId = index > 0 ? _routeStops[index - 1].routeId : null;
      final canMergeInterchange = nextStop != null &&
          stop.stopName.toUpperCase() == nextStop.stopName.toUpperCase() &&
          stop.routeId != nextStop.routeId;

      if (canMergeInterchange) {
        items.add(
          _TrackTimelineItem(
            primaryStop: stop,
            secondaryStop: nextStop,
            startIndex: index,
            endIndex: index + 1,
            previousRouteId: previousRouteId,
            isFirst: index == 0,
            isLast: index + 1 == _routeStops.length - 1,
          ),
        );
        index += 2;
        continue;
      }

      items.add(
        _TrackTimelineItem(
          primaryStop: stop,
          secondaryStop: null,
          startIndex: index,
          endIndex: index,
          previousRouteId: previousRouteId,
          isFirst: index == 0,
          isLast: index == _routeStops.length - 1,
        ),
      );
      index += 1;
    }
    return items;
  }

  _TrackStopStatus _statusForTimelineItem(_TrackTimelineItem item) {
    if (item.endIndex < _resolvedCurrentIndex) {
      return _TrackStopStatus.passed;
    }
    if (item.startIndex > _resolvedCurrentIndex) {
      return _TrackStopStatus.upcoming;
    }
    return _TrackStopStatus.current;
  }

  double get _progressValue {
    if (_routeStops.length <= 1) return 0;
    final value = _resolvedCurrentIndex / (_routeStops.length - 1);
    return value.clamp(0.0, 1.0).toDouble();
  }

  String get _currentStationName {
    if (_routeStops.isEmpty) return 'Locating train';
    return _routeStops[_resolvedCurrentIndex].stopName;
  }

  void _openReportMenu() {
    if (_reportMenuVisible) return;
    setState(() => _reportMenuVisible = true);
    _reportRevealController.forward(from: 0);
  }

  void _closeReportMenu() {
    if (!_reportMenuVisible) return;
    _reportRevealController.reverse().whenComplete(() {
      if (!mounted) return;
      setState(() => _reportMenuVisible = false);
    });
  }

  Future<void> _submitRouteReport({
    required _RouteReportType type,
  }) async {
    if (_isSubmittingReport || _routeStops.isEmpty) return;
    final stopId = _routeStops[_resolvedCurrentIndex].stopId;
    setState(() => _isSubmittingReport = true);
    try {
      if (type == _RouteReportType.crowd) {
        await _crowdReportsService.insertUserCrowdReport(
          stopId: stopId,
          occupancyLevel: 5,
          latitude: _lastMovement?.latitude,
          longitude: _lastMovement?.longitude,
        );
        _crowdsReported++;
        if (_etaPinned) {
          ActiveTripService.instance.extendPinnedEta(3);
        }
      } else {
        await _crowdReportsService.insertUserDelayReport(stopId: stopId);
        _delaysReported++;
        if (_etaPinned) {
          ActiveTripService.instance.extendPinnedEta(5);
        }
      }
      if (!mounted) return;
      _closeReportMenu();
      await _refreshAdaptiveForecasts(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == _RouteReportType.crowd
                ? 'Crowded train reported for $stopId.'
                : 'Delay reported for $stopId.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not submit report: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmittingReport = false);
      }
    }
  }

  Future<void> _cancelTrip() async {
    setState(() => _cancelTripPromptOpen = true);
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Cancel active trip?'),
            content: const Text(
              'This will stop live tracking and clear the saved route.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Keep Trip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Cancel Trip'),
              ),
            ],
          );
        },
      );
      if (confirm != true) return;

      _pollTimer?.cancel();
      await _notificationService.cancelAllNotifications();
      ActiveTripService.instance.clearPinnedEta();
      await _tripService.clearTrip();
      if (!mounted) return;
      setState(() {
        _trip = null;
        _routeStops = <_StopNode>[];
        _routeEdges = <_RouteConnection>[];
        _adaptiveForecastByStopId = <String, StopCrowdForecast>{};
        _nearestIndex = -1;
        _arrived = false;
        _estimatedTotalMinutes = null;
        _adaptiveRemainingMinutes = null;
        _adaptiveArrivalTime = null;
        _adaptiveHighestCrowdLevel = 0;
        _etaPinned = false;
        _walkMinutesToOrigin = 0;
        _delaysReported = 0;
        _crowdsReported = 0;
        _weatherAtStart = null;
        _proximityChecked = false;
        _lastMovement = null;
        _inactivityDialogOpen = false;
        _lastAdaptiveRefreshAt = null;
        _lastAdaptiveRefreshIndex = -1;
        _reportMenuVisible = false;
      });
      NavigationState.instance.goTo(0);
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } finally {
      if (mounted) {
        setState(() => _cancelTripPromptOpen = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.route_rounded,
          leadingText: 'Trip',
          accentText: 'Motion',
          badge: ConnectionStatusBadge(),
          subtitle: 'Tracking',
        ),
      ),
      body: trip == null && !OperatingHoursService.isAnyLineRunning()
              ? _buildSleepingTrain()
              : trip == null
                  ? _EmptyTrackState(
                  controller: _emptyTripSearchController,
                  stationOptions: _stationOptions,
                  closedByStopId: _closedByStopId,
                  isSearching: _isCreatingTrip,
                  onOptionSelected: (option) {
                    _pendingSearchOption = option;
                    _emptyTripSearchController.text = option.stationName;
                  },
                  onSearch: () {
                    final query =
                        _emptyTripSearchController.text.trim().toLowerCase();
                    _TrackStationOption? selected = _pendingSearchOption;
                    selected ??=
                        _stationOptions.cast<_TrackStationOption?>().firstWhere(
                              (option) =>
                                  option != null &&
                                  option.stationName.toLowerCase() == query,
                              orElse: () => null,
                            );
                    if (selected == null) {
                      _showTrackMessage(
                          'Pick a station from the search results.');
                      return;
                    }
                    if (_isStationOptionClosed(selected)) {
                      _showTrackMessage(
                        '${selected.stationName} is unavailable during closing hours.',
                      );
                      return;
                    }
                    unawaited(_startTripFromSearch(selected));
                  },
                  onPlanAhead: () {
                    unawaited(_showScheduleAheadSheet());
                  },
                )
              : _buildTrackingBody(trip),
    );
  }

  Widget _buildSleepingTrain() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bedtime_rounded, size: 64, color: Color(0xFF9E9E9E)),
            const SizedBox(height: 16),
            Text(
              'System Unavailable',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'All trains have stopped for the night.\n'
              'Service resumes at '
              '${OperatingHoursService.formatTime(OperatingHoursService.nextOpeningTime() ?? DateTime.now())}.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingBody(ActiveTrip trip) {
    final timelineItems = _routeStops.isEmpty ? null : _buildTimelineItems();
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ValueListenableBuilder<DateTime?>(
                valueListenable: ActiveTripService.instance.pinnedArrivalTime,
                builder: (_, pinned, __) {
                  final liveRemaining = pinned != null && _etaPinned
                      ? pinned.difference(DateTime.now()).inMinutes.clamp(0, 9999)
                      : _remainingMinutes;
                  return _TrackHeader(
                    trip: trip,
                    arrived: _arrived,
                    estimatedMinutes: liveRemaining,
                    estimatedArrivalTime: _estimatedArrivalTime,
                    highestCrowdLevel: _displayHighestCrowdLevel,
                    progress: _progressValue,
                    currentStationName: _currentStationName,
                    onChangeDestination:
                        _changeDestinationFromCurrentStation,
                    remainingStops: _remainingStops,
                    originRouteId: _routeStops.isEmpty
                        ? normalizeRouteId(
                            _inferRouteIdFromStopId(
                                trip.originStopId),
                          )
                        : _routeStops.first.routeId,
                    destinationRouteId: _routeStops.isEmpty
                        ? normalizeRouteId(
                            _inferRouteIdFromStopId(
                              trip.destinationStopId,
                            ),
                          )
                        : _routeStops.last.routeId,
                  );
                },
              ),
              const SizedBox(height: 16),
              Expanded(
                child: timelineItems == null
                    ? const Center(
                        child: Text(
                          'Preparing route timeline...',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : RepaintBoundary(
                        child: AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, _) {
                            final flashValue = Curves.easeInOut
                                .transform(_pulseController.value);
                            return ListView.separated(
                              padding: const EdgeInsets.only(bottom: 8),
                              itemCount: timelineItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 0),
                              itemBuilder: (context, index) {
                                final item = timelineItems[index];
                                return RepaintBoundary(
                                  child: _TrackStopTile(
                                    item: item,
                                    status: _statusForTimelineItem(item),
                                    flashValue: flashValue,
                                    crowdLevel:
                                        _crowdLevelForTimelineItem(item),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
        if (_reportMenuVisible)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeReportMenu,
              behavior: HitTestBehavior.translucent,
            ),
          ),
        Positioned(
          right: 16,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RouteReportMenu(
                controller: _reportRevealController,
                visible: _reportMenuVisible,
                onCrowdReport: _isSubmittingReport
                    ? null
                    : () => _submitRouteReport(
                          type: _RouteReportType.crowd,
                        ),
                onDelayReport: _isSubmittingReport
                    ? null
                    : () => _submitRouteReport(
                          type: _RouteReportType.delay,
                        ),
              ),
              if (_reportMenuVisible)
                const SizedBox(height: 10),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionPillButton(
                    icon: Icons.close_rounded,
                    label: 'Cancel Trip',
                    onPressed: _cancelTrip,
                    baseBackgroundColor:
                        Theme.of(context).cardColor,
                    hoverBackgroundColor:
                        const Color(0xFFDC2626),
                    baseForegroundColor:
                        Theme.of(context).colorScheme.error,
                    hoverForegroundColor: Colors.white,
                    borderColor: const Color(0xFFF1B5B8),
                    colorOnHover: false,
                    forceActive: _cancelTripPromptOpen,
                  ),
                  const SizedBox(width: 12),
                  _ActionPillButton(
                    icon: Icons.campaign_rounded,
                    label: _isSubmittingReport
                        ? 'Sending...'
                        : 'Report',
                    onPressed: _isSubmittingReport
                        ? null
                        : _openReportMenu,
                    baseBackgroundColor:
                        Theme.of(context).cardColor,
                    hoverBackgroundColor:
                        const Color(0xFF0A3A8B),
                    baseForegroundColor:
                        const Color(0xFF0A3A8B),
                    hoverForegroundColor: Colors.white,
                    borderColor: const Color(0xFFDCE6F5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegacyTrackHeader extends StatelessWidget {
  final ActiveTrip trip;
  final double? distanceToDestination;
  final bool arrived;
  final int? estimatedTotalMinutes;
  final double progress;

  const _LegacyTrackHeader({
    required this.trip,
    required this.distanceToDestination,
    required this.arrived,
    required this.estimatedTotalMinutes,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final crowdLabel = _crowdLabel(trip.highestCrowdLevel);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${trip.originName} -> ${trip.destinationName}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                arrived ? Icons.check_circle_rounded : Icons.train_rounded,
                color:
                    arrived ? const Color(0xFF16A34A) : const Color(0xFF0A3A8B),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeaderChip(
                label: trip.routePreference == 'comfort'
                    ? 'Comfort route'
                    : 'Efficiency route',
              ),
              _HeaderChip(label: 'Crowd: $crowdLabel'),
              _HeaderChip(
                label: distanceToDestination == null
                    ? 'Locating train path'
                    : 'Remaining: ${_formatMeters(distanceToDestination!)}',
              ),
              _HeaderChip(
                label: estimatedTotalMinutes == null
                    ? 'Calculating ETA'
                    : 'Journey: ${_formatDuration(estimatedTotalMinutes!)}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: const Color(0xFFD9E4F5),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF0A3A8B),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(progress * 100).round()}% completed',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _crowdLabel(int level) {
    return crowdLevelLabel(level);
  }

  static String _formatDuration(int minutes) {
    final safe = minutes < 0 ? 0 : minutes;
    final hours = safe ~/ 60;
    final mins = safe % 60;
    if (hours <= 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;

  const _HeaderChip({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF0A3A8B),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _TrackStopStatus {
  passed,
  current,
  upcoming,
}

class _LegacyTrackStopTile extends StatelessWidget {
  final _StopNode stop;
  final _TrackStopStatus status;
  final bool showTransfer;
  final String? previousRouteId;
  final int? crowdLevel;

  const _LegacyTrackStopTile({
    required this.stop,
    required this.status,
    required this.showTransfer,
    required this.previousRouteId,
    required this.crowdLevel,
  });

  @override
  Widget build(BuildContext context) {
    final routeColor = getRouteColor(stop.routeId);
    final lineOpacity = status == _TrackStopStatus.passed ? 0.35 : 1.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (showTransfer)
                  Container(
                    width: 4,
                    height: 18,
                    color: getRouteColor(previousRouteId ?? stop.routeId),
                  )
                else
                  Container(
                    width: 4,
                    height: 18,
                    color: routeColor.withValues(alpha: lineOpacity),
                  ),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: routeColor.withValues(
                      alpha: status == _TrackStopStatus.passed ? 0.45 : 1,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
                Container(
                  width: 4,
                  height: 32,
                  color: routeColor.withValues(alpha: lineOpacity),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE3EAF7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showTransfer)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'Change to ${stop.routeId}',
                        style: TextStyle(
                          color: routeColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          stop.stopName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (crowdLevel != null)
                        Text(
                          _TrackHeader._crowdLabel(crowdLevel!),
                          style: TextStyle(
                            color: _crowdColor(crowdLevel!),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stop.stopId} • ${stop.routeId}',
                    style: const TextStyle(
                      color: Color(0xFF667085),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            switch (status) {
              _TrackStopStatus.passed => Icons.check_circle_rounded,
              _TrackStopStatus.current => Icons.my_location_rounded,
              _TrackStopStatus.upcoming => Icons.radio_button_unchecked_rounded,
            },
            color: switch (status) {
              _TrackStopStatus.passed => const Color(0xFF16A34A),
              _TrackStopStatus.current => const Color(0xFF0A3A8B),
              _TrackStopStatus.upcoming => const Color(0xFF98A2B3),
            },
          ),
        ],
      ),
    );
  }

  static Color _crowdColor(int level) {
    return crowdLevelColor(level);
  }
}

class _TrackHeader extends StatelessWidget {
  final ActiveTrip trip;
  final bool arrived;
  final int? estimatedMinutes;
  final DateTime? estimatedArrivalTime;
  final int highestCrowdLevel;
  final int remainingStops;
  final double progress;
  final String currentStationName;
  final VoidCallback onChangeDestination;
  final String originRouteId;
  final String destinationRouteId;

  const _TrackHeader({
    required this.trip,
    required this.arrived,
    required this.estimatedMinutes,
    required this.estimatedArrivalTime,
    required this.highestCrowdLevel,
    required this.remainingStops,
    required this.progress,
    required this.currentStationName,
    required this.onChangeDestination,
    required this.originRouteId,
    required this.destinationRouteId,
  });

  @override
  Widget build(BuildContext context) {
    final crowdLabel = _crowdLabel(highestCrowdLevel);
    final crowdColor = crowdLevelColor(highestCrowdLevel);
    final localizations = MaterialLocalizations.of(context);
    final durationLabel = switch (estimatedMinutes) {
      null => 'syncing',
      final value => _formatDuration(value),
    };
    final arrivalLabel = arrived
        ? 'Arrived'
        : estimatedArrivalTime == null
            ? 'syncing'
            : localizations.formatTimeOfDay(TimeOfDay.fromDateTime(estimatedArrivalTime!));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                child: _RouteStationPill(
                  stationName: trip.originName,
                  routeId: originRouteId,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Color(0xFF98A2B3),
                  size: 14,
                ),
              ),
              Flexible(
                child: _RouteStationPill(
                  stationName: trip.destinationName,
                  routeId: destinationRouteId,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: crowdColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  crowdLabel,
                  style: TextStyle(
                    color: crowdColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.my_location_rounded,
                  size: 16,
                  color: getRouteColor(destinationRouteId),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    currentStationName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$remainingStops stops',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _InfoBlock(
                label: 'Time left',
                value: durationLabel,
              ),
              const SizedBox(width: 8),
              _InfoBlock(
                label: 'Arrive by',
                value: arrivalLabel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          _JourneyProgressBar(progress: progress),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                arrived
                    ? 'Arrived'
                    : '${(progress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF475467),
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: onChangeDestination,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0A3A8B),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Change destination', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _crowdLabel(int level) {
    return crowdLevelLabel(level);
  }

  static String _formatDuration(int minutes) {
    final safe = minutes < 0 ? 0 : minutes;
    final hours = safe ~/ 60;
    final mins = safe % 60;
    if (hours <= 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

class _InfoBlock extends StatelessWidget {
  final String label;
  final String value;

  const _InfoBlock({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7FB),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Color(0xFF98A2B3),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF344054),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyProgressBar extends StatelessWidget {
  final double progress;

  const _JourneyProgressBar({
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxLeft = math.max(constraints.maxWidth - 30, 0.0);
          final iconLeft = (maxLeft * progress).clamp(0.0, maxLeft).toDouble();
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9E4F5),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A3A8B),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                left: iconLeft,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xFF0A3A8B), width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F0A3A8B),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.train_rounded,
                    size: 16,
                    color: Color(0xFF0A3A8B),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RouteStationPill extends StatelessWidget {
  final String stationName;
  final String routeId;

  const _RouteStationPill({
    required this.stationName,
    required this.routeId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: getRouteColor(routeId),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        stationName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: getRouteOnColor(routeId),
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _TrackStopTile extends StatelessWidget {
  final _TrackTimelineItem item;
  final _TrackStopStatus status;
  final double flashValue;
  final int? crowdLevel;

  const _TrackStopTile({
    required this.item,
    required this.status,
    required this.flashValue,
    required this.crowdLevel,
  });

  @override
  Widget build(BuildContext context) {
    final stop = item.primaryStop;
    final secondaryStop = item.secondaryStop;
    final isInterchange = secondaryStop != null;
    final routeColor = getRouteColor(stop.routeId);
    final secondaryRouteColor = secondaryStop == null
        ? routeColor
        : getRouteColor(secondaryStop.routeId);
    final isCurrent = status == _TrackStopStatus.current;
    final isPassed = status == _TrackStopStatus.passed;
    final topConnectorVisible = !item.isFirst;
    final bottomConnectorVisible = !item.isLast;
    final connectorColor = isPassed ? const Color(0xFFBFC6D4) : routeColor;
    final secondaryConnectorColor =
        isPassed ? const Color(0xFFBFC6D4) : secondaryRouteColor;
    final cardColor = isPassed
        ? const Color(0xFFF4F5F7)
        : isCurrent
            ? Color.lerp(
                const Color(0xFFFFF4B8),
                const Color(0xFFFFE36E),
                flashValue,
              )!
            : Colors.white;
    final borderColor = isPassed
        ? const Color(0xFFE4E7EC)
        : isCurrent
            ? const Color(0xFFFACC15)
            : const Color(0xFFE3EAF7);
    final titleColor = isPassed
        ? const Color(0xFF98A2B3)
        : isInterchange
            ? const Color(0xFF344054)
            : routeColor;
    final metaColor =
        isPassed ? const Color(0xFF98A2B3) : const Color(0xFF667085);
    final crowdColor = crowdLevel == null
        ? const Color(0xFF667085)
        : crowdLevelColor(crowdLevel!);
    final crowdLabel = crowdLevel == null ? null : crowdLevelLabel(crowdLevel!);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (topConnectorVisible)
                  Expanded(
                    child: Container(
                      width: 4,
                      color: connectorColor
                          .withValues(alpha: isPassed ? 0.45 : 1),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                _TrackStationMarker(
                  primaryColor:
                      connectorColor.withValues(alpha: isPassed ? 0.75 : 1),
                  secondaryColor: secondaryConnectorColor.withValues(
                    alpha: isPassed ? 0.75 : 1,
                  ),
                  split: isInterchange,
                  flashValue: flashValue,
                  highlight: isCurrent,
                ),
                if (bottomConnectorVisible)
                  Expanded(
                    child: Container(
                      width: 4,
                      color: (isInterchange
                              ? secondaryConnectorColor
                              : connectorColor)
                          .withValues(alpha: isPassed ? 0.45 : 1),
                    ),
                  )
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: borderColor, width: isCurrent ? 1.4 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isInterchange)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'Change to ${secondaryStop.routeId}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPassed
                              ? const Color(0xFF98A2B3)
                              : secondaryRouteColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (item.isFirst || item.isLast)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (item.isFirst)
                            const _TrackTimelineFlag(
                              label: 'Start station',
                              color: Color(0xFF0A3A8B),
                              backgroundColor: Color(0xFFEEF4FF),
                            ),
                          if (item.isLast)
                            const _TrackTimelineFlag(
                              label: 'End station',
                              color: Color(0xFFB42318),
                              backgroundColor: Color(0xFFFEF3F2),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: isInterchange && !isPassed
                            ? _TrackSplitRouteText(
                                text: stop.stopName,
                                primaryColor: routeColor,
                                secondaryColor: secondaryRouteColor,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              )
                            : Text(
                                stop.stopName,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                  color: titleColor,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${stop.stopId} • ${stop.routeId}',
                    style: TextStyle(
                      fontSize: 11,
                      color: metaColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (crowdLabel != null) ...[
                    const SizedBox(height: 4),
                    _TrackTimelineFlag(
                      label: 'Forecast: $crowdLabel',
                      color: crowdColor,
                      backgroundColor: crowdColor.withValues(alpha: 0.10),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            switch (status) {
              _TrackStopStatus.passed => Icons.check_circle_rounded,
              _TrackStopStatus.current => Icons.my_location_rounded,
              _TrackStopStatus.upcoming => Icons.radio_button_unchecked_rounded,
            },
            color: switch (status) {
              _TrackStopStatus.passed => const Color(0xFF98A2B3),
              _TrackStopStatus.current => const Color(0xFFF59E0B),
              _TrackStopStatus.upcoming => const Color(0xFF98A2B3),
            },
          ),
        ],
      ),
    );
  }
}

class _TrackSplitRouteText extends StatelessWidget {
  final String text;
  final Color primaryColor;
  final Color secondaryColor;
  final TextStyle style;

  const _TrackSplitRouteText({
    required this.text,
    required this.primaryColor,
    required this.secondaryColor,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final rect = bounds.isEmpty ? const Rect.fromLTWH(0, 0, 1, 1) : bounds;
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            primaryColor,
            secondaryColor,
            secondaryColor,
          ],
          stops: const [0, 0.46, 0.54, 1],
        ).createShader(rect);
      },
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}

class _TrackTimelineItem {
  final _StopNode primaryStop;
  final _StopNode? secondaryStop;
  final int startIndex;
  final int endIndex;
  final String? previousRouteId;
  final bool isFirst;
  final bool isLast;

  const _TrackTimelineItem({
    required this.primaryStop,
    required this.secondaryStop,
    required this.startIndex,
    required this.endIndex,
    required this.previousRouteId,
    required this.isFirst,
    required this.isLast,
  });
}

class _TrackTimelineFlag extends StatelessWidget {
  final String label;
  final Color color;
  final Color backgroundColor;

  const _TrackTimelineFlag({
    required this.label,
    required this.color,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TrackStationMarker extends StatelessWidget {
  final Color primaryColor;
  final Color secondaryColor;
  final bool split;
  final double flashValue;
  final bool highlight;

  const _TrackStationMarker({
    required this.primaryColor,
    required this.secondaryColor,
    required this.split,
    required this.flashValue,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: const Color(0x55FACC15),
                  blurRadius: 12 + (flashValue * 6),
                  spreadRadius: 1.5,
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: _TrackStationMarkerPainter(
            primaryColor: primaryColor,
            secondaryColor: secondaryColor,
            split: split,
          ),
        ),
      ),
    );
  }
}

class _TrackStationMarkerPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;
  final bool split;

  const _TrackStationMarkerPainter({
    required this.primaryColor,
    required this.secondaryColor,
    required this.split,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.fill;
    if (!split) {
      paint.color = primaryColor;
      canvas.drawOval(rect, paint);
      return;
    }

    paint.color = primaryColor;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(0, size.height)
        ..close(),
      paint,
    );

    paint.color = secondaryColor;
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TrackStationMarkerPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.split != split;
  }
}

enum _RouteReportType {
  crowd,
  delay,
}

class _RouteReportMenu extends StatelessWidget {
  final AnimationController controller;
  final bool visible;
  final VoidCallback? onCrowdReport;
  final VoidCallback? onDelayReport;

  const _RouteReportMenu({
    required this.controller,
    required this.visible,
    required this.onCrowdReport,
    required this.onDelayReport,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible && controller.isDismissed) {
      return const SizedBox.shrink();
    }
    return FadeTransition(
      opacity: CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ReportBubbleButton(
            animation: CurvedAnimation(
              parent: controller,
              curve: const Interval(0.0, 1.0, curve: Curves.easeOutBack),
            ),
            icon: Icons.groups_rounded,
            tooltip: 'Crowded train',
            onPressed: onCrowdReport,
          ),
          const SizedBox(height: 10),
          _ReportBubbleButton(
            animation: CurvedAnimation(
              parent: controller,
              curve: const Interval(0.12, 1.0, curve: Curves.easeOutBack),
            ),
            icon: Icons.schedule_rounded,
            tooltip: 'Delay',
            onPressed: onDelayReport,
          ),
        ],
      ),
    );
  }
}

class _ReportBubbleButton extends StatefulWidget {
  final Animation<double> animation;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ReportBubbleButton({
    required this.animation,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_ReportBubbleButton> createState() => _ReportBubbleButtonState();
}

class _ReportBubbleButtonState extends State<_ReportBubbleButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _pressed
        ? const Color(0xFFDC2626)
        : _hovered
            ? const Color(0xFFFACC15)
            : Theme.of(context).cardColor;
    final foregroundColor = _pressed
        ? Colors.white
        : _hovered
            ? const Color(0xFF713F12)
            : const Color(0xFF0A3A8B);
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.2, 0.25),
        end: Offset.zero,
      ).animate(widget.animation),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1).animate(widget.animation),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() {
            _hovered = false;
            _pressed = false;
          }),
          child: Tooltip(
            message: widget.tooltip,
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTapDown: widget.onPressed == null
                    ? null
                    : (_) => setState(() => _pressed = true),
                onTapUp: widget.onPressed == null
                    ? null
                    : (_) => setState(() => _pressed = false),
                onTapCancel: widget.onPressed == null
                    ? null
                    : () => setState(() => _pressed = false),
                child: InkWell(
                  onTap: widget.onPressed,
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 120),
                    scale: _pressed ? 1.08 : (_hovered ? 1.03 : 1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _pressed
                              ? const Color(0xFFB91C1C)
                              : _hovered
                                  ? const Color(0xFFEAB308)
                                  : const Color(0xFFDCE6F5),
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A101828),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        color: foregroundColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color baseBackgroundColor;
  final Color hoverBackgroundColor;
  final Color baseForegroundColor;
  final Color hoverForegroundColor;
  final Color borderColor;
  final bool colorOnHover;
  final bool forceActive;

  const _ActionPillButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.baseBackgroundColor,
    required this.hoverBackgroundColor,
    required this.baseForegroundColor,
    required this.hoverForegroundColor,
    required this.borderColor,
    this.colorOnHover = true,
    this.forceActive = false,
  });

  @override
  State<_ActionPillButton> createState() => _ActionPillButtonState();
}

class _ActionPillButtonState extends State<_ActionPillButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active =
        widget.forceActive || _pressed || (widget.colorOnHover && _hovered);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: widget.onPressed == null
            ? null
            : (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _pressed ? 0.96 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active
                      ? widget.hoverBackgroundColor
                      : widget.baseBackgroundColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: widget.borderColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.icon,
                      size: 16,
                      color: active
                          ? widget.hoverForegroundColor
                          : widget.baseForegroundColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: active
                            ? widget.hoverForegroundColor
                            : widget.baseForegroundColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HoldActionPillButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onHoldComplete;
  final bool enabled;

  const _HoldActionPillButton({
    required this.icon,
    required this.label,
    required this.onHoldComplete,
    required this.enabled,
  });

  @override
  State<_HoldActionPillButton> createState() => _HoldActionPillButtonState();
}

class _HoldActionPillButtonState extends State<_HoldActionPillButton> {
  Timer? _holdTimer;
  bool _hovered = false;
  bool _pressed = false;

  void _startHold() {
    if (!widget.enabled || widget.onHoldComplete == null) return;
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 260), () {
      widget.onHoldComplete?.call();
      if (mounted) {
        setState(() => _pressed = false);
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (mounted) {
      setState(() => _pressed = false);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: widget.enabled
            ? (_) {
                setState(() => _pressed = true);
                _startHold();
              }
            : null,
        onTapUp: (_) => _cancelHold(),
        onTapCancel: _cancelHold,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 120),
          scale: _pressed ? 0.96 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF0A3A8B)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFDCE6F5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A101828),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  color: active ? Colors.white : const Color(0xFF0A3A8B),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF0A3A8B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTrackState extends StatelessWidget {
  final TextEditingController controller;
  final List<_TrackStationOption> stationOptions;
  final Map<String, bool> closedByStopId;
  final bool isSearching;
  final ValueChanged<_TrackStationOption> onOptionSelected;
  final VoidCallback onSearch;
  final VoidCallback onPlanAhead;

  const _EmptyTrackState({
    required this.controller,
    required this.stationOptions,
    required this.closedByStopId,
    required this.isSearching,
    required this.onOptionSelected,
    required this.onSearch,
    required this.onPlanAhead,
  });

  bool _isClosed(_TrackStationOption option) {
    for (final stopId in option.stopIds) {
      if (closedByStopId[stopId.trim().toUpperCase()] ?? false) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFDCE6F5)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12101828),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.route_rounded,
                      size: 30,
                      color: Color(0xFF0A3A8B),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No active trip yet.',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Search for a destination here and start tracking straight from the track page.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 18),
                Autocomplete<_TrackStationOption>(
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return const Iterable<_TrackStationOption>.empty();
                    }
                    return stationOptions.where((station) {
                      final inName =
                          station.stationName.toLowerCase().contains(query);
                      final inCode = station.stopIds.any(
                        (code) => code.toLowerCase().contains(query),
                      );
                      final inRoute = station.routeIds.any(
                        (routeId) => routeId.toLowerCase().contains(query),
                      );
                      return inName || inCode || inRoute;
                    }).take(12);
                  },
                  displayStringForOption: (option) => option.stationName,
                  onSelected: onOptionSelected,
                  fieldViewBuilder:
                      (context, textController, focusNode, onFieldSubmitted) {
                    if (textController.text != controller.text) {
                      textController.value = controller.value;
                    }
                    return TextField(
                      controller: textController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Search train station',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => controller.value = textController.value,
                      onSubmitted: (_) => onSearch(),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final optionList = options.toList();
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: math.min(
                            MediaQuery.sizeOf(context).width - 48,
                            430,
                          ),
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFDCE6F5)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x14101828),
                                blurRadius: 12,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            shrinkWrap: true,
                            itemCount: optionList.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, thickness: 0.6),
                            itemBuilder: (context, index) {
                              final option = optionList[index];
                              final isClosed = _isClosed(option);
                              return ListTile(
                                dense: true,
                                enabled: !isClosed,
                                visualDensity: const VisualDensity(
                                  horizontal: -1,
                                  vertical: -2,
                                ),
                                leading: _TrackSearchRouteBadge(
                                  routeIds: option.routeIds,
                                ),
                                title: Text(
                                  option.stationName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: isClosed
                                        ? const Color(0xFF98A2B3)
                                        : null,
                                  ),
                                ),
                                subtitle: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: option.stopIds
                                      .map(
                                        (code) =>
                                            _TrackStopCodeChip(code: code),
                                      )
                                      .toList(),
                                ),
                                trailing: isClosed
                                    ? const Text(
                                        'Closing hours',
                                        style: TextStyle(
                                          color: Color(0xFF98A2B3),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      )
                                    : null,
                                onTap: isClosed
                                    ? null
                                    : () {
                                        onOptionSelected(option);
                                        onSelected(option);
                                      },
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isSearching ? null : onSearch,
                    icon: const Icon(Icons.search_rounded),
                    label: Text(isSearching ? 'Starting trip...' : 'Search'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onPlanAhead,
                    icon: const Icon(Icons.schedule_rounded),
                    label: const Text('Plan ahead'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StopNode {
  final String stopId;
  final String stopName;
  final String routeId;
  final double latitude;
  final double longitude;

  const _StopNode({
    required this.stopId,
    required this.stopName,
    required this.routeId,
    required this.latitude,
    required this.longitude,
  });
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

class _TrackStationOption {
  final String stationName;
  final List<String> stopIds;
  final List<String> routeIds;

  const _TrackStationOption({
    required this.stationName,
    required this.stopIds,
    required this.routeIds,
  });
}

class _TrackSearchRouteBadge extends StatelessWidget {
  final List<String> routeIds;

  const _TrackSearchRouteBadge({
    required this.routeIds,
  });

  @override
  Widget build(BuildContext context) {
    final ids = routeIds.where((id) => id.isNotEmpty && id != 'N/A').toList();
    if (ids.length <= 1) {
      final route = ids.isEmpty ? 'N/A' : ids.first;
      return CircleAvatar(
        radius: 16,
        backgroundColor: getRouteColor(route),
        child: Text(
          normalizeRouteId(route),
          style: TextStyle(
            color: getRouteOnColor(route),
            fontWeight: FontWeight.w800,
            fontSize: 10,
          ),
        ),
      );
    }

    final colors = ids.map(getRouteColor).toList();
    return SizedBox(
      width: 32,
      height: 32,
      child: CustomPaint(
        painter: _TrackSearchRouteSegmentsPainter(colors: colors),
      ),
    );
  }
}

class _TrackSearchRouteSegmentsPainter extends CustomPainter {
  final List<Color> colors;

  const _TrackSearchRouteSegmentsPainter({
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
      ..strokeWidth = 1
      ..color = const Color(0xFFDDE6F5);
    canvas.drawCircle(center, radius - 0.5, border);
  }

  @override
  bool shouldRepaint(covariant _TrackSearchRouteSegmentsPainter oldDelegate) {
    if (oldDelegate.colors.length != colors.length) return true;
    for (var i = 0; i < colors.length; i++) {
      if (oldDelegate.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

class _TrackStopCodeChip extends StatelessWidget {
  final String code;

  const _TrackStopCodeChip({
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final route = normalizeRouteId(_inferRouteIdFromStopId(code));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: getRouteColor(route).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: getRouteColor(route),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DijkstraResult {
  final String destinationStopId;
  final List<_RouteConnection> path;
  final int totalMinutes;
  final int weightedMinutes;

  const _DijkstraResult({
    required this.destinationStopId,
    required this.path,
    required this.totalMinutes,
    required this.weightedMinutes,
  });
}

class _PositionRecord {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  const _PositionRecord({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  double distanceTo(double lat, double lng) {
    return Geolocator.distanceBetween(latitude, longitude, lat, lng);
  }
}

class _PlanRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PlanRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF0A3A8B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF344054),
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF0A3A8B),
          ),
        ),
      ],
    );
  }
}

String _inferRouteIdFromStopId(String stopId) {
  final match = RegExp(r'^[A-Za-z]+').firstMatch(stopId.trim());
  return (match?.group(0) ?? 'N/A').toUpperCase();
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

String _formatMeters(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}
