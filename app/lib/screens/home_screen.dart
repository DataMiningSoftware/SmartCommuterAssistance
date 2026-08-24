// ignore_for_file: unused_element, unused_element_parameter, unused_local_variable

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../services/active_trip_service.dart';
import '../services/crowd_reports_service.dart';
import '../services/location_privacy_service.dart';
import '../services/navigation_state.dart';
import '../services/operating_hours_service.dart';
import '../services/transit_network_service.dart';
import '../widgets/app_page_title.dart';
import '../widgets/scheduled_arrivals_panel.dart';
import 'station_crowd_board_screen.dart';
import 'stations_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ActiveTripService _activeTripService = ActiveTripService.instance;
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  final TransitNetworkService _transitNetworkService = TransitNetworkService();
  final TextEditingController _routeSearchController = TextEditingController();
  Position? _position;
  bool _isPreparingTrip = false;
  Future<List<NearbyStationCrowdForecast>>? _nearestCrowdFuture;
  late Future<List<_HomeStationSearchOption>> _stationSearchFuture;
  late Future<Map<String, bool>> _stationClosedByStopFuture;
  Timer? _nearestAutoRefreshTimer;
  bool _isLoadingMap = true;
  String? _mapError;
  final Map<String, _MapStop> _mapStopsById = <String, _MapStop>{};
  final List<_HomeRouteConnection> _routeConnections = <_HomeRouteConnection>[];
  DateTime _departureTime = DateTime.now();
  _HomeRouteMode _routeMode = _HomeRouteMode.auto;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _loadMapStops();
    _stationSearchFuture = _loadStationSearchOptions();
    _stationClosedByStopFuture = _stationSearchFuture.then(
      (options) => _loadStationClosedByStop(options, _departureTime),
    );
    _startNearestCrowdAutoRefresh();
  }

  void _handleStationSelected(_HomeStationSearchOption option) {
    unawaited(_prepareTrip(option));
  }

  Future<void> _prepareTrip(_HomeStationSearchOption option) async {
    if (_isPreparingTrip) return;
    setState(() => _isPreparingTrip = true);
    try {
      final closedByStop =
          await _crowdReportsService.fetchClosedStatusForStopsAtTime(
        option.stopCodes,
        _departureTime,
      );
      final isClosed = option.stopCodes.any(
        (stopCode) => closedByStop[stopCode.trim().toUpperCase()] ?? false,
      );
      if (isClosed) {
        _showHomeMessage(
          '${option.stationName} is unavailable during closing hours for the selected departure time.',
        );
        return;
      }

      var position = _position;
      if (position == null) {
        await _loadLocation();
        position = _position;
      }
      if (!mounted || position == null) {
        _showHomeMessage('Location is required before starting a trip.');
        return;
      }

      final nearestStops = _nearestMapStops(limit: 1);
      if (nearestStops.isEmpty) {
        _showHomeMessage('Could not determine your nearest station yet.');
        return;
      }

      final nearestStop = nearestStops.first;
      if (_routeConnections.isEmpty && !_isLoadingMap) {
        await _loadMapStops();
      }

      _HomeRoutePreview? selectedPreview;
      if (option.stopCodes.isNotEmpty && _routeConnections.isNotEmpty) {
        final forecasts =
            await _crowdReportsService.fetchForecastForStopsAtTime(
          _mapStopsById.keys.toList(),
          _departureTime,
        );
        final crowdByStopId = <String, int>{
          for (final entry in forecasts.entries)
            entry.key.toUpperCase(): entry.value.occupancyLevel,
        };

        final efficientResult = _bestPathToStops(
          originStopId: nearestStop.stopId,
          destinationStopIds: option.stopCodes,
          preferComfort: false,
          crowdByStopId: crowdByStopId,
        );
        if (efficientResult == null) {
          _showHomeMessage('No route found for ${option.stationName}.');
          return;
        }

        final efficientPreview = _buildRoutePreview(
          result: efficientResult,
          originName: nearestStop.stopName,
          destinationName: option.stationName,
          routePreference: 'efficiency',
          crowdByStopId: crowdByStopId,
        );

        _HomeRoutePreview? relaxedPreview;
        if (_routeMode != _HomeRouteMode.efficiency) {
          final comfortResult = _bestPathToStops(
            originStopId: nearestStop.stopId,
            destinationStopIds: option.stopCodes,
            preferComfort: true,
            crowdByStopId: crowdByStopId,
          );
          relaxedPreview = comfortResult == null
              ? null
              : _buildRoutePreview(
                  result: comfortResult,
                  originName: nearestStop.stopName,
                  destinationName: option.stationName,
                  routePreference: 'comfort',
                  crowdByStopId: crowdByStopId,
                );
        }

        final shouldPrompt = _routeMode == _HomeRouteMode.auto &&
            relaxedPreview != null &&
            _shouldPromptRelaxedRoute(
              efficientPreview: efficientPreview,
              relaxedPreview: relaxedPreview,
            );

        if (shouldPrompt) {
          selectedPreview = await _showPackedRoutePrompt(
            destinationName: option.stationName,
            efficientPreview: efficientPreview,
            relaxedPreview: relaxedPreview,
          );
          if (selectedPreview == null) return;
        } else if (_routeMode == _HomeRouteMode.comfort &&
            relaxedPreview != null) {
          selectedPreview = relaxedPreview;
        } else {
          selectedPreview = efficientPreview;
        }
      }

      final fallbackDestinationStopId = option.stopCodes.isEmpty
          ? option.stationName
          : option.stopCodes.first;
      final fallbackStops = <ActiveTripStop>[
        ActiveTripStop(
          stopId: nearestStop.stopId,
          stopName: nearestStop.stopName,
          routeId: nearestStop.routeId,
        ),
        ActiveTripStop(
          stopId: fallbackDestinationStopId,
          stopName: option.stationName,
          routeId: option.routeIds.isEmpty ? 'N/A' : option.routeIds.first,
        ),
      ];
      final preview = selectedPreview;

      await _activeTripService.saveTrip(
        ActiveTrip(
          originStopId: nearestStop.stopId,
          destinationStopId:
              preview?.result.destinationStopId ?? fallbackDestinationStopId,
          originName: nearestStop.stopName,
          destinationName: option.stationName,
          routePreference: preview?.routePreference ?? 'efficiency',
          highestCrowdLevel: preview?.highestCrowdLevel ?? 0,
          createdAt: DateTime.now(),
          estimatedTotalMinutes: preview?.totalMinutes,
          stops: preview?.activeTripStops ?? fallbackStops,
        ),
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      _routeSearchController.clear();
      NavigationState.instance.goTo(2);
    } catch (e) {
      if (!mounted) return;
      _showHomeMessage('Could not prepare trip: $e');
    } finally {
      if (mounted) {
        setState(() => _isPreparingTrip = false);
      }
    }
  }

  Future<_HomeRoutePreview?> _showPackedRoutePrompt({
    required String destinationName,
    required _HomeRoutePreview efficientPreview,
    required _HomeRoutePreview relaxedPreview,
  }) {
    final efficientReasoning = _buildChoiceReasoningLabels(
      preview: efficientPreview,
      comparison: relaxedPreview,
      prioritizeCrowd: false,
    );
    final relaxedReasoning = _buildChoiceReasoningLabels(
      preview: relaxedPreview,
      comparison: efficientPreview,
      prioritizeCrowd: true,
    );
    return showModalBottomSheet<_HomeRoutePreview>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
                _HomeRouteChoiceCard(
                  title: 'Efficient route',
                  subtitle: 'Fastest option right now',
                  preview: efficientPreview,
                  reasoningLabels: efficientReasoning,
                  actionLabel: 'Keep this route',
                  isPrimary: false,
                  onTap: () => Navigator.of(context).pop(efficientPreview),
                ),
                const SizedBox(height: 10),
                _HomeRouteChoiceCard(
                  title: 'Relaxed route',
                  subtitle: 'Calmer ride with a small detour',
                  preview: relaxedPreview,
                  reasoningLabels: relaxedReasoning,
                  actionLabel: 'Take a more relaxed route',
                  isPrimary: true,
                  onTap: () => Navigator.of(context).pop(relaxedPreview),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _showLocationConsentDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Location Privacy'),
        content: const Text(
          'Your location is used to find nearby stations and '
          'provide arrival estimates. Coordinates are rounded '
          'to ~1 km precision before being sent to our servers. '
          'Your exact location is never stored or shared.\n\n'
          'You can change this later in Profile settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (result == true) {
      await LocationPrivacyService.setConsent(true);
    }
    return result ?? false;
  }

  void _showHomeMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _shouldPromptRelaxedRoute({
    required _HomeRoutePreview efficientPreview,
    required _HomeRoutePreview relaxedPreview,
  }) {
    if (_sameRouteResult(efficientPreview.result, relaxedPreview.result)) {
      return false;
    }
    if (efficientPreview.highestCrowdLevel <= 2) return false;

    final crowdImprovement =
        efficientPreview.highestCrowdLevel - relaxedPreview.highestCrowdLevel;
    if (crowdImprovement <= 0) return false;

    final timeDelta =
        relaxedPreview.totalMinutes - efficientPreview.totalMinutes;
    if (timeDelta <= 0) return true;
    if (crowdImprovement >= 2) return timeDelta <= 12;
    return timeDelta <= 6;
  }

  List<String> _buildChoiceReasoningLabels({
    required _HomeRoutePreview preview,
    required _HomeRoutePreview comparison,
    required bool prioritizeCrowd,
  }) {
    final labels = <String>[];
    final crowdDelta = comparison.highestCrowdLevel - preview.highestCrowdLevel;
    final crowdLabel = _formatCrowdDeltaLabel(crowdDelta);
    final timeLabel = _formatTimeDeltaLabel(
      preview.totalMinutes - comparison.totalMinutes,
      preferNoPenalty: prioritizeCrowd,
    );

    if (prioritizeCrowd && crowdLabel != null) {
      labels.add(crowdLabel);
    }
    if (timeLabel != null) {
      labels.add(timeLabel);
    }
    if (!prioritizeCrowd && crowdLabel != null) {
      labels.add(crowdLabel);
    }
    labels.add(_formatTransferCountLabel(preview.transferCount));
    return labels;
  }

  String? _formatCrowdDeltaLabel(int delta) {
    if (delta == 0) return null;
    final magnitude = delta.abs();
    final suffix = magnitude == 1 ? '' : 's';
    final direction = delta > 0 ? 'lower' : 'higher';
    return '$magnitude crowd level$suffix $direction';
  }

  String? _formatTimeDeltaLabel(
    int delta, {
    required bool preferNoPenalty,
  }) {
    if (delta < 0) return 'Fastest';
    if (delta == 0) return preferNoPenalty ? 'No time penalty' : 'Fastest';
    return '+$delta min';
  }

  String _formatTransferCountLabel(int count) {
    if (count <= 0) return 'Direct ride';
    return count == 1 ? '1 transfer' : '$count transfers';
  }

  @override
  void dispose() {
    _nearestAutoRefreshTimer?.cancel();
    _routeSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        return;
      }

      final consented = await LocationPrivacyService.hasConsent();
      if (!consented) {
        final result = await _showLocationConsentDialog();
        if (result != true || !mounted) return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      final redacted = LocationPrivacyService.redact(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      setState(() {
        _position = position;
        _nearestCrowdFuture =
            _crowdReportsService.fetchNearestStationsWithCrowd(
          latitude: redacted.latitude,
          longitude: redacted.longitude,
          departureTime: DateTime.now(),
          limit: 5,
        );
      });
    } catch (e) {
      if (!mounted) return;
    }
  }

  void _refreshNearestCrowd() {
    final position = _position;
    if (position == null) return;
    final redacted = LocationPrivacyService.redact(
      latitude: position.latitude,
      longitude: position.longitude,
    );
    setState(() {
      _nearestCrowdFuture = _crowdReportsService.fetchNearestStationsWithCrowd(
        latitude: redacted.latitude,
        longitude: redacted.longitude,
        departureTime: DateTime.now(),
        limit: 5,
      );
    });
  }

  void _refreshCrowdBoard() {
    _refreshNearestCrowd();
  }

  void _startNearestCrowdAutoRefresh() {
    _nearestAutoRefreshTimer?.cancel();
    _nearestAutoRefreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) {
        if (!mounted) return;
        _refreshNearestCrowd();
      },
    );
  }

  Future<void> _loadMapStops() async {
    if (mounted) {
      setState(() {
        _isLoadingMap = true;
        _mapError = null;
      });
    }
    try {
      final network = await _transitNetworkService.loadNetwork();
      _mapStopsById.clear();
      for (final stop in network.stopsById.values) {
        _mapStopsById[stop.stopId] = _MapStop(
          stopId: stop.stopId,
          stopName: stop.stopName,
          routeId: stop.routeId,
          latitude: stop.latitude,
          longitude: stop.longitude,
        );
      }

      _routeConnections
        ..clear()
        ..addAll(
          network.connections.map(
            (edge) => _HomeRouteConnection(
              fromStopId: edge.fromStopId,
              toStopId: edge.toStopId,
              routeId: edge.routeId,
              connectionType: edge.connectionType,
              travelMinutes: edge.travelMinutes,
            ),
          ),
        );

      if (!mounted) return;
      setState(() => _isLoadingMap = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mapError = e.toString();
        _isLoadingMap = false;
      });
    }
  }

  Future<List<_HomeStationSearchOption>> _loadStationSearchOptions() async {
    try {
      final network = await _transitNetworkService.loadNetwork();
      final options = network.stationOptions
          .map(
            (option) => _HomeStationSearchOption(
              stationName: option.stationName,
              stopCodes: option.stopIds,
              routeIds: option.routeIds,
            ),
          )
          .toList();
      if (options.isNotEmpty) {
        return options;
      }
    } catch (_) {}

    return const <_HomeStationSearchOption>[
      _HomeStationSearchOption(
        stationName: 'KL Sentral',
        stopCodes: <String>['KJ15'],
        routeIds: <String>['KJ'],
      ),
      _HomeStationSearchOption(
        stationName: 'Pasar Seni',
        stopCodes: <String>['KJ14', 'KG16'],
        routeIds: <String>['KJ', 'KG'],
      ),
      _HomeStationSearchOption(
        stationName: 'Bukit Bintang',
        stopCodes: <String>['KG18', 'MR6'],
        routeIds: <String>['KG', 'MR'],
      ),
    ];
  }

  List<_HomeRouteConnection> _mapEdgeRows(List<Map<String, dynamic>> edgeRows) {
    final output = <_HomeRouteConnection>[];
    for (final row in edgeRows) {
      final from = (row['from_stop_id']?.toString() ?? '').trim().toUpperCase();
      final to = (row['to_stop_id']?.toString() ?? '').trim().toUpperCase();
      if (!_mapStopsById.containsKey(from) || !_mapStopsById.containsKey(to)) {
        continue;
      }
      final routeId = normalizeRouteId(
        (row['route_id']?.toString() ?? '').trim().toUpperCase(),
      );
      final type =
          (row['connection_type']?.toString() ?? 'standard_stop').trim();
      final minutesRaw = row['travel_time_minutes'];
      final minutes = minutesRaw is num
          ? minutesRaw.toInt()
          : int.tryParse(minutesRaw?.toString() ?? '') ?? 2;
      output.add(
        _HomeRouteConnection(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          connectionType: type,
          travelMinutes: minutes,
        ),
      );
    }
    return output;
  }

  List<_HomeRouteConnection> _buildFallbackConnections(List<_MapStop> stops) {
    final edges = <_HomeRouteConnection>[];
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
        _HomeRouteConnection(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          connectionType: type,
          travelMinutes: minutes,
        ),
      );
    }

    final byLine = <String, List<_MapStop>>{};
    for (final stop in stops) {
      byLine.putIfAbsent(stop.routeId, () => <_MapStop>[]).add(stop);
    }
    for (final entry in byLine.entries) {
      final ordered = List<_MapStop>.from(entry.value)
        ..sort((a, b) => _compareStopCode(a.stopId, b.stopId));
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

    final byStation = <String, List<_MapStop>>{};
    for (final stop in stops) {
      byStation
          .putIfAbsent(stop.stopName.toUpperCase(), () => <_MapStop>[])
          .add(stop);
    }
    for (final stationStops in byStation.values) {
      if (stationStops.length < 2) continue;
      for (var i = 0; i < stationStops.length - 1; i++) {
        for (var j = i + 1; j < stationStops.length; j++) {
          final a = stationStops[i];
          final b = stationStops[j];
          if (a.routeId == b.routeId) continue;
          addEdge(
            from: a.stopId,
            to: b.stopId,
            routeId: b.routeId,
            type: 'interchange_transfer',
            minutes: 3,
          );
          addEdge(
            from: b.stopId,
            to: a.stopId,
            routeId: a.routeId,
            type: 'interchange_transfer',
            minutes: 3,
          );
        }
      }
    }
    return edges;
  }

  _HomeDijkstraResult? _bestPathToStops({
    required String originStopId,
    required List<String> destinationStopIds,
    required bool preferComfort,
    required Map<String, int> crowdByStopId,
  }) {
    _HomeDijkstraResult? bestResult;
    for (final destinationStopId in destinationStopIds) {
      final result = _shortestPath(
        originStopId: originStopId,
        destinationStopId: destinationStopId,
        preferComfort: preferComfort,
        crowdByStopId: crowdByStopId,
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

  _HomeDijkstraResult? _shortestPath({
    required String originStopId,
    required String destinationStopId,
    required bool preferComfort,
    required Map<String, int> crowdByStopId,
  }) {
    if (!_mapStopsById.containsKey(originStopId) ||
        !_mapStopsById.containsKey(destinationStopId)) {
      return null;
    }

    final adjacency = <String, List<_HomeRouteConnection>>{};
    void addEdge(_HomeRouteConnection edge) {
      adjacency
          .putIfAbsent(edge.fromStopId, () => <_HomeRouteConnection>[])
          .add(edge);
    }

    for (final edge in _routeConnections) {
      addEdge(edge);
      addEdge(edge.reversed());
    }

    final distances = <String, int>{originStopId: 0};
    final previousNode = <String, String>{};
    final previousEdge = <String, _HomeRouteConnection>{};
    final visited = <String>{};

    while (visited.length < _mapStopsById.length) {
      String? current;
      var currentDistance = 1 << 30;
      for (final id in _mapStopsById.keys) {
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

      for (final edge in adjacency[current] ?? const <_HomeRouteConnection>[]) {
        if (visited.contains(edge.toStopId)) continue;
        if (!OperatingHoursService.isLineRunning(edge.routeId, at: _departureTime)) continue;
        final penalty = preferComfort
            ? _crowdPenaltyForStop(crowdByStopId, edge.toStopId)
            : 0;
        final candidate = currentDistance + edge.travelMinutes + penalty;
        if (candidate < (distances[edge.toStopId] ?? (1 << 30))) {
          distances[edge.toStopId] = candidate;
          previousNode[edge.toStopId] = current;
          previousEdge[edge.toStopId] = edge;
        }
      }
    }

    if (!previousEdge.containsKey(destinationStopId)) return null;
    final path = <_HomeRouteConnection>[];
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
    return _HomeDijkstraResult(
      destinationStopId: destinationStopId,
      path: ordered,
      totalMinutes: total,
      weightedMinutes: distances[destinationStopId] ?? total,
    );
  }

  int _crowdPenaltyForStop(Map<String, int> crowdByStopId, String stopId) {
    switch (crowdByStopId[stopId] ?? 0) {
      case 2:
        return 3;
      case 3:
        return 8;
      case 4:
        return 14;
      case 5:
        return 18;
      default:
        return 0;
    }
  }

  _HomeRoutePreview _buildRoutePreview({
    required _HomeDijkstraResult result,
    required String originName,
    required String destinationName,
    required String routePreference,
    required Map<String, int> crowdByStopId,
  }) {
    final activeTripStops = <ActiveTripStop>[];
    final originStop = _mapStopsById[result.path.isEmpty
        ? result.destinationStopId
        : result.path.first.fromStopId];
    if (originStop != null) {
      activeTripStops.add(
        ActiveTripStop(
          stopId: originStop.stopId,
          stopName: originStop.stopName,
          routeId: originStop.routeId,
        ),
      );
    }
    for (final edge in result.path) {
      final stop = _mapStopsById[edge.toStopId];
      if (stop == null) continue;
      activeTripStops.add(
        ActiveTripStop(
          stopId: stop.stopId,
          stopName: stop.stopName,
          routeId: edge.routeId,
        ),
      );
    }

    final highestCrowdLevel = activeTripStops.fold<int>(
      0,
      (highest, stop) => math.max(highest, crowdByStopId[stop.stopId] ?? 0),
    );
    final routeLines = <String>[];
    String? previousLine;
    for (final edge in result.path) {
      final line = normalizeRouteId(edge.routeId);
      if (line == previousLine) continue;
      routeLines.add(line);
      previousLine = line;
    }
    final transferCount = result.path
        .where((edge) => edge.connectionType == 'interchange_transfer')
        .length;

    return _HomeRoutePreview(
      routePreference: routePreference,
      originName: originName,
      destinationName: destinationName,
      highestCrowdLevel: highestCrowdLevel,
      totalMinutes: result.totalMinutes,
      routeLines: routeLines,
      transferCount: transferCount,
      stopCount: activeTripStops.length,
      activeTripStops: activeTripStops,
      result: result,
    );
  }

  bool _sameRouteResult(_HomeDijkstraResult a, _HomeDijkstraResult b) {
    if (a.destinationStopId != b.destinationStopId) return false;
    if (a.path.length != b.path.length) return false;
    for (var i = 0; i < a.path.length; i++) {
      final left = a.path[i];
      final right = b.path[i];
      if (left.fromStopId != right.fromStopId ||
          left.toStopId != right.toStopId ||
          left.routeId != right.routeId) {
        return false;
      }
    }
    return true;
  }

  Future<Map<String, bool>> _loadStationClosedByStop(
    List<_HomeStationSearchOption> options,
    DateTime time,
  ) async {
    final stopCodes = <String>{
      for (final option in options)
        ...option.stopCodes.map((code) => code.trim().toUpperCase()),
    }.toList();
    if (stopCodes.isEmpty) return const <String, bool>{};
    return _crowdReportsService.fetchClosedStatusForStopsAtTime(
        stopCodes, time);
  }

  List<_HomeStationSearchOption> _buildSearchOptions(
    Map<String, List<Map<String, dynamic>>> groupedRows,
  ) {
    final options = <_HomeStationSearchOption>[];
    for (final entry in groupedRows.entries) {
      final stationName = entry.key;
      final rows = entry.value;
      final stopCodes = <String>{};
      final routeIds = <String>{};

      for (final row in rows) {
        final stopCode =
            (row['stop_id']?.toString() ?? '').trim().toUpperCase();
        if (stopCode.isNotEmpty) {
          stopCodes.add(stopCode);
        }

        final routeRaw = (row['route_id']?.toString() ?? '').trim();
        if (routeRaw.isNotEmpty) {
          routeIds.add(normalizeRouteId(routeRaw));
        } else if (stopCode.isNotEmpty) {
          routeIds.add(normalizeRouteId(_inferRouteIdFromStopId(stopCode)));
        }

        final lineArray = row['lines'];
        if (lineArray is List) {
          for (final item in lineArray) {
            final lineText = item?.toString().trim() ?? '';
            if (lineText.isEmpty) continue;
            routeIds.add(normalizeRouteId(lineText));
          }
        }
      }

      final sortedCodes = stopCodes.toList()..sort();
      final sortedRoutes = routeIds.where((id) => id != 'N/A').toList()..sort();

      options.add(
        _HomeStationSearchOption(
          stationName: stationName,
          stopCodes: sortedCodes,
          routeIds: sortedRoutes,
        ),
      );
    }
    options.sort((a, b) => a.stationName.compareTo(b.stationName));
    return options;
  }

  void _openMapTab() {
    NavigationState.instance.goTo(1);
  }

  List<_MapStop> _nearestMapStops({int limit = 5}) {
    final position = _position;
    if (position == null) return const <_MapStop>[];
    final stops = _mapStopsById.values.toList()
      ..sort((a, b) {
        final aDistance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          a.latitude,
          a.longitude,
        );
        final bDistance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          b.latitude,
          b.longitude,
        );
        return aDistance.compareTo(bDistance);
      });
    return stops.take(limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.train_rounded,
          leadingText: 'Smart',
          accentText: 'Commuter',
          badgeText: 'ASSISTANT+',
          subtitle: 'Home base',
        ),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadLocation();
          await _loadMapStops();
          _refreshNearestCrowd();
          _refreshCrowdBoard();
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _HeroCard(
                    theme: Theme.of(context),
                    title: 'Ride smart, skip the squeeze.',
                    subtitle:
                        'Live crowd-aware routing, trip tracking, and route glow in one place.',
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<ActiveTrip?>(
                    valueListenable: _activeTripService.activeTrip,
                    builder: (context, trip, _) {
                      if (trip != null) {
                        return _LiveTripSummary(
                          trip: trip,
                          onOpenMap: _openMapTab,
                        );
                      }
                      return _HomeRouteSearchCard(
                        stationNamesFuture: _stationSearchFuture,
                        stationClosedByStopFuture: _stationClosedByStopFuture,
                        controller: _routeSearchController,
                        departureTime: _departureTime,
                        routeMode: _routeMode,
                        onDepartureTimeSelected: (value) {
                          setState(() {
                            _departureTime = value;
                            _stationClosedByStopFuture =
                                _stationSearchFuture.then(
                              (options) =>
                                  _loadStationClosedByStop(options, value),
                            );
                          });
                        },
                        onRouteModeChanged: (value) {
                          setState(() => _routeMode = value);
                        },
                        onStationSelected: _handleStationSelected,
                        nearestCrowdFuture: _nearestCrowdFuture,
                        isPreparingTrip: _isPreparingTrip,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_mapError != null) ...[
                    _InlineHomeError(
                      message: _mapError!,
                      onRetry: _loadMapStops,
                    ),
                    const SizedBox(height: 16),
                  ],
                  _StationCrowdBoard(
                    nearestCrowdFuture: _nearestCrowdFuture,
                    onRefresh: _refreshCrowdBoard,
                    onOpenAllStations: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StationCrowdBoardScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          icon: Icons.train_rounded,
                          label: 'All Stations',
                          subtitle: 'Browse lines and interchanges',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StationsScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ValueListenableBuilder<ActiveTrip?>(
                          valueListenable: _activeTripService.activeTrip,
                          builder: (context, trip, _) {
                            return _ActionTile(
                              icon: Icons.route_rounded,
                              label:
                                  trip == null ? 'Track Route' : 'Resume Trip',
                              subtitle: trip == null
                                  ? 'Start a trip to unlock tracking'
                                  : '${trip.originName} to ${trip.destinationName}',
                              onTap: () => NavigationState.instance.goTo(2),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _HomeRouteMode {
  auto,
  efficiency,
  comfort,
}

extension _HomeRouteModeUi on _HomeRouteMode {
  String get label {
    switch (this) {
      case _HomeRouteMode.auto:
        return 'Auto';
      case _HomeRouteMode.efficiency:
        return 'Efficient';
      case _HomeRouteMode.comfort:
        return 'Relaxed';
    }
  }

  String get helperText {
    switch (this) {
      case _HomeRouteMode.auto:
        return 'Compare efficient and relaxed routes, then ask only when the calmer route is worth it.';
      case _HomeRouteMode.efficiency:
        return 'Always keep the fastest route.';
      case _HomeRouteMode.comfort:
        return 'Prefer lower crowd even if the trip takes a little longer.';
    }
  }
}

class _HomeRouteSearchCard extends StatefulWidget {
  final Future<List<_HomeStationSearchOption>> stationNamesFuture;
  final Future<Map<String, bool>> stationClosedByStopFuture;
  final TextEditingController controller;
  final DateTime departureTime;
  final _HomeRouteMode routeMode;
  final ValueChanged<DateTime> onDepartureTimeSelected;
  final ValueChanged<_HomeRouteMode> onRouteModeChanged;
  final ValueChanged<_HomeStationSearchOption> onStationSelected;
  final Future<List<NearbyStationCrowdForecast>>? nearestCrowdFuture;
  final bool isPreparingTrip;

  const _HomeRouteSearchCard({
    required this.stationNamesFuture,
    required this.stationClosedByStopFuture,
    required this.controller,
    required this.departureTime,
    required this.routeMode,
    required this.onDepartureTimeSelected,
    required this.onRouteModeChanged,
    required this.onStationSelected,
    required this.nearestCrowdFuture,
    required this.isPreparingTrip,
  });

  @override
  State<_HomeRouteSearchCard> createState() => _HomeRouteSearchCardState();
}

class _HomeRouteSearchCardState extends State<_HomeRouteSearchCard> {
  final GlobalKey _fieldKey = GlobalKey();
  FocusNode? _trackedFocusNode;
  _HomeStationSearchOption? _selectedStationOption;

  @override
  void dispose() {
    _trackedFocusNode?.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _attachFocusNode(FocusNode focusNode) {
    if (identical(_trackedFocusNode, focusNode)) return;
    _trackedFocusNode?.removeListener(_handleFocusChange);
    _trackedFocusNode = focusNode;
    focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_trackedFocusNode?.hasFocus ?? false) {
      _ensureFieldVisible();
    }
  }

  void _ensureFieldVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fieldContext = _fieldKey.currentContext;
      if (!mounted || fieldContext == null) return;
      Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  void _rememberSelectedStation(_HomeStationSearchOption option) {
    if (!mounted) return;
    setState(() => _selectedStationOption = option);
  }



  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    if (!OperatingHoursService.isAnyLineRunning(at: widget.departureTime)) {
      final nextOpen = OperatingHoursService.nextOpeningTime(at: widget.departureTime);
      final message = nextOpen != null
          ? 'The trains are closed and will open at ${OperatingHoursService.formatTime(nextOpen)}.'
          : 'The trains are currently closed.';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFF8F9FC),
              Color(0xFFEEF0F7),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: const Color(0xFFD0D5DD),
            width: 1,
          ),
          boxShadow: appCardShadows(context, prominent: true),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.bedtime_rounded,
              size: 64,
              color: Color(0xFF667085),
            ),
            const SizedBox(height: 20),
            const Text(
              'Trains are closed',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset > 0 ? 12 : 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFFFCF5),
              primary.withValues(alpha: 0.09),
              const Color(0xFFFFFFFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: primary.withValues(alpha: 0.18),
            width: 1.2,
          ),
          boxShadow: appCardShadows(context, prominent: true),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pick Your Next Stop',
              style: TextStyle(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Search a destination, set your routing style, and preview crowd before you leave.',
              style: TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Route style',
              style: TextStyle(
                color: Color(0xFF475467),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in _HomeRouteMode.values)
                  _HomeRouteModeChip(
                    mode: mode,
                    selected: widget.routeMode == mode,
                    onTap: () => widget.onRouteModeChanged(mode),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.routeMode.helperText,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<_HomeStationSearchOption>>(
              future: widget.stationNamesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Text('Loading stations…', style: TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w600)),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'Failed to load stations: ${snapshot.error}',
                    style: const TextStyle(color: Color(0xFFB42318)),
                  );
                }

                final stationOptions =
                    snapshot.data ?? const <_HomeStationSearchOption>[];
                if (stationOptions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'No station names available yet. Showing a local sample list instead.',
                      style: TextStyle(color: Color(0xFF667085)),
                    ),
                  );
                }

                return FutureBuilder<Map<String, bool>>(
                  future: widget.stationClosedByStopFuture,
                  builder: (context, availabilitySnapshot) {
                    final closedByStop =
                        availabilitySnapshot.data ?? const <String, bool>{};

                    bool isOptionClosed(_HomeStationSearchOption option) {
                      for (final stopCode in option.stopCodes) {
                        if (closedByStop[stopCode.trim().toUpperCase()] ??
                            false) {
                          return true;
                        }
                      }
                      return false;
                    }

                    void showClosedStationMessage(
                        _HomeStationSearchOption option) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${option.stationName} is unavailable during closing hours for the selected departure time.',
                          ),
                        ),
                      );
                    }

                    return Autocomplete<_HomeStationSearchOption>(
                      optionsBuilder: (value) {
                        final query = value.text.trim().toLowerCase();
                        if (query.isEmpty) {
                          return const Iterable<
                              _HomeStationSearchOption>.empty();
                        }
                        return stationOptions.where((station) {
                          final inName =
                              station.stationName.toLowerCase().contains(query);
                          final inCode = station.stopCodes.any(
                            (code) => code.toLowerCase().contains(query),
                          );
                          final inRoute = station.routeIds.any(
                            (routeId) => routeId.toLowerCase().contains(query),
                          );
                          return inName || inCode || inRoute;
                        }).take(12);
                      },
                      displayStringForOption: (option) => option.stationName,
                      onSelected: (option) {
                        if (isOptionClosed(option)) {
                          showClosedStationMessage(option);
                          return;
                        }
                        _rememberSelectedStation(option);
                        widget.onStationSelected(option);
                      },
                      fieldViewBuilder: (
                        context,
                        textController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        if (textController.text != widget.controller.text) {
                          textController.value = widget.controller.value;
                        }
                        _attachFocusNode(focusNode);
                        return TextField(
                          key: _fieldKey,
                          controller: textController,
                          focusNode: focusNode,
                          scrollPadding: const EdgeInsets.only(
                            left: 20,
                            top: 20,
                            right: 20,
                            bottom: 260,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search train station',
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search_rounded),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: primary.withValues(alpha: 0.2),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: primary,
                                width: 1.6,
                              ),
                            ),
                          ),
                          onTap: _ensureFieldVisible,
                          onChanged: (_) {
                            widget.controller.value = textController.value;
                            final query =
                                textController.text.trim().toLowerCase();
                            _HomeStationSearchOption? exactMatch;
                            for (final option in stationOptions) {
                              if (option.stationName.toLowerCase() == query) {
                                exactMatch = option;
                                break;
                              }
                            }
                            if (exactMatch == null ||
                                isOptionClosed(exactMatch)) {
                              if (_selectedStationOption != null) {
                                setState(() => _selectedStationOption = null);
                              }
                            } else {
                              _rememberSelectedStation(exactMatch);
                            }
                          },
                          onSubmitted: (value) {
                            final text = value.trim();
                            if (text.isEmpty) return;
                            final match = stationOptions.firstWhere(
                              (option) =>
                                  option.stationName.toLowerCase() ==
                                  text.toLowerCase(),
                              orElse: () => _HomeStationSearchOption(
                                stationName: text,
                                stopCodes: const <String>[],
                                routeIds: const <String>[],
                              ),
                            );
                            if (match.stopCodes.isNotEmpty &&
                                isOptionClosed(match)) {
                              showClosedStationMessage(match);
                              return;
                            }
                            if (match.stopCodes.isNotEmpty) {
                              _rememberSelectedStation(match);
                            }
                            widget.onStationSelected(match);
                          },
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
                                MediaQuery.sizeOf(context).width - 32,
                                430,
                              ),
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.06),
                                ),
                                boxShadow: appCardShadows(context),
                              ),
                              child: FutureBuilder<
                                  List<NearbyStationCrowdForecast>>(
                                future: widget.nearestCrowdFuture,
                                builder: (context, crowdSnapshot) {
                                  final crowdMap =
                                      <String, NearbyStationCrowdForecast>{};
                                  if (crowdSnapshot.hasData) {
                                    for (final forecast
                                        in crowdSnapshot.data!) {
                                      crowdMap[forecast.stationName
                                          .toUpperCase()] = forecast;
                                    }
                                  }

                                  return ListView.separated(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    shrinkWrap: true,
                                    itemCount: optionList.length,
                                    separatorBuilder: (_, __) => const Divider(
                                        height: 1, thickness: 0.6),
                                    itemBuilder: (context, index) {
                                      final option = optionList[index];
                                      final optionClosed =
                                          isOptionClosed(option);
                                      final crowdForecast = crowdMap[
                                          option.stationName.toUpperCase()];
                                      final isClosed = optionClosed ||
                                          (crowdForecast
                                                  ?.forecast?.isClosedHours ??
                                              false);
                                      final crowdUi = crowdForecast != null
                                          ? isClosed
                                              ? const _HomeCrowdUi(
                                                  label: 'Closing hours',
                                                  color: Color(0xFF98A2B3),
                                                )
                                              : _HomeCrowdUi.fromLevel(
                                                  crowdForecast.forecast
                                                          ?.occupancyLevel ??
                                                      1,
                                                )
                                          : optionClosed
                                              ? const _HomeCrowdUi(
                                                  label: 'Closing hours',
                                                  color: Color(0xFF98A2B3),
                                                )
                                              : null;

                                      return ListTile(
                                        dense: true,
                                        enabled: !optionClosed,
                                        visualDensity: const VisualDensity(
                                          horizontal: -1,
                                          vertical: -2,
                                        ),
                                        leading: _HomeSearchRouteBadge(
                                          routeIds: option.routeIds,
                                        ),
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                option.stationName,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: isClosed
                                                      ? const Color(0xFF98A2B3)
                                                      : null,
                                                ),
                                              ),
                                            ),
                                            if (crowdUi != null) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: crowdUi.color
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  crowdUi.label,
                                                  style: TextStyle(
                                                    color: crowdUi.color,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        subtitle: Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: option.stopCodes
                                              .map(
                                                (code) => _HomeSearchCodeChip(
                                                  code: code,
                                                ),
                                              )
                                              .toList(),
                                        ),
                                        onTap: optionClosed
                                            ? () =>
                                                showClosedStationMessage(option)
                                            : () {
                                                _rememberSelectedStation(
                                                    option);
                                                onSelected(option);
                                              },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => NavigationState.instance.goTo(2),
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text('Plan Ahead', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeRouteModeChip extends StatelessWidget {
  final _HomeRouteMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _HomeRouteModeChip({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0A3A8B) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF0A3A8B) : const Color(0xFFD6E0EF),
          ),
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF344054),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _HomeStationSearchOption {
  final String stationName;
  final List<String> stopCodes;
  final List<String> routeIds;

  const _HomeStationSearchOption({
    required this.stationName,
    required this.stopCodes,
    required this.routeIds,
  });
}

class _HomeSearchRouteBadge extends StatelessWidget {
  final List<String> routeIds;

  const _HomeSearchRouteBadge({
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
        painter: _HomeSearchRouteSegmentsPainter(colors: colors),
      ),
    );
  }
}

class _HomeSearchRouteSegmentsPainter extends CustomPainter {
  final List<Color> colors;

  const _HomeSearchRouteSegmentsPainter({
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
  bool shouldRepaint(covariant _HomeSearchRouteSegmentsPainter oldDelegate) {
    if (oldDelegate.colors.length != colors.length) return true;
    for (var i = 0; i < colors.length; i++) {
      if (oldDelegate.colors[i] != colors[i]) return true;
    }
    return false;
  }
}

class _HomeSearchCodeChip extends StatelessWidget {
  final String code;

  const _HomeSearchCodeChip({
    required this.code,
  });

  @override
  Widget build(BuildContext context) {
    final routeId = normalizeRouteId(_inferRouteIdFromStopId(code));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: getRouteColor(routeId).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        code,
        style: TextStyle(
          color: getRouteColor(routeId),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
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

class _HomeCrowdUi {
  final String label;
  final Color color;

  const _HomeCrowdUi({
    required this.label,
    required this.color,
  });

  static _HomeCrowdUi fromLevel(int level) {
    final crowd = crowdLevelStyleFromIndex(level);
    return _HomeCrowdUi(label: crowd.label, color: crowd.color);
  }
}

class _HeroCard extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String subtitle;

  const _HeroCard({
    required this.theme,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [Color(0xFF0E1D3A), Color(0xFF1B3566), Color(0xFF234B8F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: appCardShadows(context, prominent: true),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFFD6E4FF),
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineHomeError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _InlineHomeError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFA),
        borderRadius: BorderRadius.circular(24),
        border:
            Border.all(color: const Color(0xFFF04438).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live map unavailable',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFFB42318),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xFF7A271A),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _LiveTripSummary extends StatelessWidget {
  final ActiveTrip trip;
  final VoidCallback onOpenMap;

  const _LiveTripSummary({
    required this.trip,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final originRouteId =
        trip.stops.isEmpty ? 'N/A' : normalizeRouteId(trip.stops.first.routeId);
    final destinationRouteId =
        trip.stops.isEmpty ? 'N/A' : normalizeRouteId(trip.stops.last.routeId);
    final crowdUi = _HomeCrowdUi.fromLevel(trip.highestCrowdLevel);
    final estimatedArrivalTime = trip.estimatedArrivalTime;
    final arrivalLabel = switch (estimatedArrivalTime) {
      null => 'ETA syncing',
      final value when value.isBefore(DateTime.now()) => 'Arriving now',
      final value =>
        'Arrive by ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}',
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(28),
        boxShadow: appCardShadows(context, prominent: true),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.directions_railway_filled_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Live Trip',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onOpenMap,
                icon:
                    Icon(Icons.map_rounded, color: theme.colorScheme.onPrimary),
                label: Text(
                  'View map',
                  style: TextStyle(color: theme.colorScheme.onPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _HomeLiveTripStationPill(
                stationName: trip.originName,
                routeId: originRouteId,
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 20,
              ),
              _HomeLiveTripStationPill(
                stationName: trip.destinationName,
                routeId: destinationRouteId,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            trip.routePreference == 'comfort'
                ? 'Relaxed routing is active.'
                : 'Live tracking is ready.',
            style: const TextStyle(
              color: Color(0xFFCFD8EA),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: crowdUi.color.withValues(alpha: 0.48),
                  ),
                ),
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      fontWeight: FontWeight.w700,
                    ),
                    children: [
                      const TextSpan(text: 'Crowd level: '),
                      TextSpan(
                        text: crowdUi.label,
                        style: TextStyle(
                          color: crowdUi.color,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(
                  arrivalLabel,
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => NavigationState.instance.goTo(2),
                icon: const Icon(Icons.track_changes_rounded),
                label: const Text('Open tracking'),
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeLiveTripStationPill extends StatelessWidget {
  final String stationName;
  final String routeId;

  const _HomeLiveTripStationPill({
    required this.stationName,
    required this.routeId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 210),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

class _StationCrowdBoard extends StatelessWidget {
  final Future<List<NearbyStationCrowdForecast>>? nearestCrowdFuture;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAllStations;

  const _StationCrowdBoard({
    required this.nearestCrowdFuture,
    required this.onRefresh,
    required this.onOpenAllStations,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.06),
        ),
        boxShadow: appCardShadows(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Station Crowd Board',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Showing the nearest station to your current location.',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpenAllStations,
                child: const Text('View all'),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<NearbyStationCrowdForecast>>(
            future: nearestCrowdFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator(minHeight: 3);
              }
              if (snapshot.hasError) {
                return Text(
                  'Failed to load crowd board: ${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFB42318)),
                );
              }
              final items =
                  snapshot.data ?? const <NearbyStationCrowdForecast>[];
              if (items.isEmpty) {
                return const Text(
                  'Location is still syncing. Pull to refresh or try again in a moment.',
                  style: TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                );
              }
              return _NearestStationCrowdCard(item: items.first);
            },
          ),
        ],
      ),
    );
  }
}

class _NearestStationCrowdCard extends StatelessWidget {
  final NearbyStationCrowdForecast item;

  const _NearestStationCrowdCard({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final occupancyLevel = item.forecast?.occupancyLevel ?? 0;
    final ui = _HomeCrowdUi.fromLevel(occupancyLevel);
    final statusTags = CrowdReportsService.statusTagsFor(
      sourceType: item.forecast?.sourceType ?? 'fallback',
      fromCache: item.forecast?.fromCache == true || item.fromCache,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _HomeLiveTripStationPill(
                  stationName: item.stationName,
                  routeId: item.routeId,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ui.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  ui.label,
                  style: TextStyle(
                    color: ui.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${item.stopId} | ${item.routeId}',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.distanceMeters.toStringAsFixed(0)} m away',
            style: const TextStyle(
              color: Color(0xFF98A2B3),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (statusTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            _StatusTagWrap(tags: statusTags),
          ],
          const SizedBox(height: 12),
          ScheduledArrivalsPanel(
            stopId: item.stopId,
            stationName: item.stationName,
            limit: 2,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _LegacyStationCrowdRow extends StatelessWidget {
  final StationCrowdBoardItem item;
  final VoidCallback onReportPacked;

  const _LegacyStationCrowdRow({
    required this.item,
    this.onReportPacked = _noop,
  });

  static void _noop() {}

  @override
  Widget build(BuildContext context) {
    final isClosed = item.isClosedHours;
    final ui = isClosed
        ? const _HomeCrowdUi(
            label: 'Closing hours',
            color: Color(0xFF98A2B3),
          )
        : _HomeCrowdUi.fromLevel(item.occupancyLevel);
    final routeSummary =
        item.routeIds.isEmpty ? 'N/A' : item.routeIds.join(' • ');
    final stopSummary = item.stopIds.join(', ');
    final statusTags = CrowdReportsService.statusTagsFor(
      sourceType: item.sourceType,
      fromCache: item.fromCache,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: ui.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.stationName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isClosed
                        ? const Color(0xFF667085)
                        : const Color(0xFF101828),
                  ),
                ),
                Text(
                  '${item.stopId} • ${CrowdReportsService.displaySourceType(item.sourceType)}',
                  style: TextStyle(
                    color: isClosed
                        ? const Color(0xFF98A2B3)
                        : const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                if (statusTags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _StatusTagWrap(tags: statusTags),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ui.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ui.label,
              style: TextStyle(
                color: ui.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onReportPacked,
            child: const Text('Report crowded'),
          ),
        ],
      ),
    );
  }
}

class _StationCrowdRow extends StatelessWidget {
  final StationCrowdBoardItem item;

  const _StationCrowdRow({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final isClosed = item.isClosedHours;
    final ui = isClosed
        ? const _HomeCrowdUi(
            label: 'Closing hours',
            color: Color(0xFF98A2B3),
          )
        : _HomeCrowdUi.fromLevel(item.occupancyLevel);
    final routeSummary =
        item.routeIds.isEmpty ? 'N/A' : item.routeIds.join(' • ');
    final stopSummary = item.stopIds.join(', ');
    final statusTags = CrowdReportsService.statusTagsFor(
      sourceType: item.sourceType,
      fromCache: item.fromCache,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: ui.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.stationName,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: isClosed
                        ? const Color(0xFF667085)
                        : const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$routeSummary • $stopSummary',
                  style: TextStyle(
                    color: isClosed
                        ? const Color(0xFF98A2B3)
                        : const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  CrowdReportsService.displaySourceType(item.sourceType),
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
                if (statusTags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _StatusTagWrap(tags: statusTags),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: ui.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ui.label,
              style: TextStyle(
                color: ui.color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTagWrap extends StatelessWidget {
  final List<String> tags;

  const _StatusTagWrap({
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: tags
          .map(
            (tag) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FC),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFDCE4F3)),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  color: Color(0xFF344054),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.06)),
          boxShadow: appCardShadows(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapStop {
  final String stopId;
  final String stopName;
  final String routeId;
  final double latitude;
  final double longitude;

  const _MapStop({
    required this.stopId,
    required this.stopName,
    required this.routeId,
    required this.latitude,
    required this.longitude,
  });
}

class _HomeRouteConnection {
  final String fromStopId;
  final String toStopId;
  final String routeId;
  final String connectionType;
  final int travelMinutes;

  const _HomeRouteConnection({
    required this.fromStopId,
    required this.toStopId,
    required this.routeId,
    required this.connectionType,
    required this.travelMinutes,
  });

  _HomeRouteConnection reversed() {
    return _HomeRouteConnection(
      fromStopId: toStopId,
      toStopId: fromStopId,
      routeId: routeId,
      connectionType: connectionType,
      travelMinutes: travelMinutes,
    );
  }
}

class _HomeDijkstraResult {
  final String destinationStopId;
  final List<_HomeRouteConnection> path;
  final int totalMinutes;
  final int weightedMinutes;

  const _HomeDijkstraResult({
    required this.destinationStopId,
    required this.path,
    required this.totalMinutes,
    required this.weightedMinutes,
  });
}

class _HomeRoutePreview {
  final String routePreference;
  final String originName;
  final String destinationName;
  final int highestCrowdLevel;
  final int totalMinutes;
  final List<String> routeLines;
  final int transferCount;
  final int stopCount;
  final List<ActiveTripStop> activeTripStops;
  final _HomeDijkstraResult result;

  const _HomeRoutePreview({
    required this.routePreference,
    required this.originName,
    required this.destinationName,
    required this.highestCrowdLevel,
    required this.totalMinutes,
    required this.routeLines,
    required this.transferCount,
    required this.stopCount,
    required this.activeTripStops,
    required this.result,
  });
}

class _HomeRouteChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final _HomeRoutePreview preview;
  final List<String> reasoningLabels;
  final String actionLabel;
  final bool isPrimary;
  final VoidCallback onTap;

  const _HomeRouteChoiceCard({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.reasoningLabels,
    required this.actionLabel,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final crowdUi = _HomeCrowdUi.fromLevel(preview.highestCrowdLevel);
    final button = isPrimary
        ? ElevatedButton(
            onPressed: onTap,
            child: Text(actionLabel),
          )
        : OutlinedButton(
            onPressed: onTap,
            child: Text(actionLabel),
          );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isPrimary ? const Color(0xFFBFD2F3) : const Color(0xFFD9E2F2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: crowdUi.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  crowdUi.label,
                  style: TextStyle(
                    color: crowdUi.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (reasoningLabels.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: reasoningLabels
                  .map(
                    (label) => _HomeRouteMetricChip(
                      label: label,
                      backgroundColor: isPrimary
                          ? const Color(0xFFEEF4FF)
                          : const Color(0xFFF4F7FC),
                      textColor: isPrimary
                          ? const Color(0xFF0A3A8B)
                          : const Color(0xFF344054),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HomeRouteMetricChip(
                label: 'ETA ${_formatMinutes(preview.totalMinutes)}',
              ),
              _HomeRouteMetricChip(
                label: preview.transferCount == 0
                    ? 'Direct ride'
                    : preview.transferCount == 1
                        ? '1 transfer'
                        : '${preview.transferCount} transfers',
              ),
              _HomeRouteMetricChip(
                label: preview.routeLines.isEmpty
                    ? 'Route pending'
                    : preview.routeLines.join(' | '),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: button),
        ],
      ),
    );
  }

  static String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }
}

class _HomeRouteMetricChip extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _HomeRouteMetricChip({
    required this.label,
    this.backgroundColor = const Color(0xFFF4F7FC),
    this.textColor = const Color(0xFF344054),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

int _compareStopCode(String a, String b) {
  final pa = _HomeStopIdParts.tryParse(a);
  final pb = _HomeStopIdParts.tryParse(b);
  if (pa == null || pb == null) return a.compareTo(b);
  if (pa.prefix != pb.prefix) return pa.prefix.compareTo(pb.prefix);
  if (pa.number != pb.number) return pa.number.compareTo(pb.number);
  return pa.suffix.compareTo(pb.suffix);
}

class _HomeStopIdParts {
  final String prefix;
  final int number;
  final String suffix;

  const _HomeStopIdParts({
    required this.prefix,
    required this.number,
    required this.suffix,
  });

  static _HomeStopIdParts? tryParse(String stopId) {
    final match = RegExp(r'^([A-Z]+)(\d+)([A-Z]*)$')
        .firstMatch(stopId.trim().toUpperCase());
    if (match == null) return null;
    final number = int.tryParse(match.group(2) ?? '');
    if (number == null) return null;
    return _HomeStopIdParts(
      prefix: match.group(1) ?? '',
      number: number,
      suffix: match.group(3) ?? '',
    );
  }
}
