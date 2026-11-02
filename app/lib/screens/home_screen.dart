// ignore_for_file: unused_element, unused_element_parameter, unused_local_variable

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/active_trip_service.dart';
import '../services/crowd_reports_service.dart';
import '../services/location_privacy_service.dart';
import '../services/navigation_state.dart';
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
  Timer? _routeProgressTimer;
  bool _isLoadingMap = true;
  String? _mapError;
  final Map<String, _MapStop> _mapStopsById = <String, _MapStop>{};
  final List<_HomeRouteConnection> _routeConnections = <_HomeRouteConnection>[];
  DateTime _departureTime = DateTime.now();
  _HomeRouteMode _routeMode = _HomeRouteMode.auto;

  @override
  void initState() {
    super.initState();
    LocationPrivacyService.consent.addListener(_onLocationConsentChanged);
    _loadLocation();
    _loadMapStops();
    _stationSearchFuture = _loadStationSearchOptions();
    _stationClosedByStopFuture = _stationSearchFuture.then(
      (options) => _loadStationClosedByStop(options, _departureTime),
    );
    _startNearestCrowdAutoRefresh();
    _startActiveTripProgressRefresh();
  }

  void _onLocationConsentChanged() {
    if (!mounted) return;
    if (LocationPrivacyService.consent.value) {
      _loadLocation();
    } else {
      setState(() {
        _position = null;
        _nearestCrowdFuture =
            Future.value(const <NearbyStationCrowdForecast>[]);
      });
    }
  }

  void _handleStationSelected(_HomeStationSearchOption option) {
    unawaited(_prepareTrip(option));
  }

  Future<void> _prepareTrip(_HomeStationSearchOption option) async {
    if (_isPreparingTrip) return;
    final l10n = AppLocalizations.of(context);
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
          l10n.homeStationUnavailableClosingHours(option.stationName),
        );
        return;
      }

      var position = _position;
      if (position == null) {
        await _loadLocation();
        position = _position;
      }
      if (!mounted || position == null) {
        _showHomeMessage(l10n.homeLocationRequired);
        return;
      }

      final nearestStops = _nearestMapStops(limit: 1);
      if (nearestStops.isEmpty) {
        _showHomeMessage(l10n.homeNearestStationUnavailable);
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
          _showHomeMessage(l10n.homeNoRouteFound(option.stationName));
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
      _showHomeMessage(l10n.homePrepareTripFailed(e.toString()));
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
    final l10n = AppLocalizations.of(context);
    final efficientReasoning = _buildChoiceReasoningLabels(
      preview: efficientPreview,
      comparison: relaxedPreview,
      prioritizeCrowd: false,
      l10n: l10n,
    );
    final relaxedReasoning = _buildChoiceReasoningLabels(
      preview: relaxedPreview,
      comparison: efficientPreview,
      prioritizeCrowd: true,
      l10n: l10n,
    );
    return showModalBottomSheet<_HomeRoutePreview>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final sheetL10n = AppLocalizations.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.sentiment_dissatisfied_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        sheetL10n.homeRouteCrowdedTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  sheetL10n.homeCalmerTripAvailable(destinationName),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                _HomeRouteChoiceCard(
                  title: sheetL10n.homeEfficientRoute,
                  subtitle: sheetL10n.homeFastestOptionNow,
                  preview: efficientPreview,
                  reasoningLabels: efficientReasoning,
                  actionLabel: sheetL10n.homeKeepThisRoute,
                  isPrimary: false,
                  onTap: () => Navigator.of(context).pop(efficientPreview),
                ),
                const SizedBox(height: 10),
                _HomeRouteChoiceCard(
                  title: sheetL10n.homeRelaxedRoute,
                  subtitle: sheetL10n.homeCalmerRideDetour,
                  preview: relaxedPreview,
                  reasoningLabels: relaxedReasoning,
                  actionLabel: sheetL10n.homeTakeRelaxedRoute,
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
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx);
        return AlertDialog(
          title: Text(l10n.homeLocationPrivacyTitle),
          content: Text(l10n.homeLocationPrivacyBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.homeSkip),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.homeAllow),
            ),
          ],
        );
      },
    );
    if (result == true) {
      await LocationPrivacyService.setConsent(true);
    } else {
      await LocationPrivacyService.markAsked();
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
    required AppLocalizations l10n,
  }) {
    final labels = <String>[];
    final crowdDelta = comparison.highestCrowdLevel - preview.highestCrowdLevel;
    final crowdLabel = _formatCrowdDeltaLabel(crowdDelta, l10n);
    final timeLabel = _formatTimeDeltaLabel(
      preview.totalMinutes - comparison.totalMinutes,
      preferNoPenalty: prioritizeCrowd,
      l10n: l10n,
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
    labels.add(_formatTransferCountLabel(preview.transferCount, l10n));
    return labels;
  }

  String? _formatCrowdDeltaLabel(int delta, AppLocalizations l10n) {
    if (delta == 0) return null;
    final magnitude = delta.abs();
    return delta > 0
        ? l10n.homeCrowdLevelsLower(magnitude)
        : l10n.homeCrowdLevelsHigher(magnitude);
  }

  String? _formatTimeDeltaLabel(
    int delta, {
    required bool preferNoPenalty,
    required AppLocalizations l10n,
  }) {
    if (delta < 0) return l10n.homeFastest;
    if (delta == 0) {
      return preferNoPenalty ? l10n.homeNoTimePenalty : l10n.homeFastest;
    }
    return l10n.homePlusMinutes(delta);
  }

  String _formatTransferCountLabel(int count, AppLocalizations l10n) {
    if (count <= 0) return l10n.homeDirectRide;
    return l10n.homeTransferCount(count);
  }

  @override
  void dispose() {
    LocationPrivacyService.consent.removeListener(_onLocationConsentChanged);
    _nearestAutoRefreshTimer?.cancel();
    _routeProgressTimer?.cancel();
    _routeSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    try {
      final consented = await LocationPrivacyService.hasConsent();
      if (!consented) {
        if (await LocationPrivacyService.hasBeenAsked()) return;
        final result = await _showLocationConsentDialog();
        if (result != true || !mounted) return;
      }

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

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      ).catchError((Object error) async {
        debugPrint('Home location: current position failed: $error');
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown == null) {
          throw error;
        }
        return lastKnown;
      });
      if (!mounted) return;
      setState(() {
        _position = position;
        _nearestCrowdFuture =
            _crowdReportsService.fetchNearestStationsWithCrowd(
          latitude: position.latitude,
          longitude: position.longitude,
          departureTime: DateTime.now(),
          limit: 5,
        );
      });
      debugPrint(
        'Home location: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint('Home location failed: $e');
      if (!mounted) return;
    }
  }

  void _refreshNearestCrowd() {
    final position = _position;
    if (position == null) return;
    setState(() {
      _nearestCrowdFuture = _crowdReportsService.fetchNearestStationsWithCrowd(
        latitude: position.latitude,
        longitude: position.longitude,
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

  void _startActiveTripProgressRefresh() {
    _routeProgressTimer?.cancel();
    _routeProgressTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        if (!mounted) return;
        unawaited(_refreshActiveTripProgress());
      },
    );
  }

  Future<void> _refreshActiveTripProgress() async {
    final trip = _activeTripService.activeTrip.value;
    if (trip == null || trip.stops.length < 2) return;
    if (trip.currentStopIndex >= trip.stops.length - 1) return;

    final position = await _bestAvailablePosition();
    int? candidate;
    if (position != null) {
      final nearest = _nearestTripStopIndex(trip, position);
      if (nearest != null) candidate = nearest;
    }
    candidate ??= _estimatedTripStopIndex(trip);
    if (candidate == null) return;

    final capped = math.min(candidate, trip.currentStopIndex + 2);
    await _activeTripService.updateProgress(capped);
  }

  Future<Position?> _bestAvailablePosition() async {
    final cached = _position;
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          (cached == null || !lastKnown.timestamp.isBefore(cached.timestamp))) {
        return lastKnown;
      }
    } catch (_) {}
    return cached;
  }

  int? _nearestTripStopIndex(ActiveTrip trip, Position position) {
    int? bestIndex;
    var bestDistance = double.infinity;
    for (var i = 0; i < trip.stops.length; i++) {
      final stop = _mapStopsById[trip.stops[i].stopId];
      if (stop == null) continue;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    if (bestIndex == null || bestDistance > 900) return null;
    return bestIndex;
  }

  int? _estimatedTripStopIndex(ActiveTrip trip) {
    final total = trip.estimatedTotalMinutes;
    if (total == null || total <= 0) return null;
    final elapsed = DateTime.now().difference(trip.createdAt);
    if (elapsed.isNegative) return trip.currentStopIndex;
    if (elapsed > Duration(minutes: total * 2 + 30)) return null;
    final fraction = (elapsed.inMinutes / total).clamp(0.0, 1.0);
    final index = (fraction * (trip.stops.length - 1)).floor();
    return index.clamp(0, trip.stops.length - 1).toInt();
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        toolbarHeight: 78,
        title: AppPageTitle(
          icon: Icons.train_rounded,
          leadingText: 'Smart',
          accentText: 'Commuter',
          badgeText: 'ASSISTANT+',
          subtitle: l10n.homeSubtitle,
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
                    title: l10n.homeHeroTitle,
                    subtitle: l10n.homeHeroSubtitle,
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
                          label: l10n.homeAllStations,
                          subtitle: l10n.homeAllStationsSubtitle,
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
                              label: trip == null
                                  ? l10n.homeTrackRoute
                                  : l10n.homeResumeTrip,
                              subtitle: trip == null
                                  ? l10n.homeStartTripHint
                                  : l10n.homeTripDirection(
                                      trip.originName,
                                      trip.destinationName,
                                    ),
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
  String label(AppLocalizations l10n) {
    switch (this) {
      case _HomeRouteMode.auto:
        return l10n.homeRouteModeAuto;
      case _HomeRouteMode.efficiency:
        return l10n.homeRouteModeEfficient;
      case _HomeRouteMode.comfort:
        return l10n.homeRouteModeRelaxed;
    }
  }

  String helperText(AppLocalizations l10n) {
    switch (this) {
      case _HomeRouteMode.auto:
        return l10n.homeRouteModeAutoHelper;
      case _HomeRouteMode.efficiency:
        return l10n.homeRouteModeEfficientHelper;
      case _HomeRouteMode.comfort:
        return l10n.homeRouteModeComfortHelper;
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
    final l10n = AppLocalizations.of(context);

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
            Text(
              l10n.homePickNextStop,
              style: const TextStyle(
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.homeSearchDestinationHint,
              style: const TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.homeRouteStyle,
              style: const TextStyle(
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
              widget.routeMode.helperText(l10n),
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      l10n.homeLoadingStations,
                      style: const TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    l10n.homeLoadStationsFailed(snapshot.error.toString()),
                    style: const TextStyle(color: Color(0xFFB42318)),
                  );
                }

                final stationOptions =
                    snapshot.data ?? const <_HomeStationSearchOption>[];
                if (stationOptions.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.homeNoStationNames,
                      style: const TextStyle(color: Color(0xFF667085)),
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
                            l10n.homeStationUnavailableClosingHours(
                              option.stationName,
                            ),
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
                            hintText: l10n.homeSearchTrainStation,
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
                                              ? _HomeCrowdUi(
                                                  label: l10n.homeClosingHours,
                                                  color: const Color(
                                                      0xFF98A2B3),
                                                )
                                              : _HomeCrowdUi.fromLevel(
                                                  l10n,
                                                  crowdForecast.forecast
                                                          ?.occupancyLevel ??
                                                      1,
                                                )
                                          : optionClosed
                                              ? _HomeCrowdUi(
                                                  label: l10n.homeClosingHours,
                                                  color: const Color(
                                                      0xFF98A2B3),
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
                label: Text(l10n.homePlanAhead,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
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
    final l10n = AppLocalizations.of(context);
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
          mode.label(l10n),
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

  static _HomeCrowdUi fromLevel(AppLocalizations l10n, int level) {
    final crowd = crowdLevelStyleFromIndex(level);
    return _HomeCrowdUi(
        label: localizedCrowdLevelLabel(l10n, level), color: crowd.color);
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
    final l10n = AppLocalizations.of(context);
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
          Text(
            l10n.homeLiveMapUnavailable,
            style: const TextStyle(
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
            label: Text(l10n.retry),
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
    final l10n = AppLocalizations.of(context);
    final progressWindow = buildTripProgressWindow(trip);
    final crowdUi = _HomeCrowdUi.fromLevel(l10n, trip.highestCrowdLevel);
    final estimatedArrivalTime = trip.estimatedArrivalTime;
    final arrivalLabel = switch (estimatedArrivalTime) {
      null => l10n.homeEtaSyncing,
      final value when value.isBefore(DateTime.now()) => l10n.homeArrivingNow,
      final value => l10n.homeArriveBy(
          localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))),
    };
    final minutesToDestination =
        estimatedArrivalTime?.difference(DateTime.now()).inMinutes;
    final progressLabel = switch (minutesToDestination) {
      null => trip.routePreference == 'comfort'
          ? l10n.homeRelaxedRoutingActive
          : l10n.homeLiveTrackingReady,
      final minutes when minutes <= 0 => l10n.homeArrivingNow,
      final minutes => l10n.homeTripEtaTo(minutes, trip.destinationName),
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
                  l10n.homeLiveTrip,
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
                  l10n.homeViewMap,
                  style: TextStyle(color: theme.colorScheme.onPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HomeTripProgressRail(window: progressWindow),
          const SizedBox(height: 10),
          Text(
            progressLabel,
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
                      TextSpan(text: l10n.homeCrowdLevelPrefix),
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
                label: Text(l10n.homeOpenTracking),
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

class _HomeTripProgressRail extends StatelessWidget {
  final TripProgressWindow window;

  const _HomeTripProgressRail({required this.window});

  @override
  Widget build(BuildContext context) {
    final entries = window.visible;
    if (entries.isEmpty) return const SizedBox.shrink();

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          const moreWidth = 26.0;
          final gaps = (entries.length - 1) + (window.hasMore ? 1 : 0);
          final nodeWidth =
              ((constraints.maxWidth - moreWidth - gaps * gap) / entries.length)
                  .clamp(52.0, 104.0);
          final fontSize = nodeWidth < 66 ? 9.0 : 10.0;

          final children = <Widget>[];
          for (var i = 0; i < entries.length; i++) {
            if (i > 0) {
              children.add(
                _HomeTripRailConnector(
                  width: gap,
                  color: Colors.white.withValues(alpha: i == 1 ? 0.85 : 0.4),
                ),
              );
            }
            children.add(
              _HomeTripRailNode(
                name: entries[i].stopName,
                routeId: entries[i].routeId,
                isCurrent: i == 0,
                width: nodeWidth,
                fontSize: fontSize,
              ),
            );
          }
          if (window.hasMore) {
            children.add(
              _HomeTripRailConnector(
                width: gap,
                color: Colors.white.withValues(alpha: 0.28),
              ),
            );
            children.add(const _HomeTripRailMore(width: moreWidth));
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          );
        },
      ),
    );
  }
}

class _HomeTripRailNode extends StatelessWidget {
  final String name;
  final String routeId;
  final bool isCurrent;
  final double width;
  final double fontSize;

  const _HomeTripRailNode({
    required this.name,
    required this.routeId,
    required this.isCurrent,
    required this.width,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final color = getRouteColor(routeId);
    final onColor = getRouteOnColor(routeId);
    return SizedBox(
      width: width,
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: Center(
              child: Container(
                width: isCurrent ? 20 : 12,
                height: isCurrent ? 20 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCurrent ? color : Colors.transparent,
                  border: Border.all(
                    color:
                        isCurrent ? Colors.white : color.withValues(alpha: 0.9),
                    width: isCurrent ? 3 : 2,
                  ),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: isCurrent
                    ? Center(
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: onColor,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.15,
              fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w600,
              color: Colors.white.withValues(alpha: isCurrent ? 1 : 0.72),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTripRailConnector extends StatelessWidget {
  final Color color;
  final double width;

  const _HomeTripRailConnector({
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Container(
        width: width,
        height: 2,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _HomeTripRailMore extends StatelessWidget {
  final double width;

  const _HomeTripRailMore({required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SizedBox(
        height: 20,
        child: Center(
          child: Icon(
            Icons.more_horiz_rounded,
            size: 20,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
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
    final l10n = AppLocalizations.of(context);
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.homeStationCrowdBoard,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.homeNearestStationSubtitle,
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpenAllStations,
                child: Text(l10n.homeViewAll),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: l10n.homeRefreshNearbyStations,
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
                  l10n.homeLoadCrowdBoardFailed(snapshot.error.toString()),
                  style: const TextStyle(color: Color(0xFFB42318)),
                );
              }
              final items =
                  snapshot.data ?? const <NearbyStationCrowdForecast>[];
              if (items.isEmpty) {
                return Text(
                  l10n.homeLocationSyncing,
                  style: const TextStyle(
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
    final l10n = AppLocalizations.of(context);
    final occupancyLevel = item.forecast?.occupancyLevel ?? 0;
    final ui = _HomeCrowdUi.fromLevel(l10n, occupancyLevel);
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
            l10n.homeMetersAway(item.distanceMeters.toStringAsFixed(0)),
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
    final l10n = AppLocalizations.of(context);
    final isClosed = item.isClosedHours;
    final ui = isClosed
        ? _HomeCrowdUi(
            label: l10n.homeClosingHours,
            color: const Color(0xFF98A2B3),
          )
        : _HomeCrowdUi.fromLevel(l10n, item.occupancyLevel);
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
            child: Text(l10n.homeReportCrowded),
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
    final l10n = AppLocalizations.of(context);
    final isClosed = item.isClosedHours;
    final ui = isClosed
        ? _HomeCrowdUi(
            label: l10n.homeClosingHours,
            color: const Color(0xFF98A2B3),
          )
        : _HomeCrowdUi.fromLevel(l10n, item.occupancyLevel);
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
    final l10n = AppLocalizations.of(context);
    final crowdUi = _HomeCrowdUi.fromLevel(l10n, preview.highestCrowdLevel);
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
                label: l10n.homeEtaLabel(_formatMinutes(l10n, preview.totalMinutes)),
              ),
              _HomeRouteMetricChip(
                label: preview.transferCount == 0
                    ? l10n.homeDirectRide
                    : l10n.homeTransferCount(preview.transferCount),
              ),
              _HomeRouteMetricChip(
                label: preview.routeLines.isEmpty
                    ? l10n.homeRoutePending
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

  static String _formatMinutes(AppLocalizations l10n, int minutes) {
    if (minutes < 60) return l10n.homeDurationMinutesShort(minutes);
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return l10n.homeDurationHoursShort(hours);
    return l10n.homeDurationHoursMinutesShort(hours, mins);
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
