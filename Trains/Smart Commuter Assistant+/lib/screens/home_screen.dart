// ignore_for_file: unused_element, unused_element_parameter, unused_local_variable

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../services/active_trip_service.dart';
import '../services/crowd_reports_service.dart';
import '../services/database_service.dart';
import '../services/navigation_state.dart';
import '../services/station_service.dart';
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
  final DatabaseService _databaseService = DatabaseService();
  final StationService _stationService = StationService();
  final TextEditingController _routeSearchController = TextEditingController();
  Position? _position;
  String _locationStatus = 'Getting location...';
  bool _isLoadingLocation = false;
  bool _isPreparingTrip = false;
  Future<List<NearbyStationCrowdForecast>>? _nearestCrowdFuture;
  late Future<List<_HomeStationSearchOption>> _stationSearchFuture;
  Timer? _nearestAutoRefreshTimer;
  bool _isLoadingMap = true;
  String? _mapError;
  final Map<String, _MapStop> _mapStopsById = <String, _MapStop>{};
  DateTime _departureTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _loadMapStops();
    _stationSearchFuture = _loadStationSearchOptions();
    _startNearestCrowdAutoRefresh();
  }

  void _handleStationSelected(_HomeStationSearchOption option) {
    unawaited(_prepareTrip(option));
  }

  Future<void> _prepareTrip(_HomeStationSearchOption option) async {
    if (_isPreparingTrip) return;
    setState(() => _isPreparingTrip = true);
    try {
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

      final destinationStopId = option.stopCodes.isEmpty
          ? option.stationName
          : option.stopCodes.first;
      final forecasts = option.stopCodes.isEmpty
          ? <String, StopCrowdForecast>{}
          : await _crowdReportsService.fetchForecastForStopsAtTime(
              option.stopCodes,
              _departureTime,
            );
      var highestCrowdLevel = 0;
      for (final forecast in forecasts.values) {
        if (forecast.occupancyLevel > highestCrowdLevel) {
          highestCrowdLevel = forecast.occupancyLevel;
        }
      }

      var routePreference = 'efficiency';
      if (highestCrowdLevel > 1) {
        final useComfort = await _showPackedRoutePrompt(option.stationName);
        if (useComfort == null) return;
        routePreference = useComfort ? 'comfort' : 'efficiency';
      }

      final nearestStop = nearestStops.first;
      final placeholderStops = <ActiveTripStop>[
        ActiveTripStop(
          stopId: nearestStop.stopId,
          stopName: nearestStop.stopName,
          routeId: nearestStop.routeId,
        ),
        ActiveTripStop(
          stopId: destinationStopId,
          stopName: option.stationName,
          routeId: option.routeIds.isEmpty ? 'N/A' : option.routeIds.first,
        ),
      ];

      await _activeTripService.saveTrip(
        ActiveTrip(
          originStopId: nearestStop.stopId,
          destinationStopId: destinationStopId,
          originName: nearestStop.stopName,
          destinationName: option.stationName,
          routePreference: routePreference,
          highestCrowdLevel: highestCrowdLevel,
          createdAt: DateTime.now(),
          stops: placeholderStops,
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
                        'Looks like your route is packed.',
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

  void _showHomeMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _nearestAutoRefreshTimer?.cancel();
    _routeSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationStatus = 'Location service is disabled');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        setState(() => _locationStatus = 'Location permission denied');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _locationStatus = 'Location permission denied forever');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _position = position;
        _locationStatus = 'Location updated';
        _nearestCrowdFuture =
            _crowdReportsService.fetchNearestStationsWithCrowd(
          latitude: position.latitude,
          longitude: position.longitude,
          departureTime: DateTime.now(),
          limit: 5,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _locationStatus = 'Location error: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
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

  Future<void> _loadMapStops() async {
    if (mounted) {
      setState(() {
        _isLoadingMap = true;
        _mapError = null;
      });
    }
    try {
      final rows = <Map<String, dynamic>>[];
      try {
        final remoteRows = await Supabase.instance.client
            .from('train_stops_kl')
            .select('stop_id,stop_name,stop_lat,stop_lon,route_id');
        final maps = remoteRows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        rows.addAll(maps);
        if (maps.isNotEmpty) {
          await _databaseService.cacheTrainStops(maps);
        }
      } catch (_) {}

      if (rows.isEmpty) {
        final cachedRows = await _databaseService.getCachedTrainStops();
        rows.addAll(
          cachedRows.map((row) => Map<String, dynamic>.from(row)),
        );
      }

      _mapStopsById.clear();
      for (final row in rows) {
        final stopId = (row['stop_id']?.toString() ?? '').trim().toUpperCase();
        final stopName = (row['stop_name']?.toString() ?? '').trim();
        final lat = _toDouble(row['stop_lat']);
        final lon = _toDouble(row['stop_lon']);
        if (stopId.isEmpty || stopName.isEmpty || lat == null || lon == null) {
          continue;
        }
        _mapStopsById[stopId] = _MapStop(
          stopId: stopId,
          stopName: stopName,
          routeId: normalizeRouteId(
            (row['route_id']?.toString() ?? _inferRouteIdFromStopId(stopId))
                .trim()
                .toUpperCase(),
          ),
          latitude: lat,
          longitude: lon,
        );
      }

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
    final groupedRows = <String, List<Map<String, dynamic>>>{};

    void collectRows(List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        final stationName =
            (row['stop_name'] ?? row['station_name'] ?? '').toString().trim();
        if (stationName.isEmpty) continue;
        groupedRows
            .putIfAbsent(stationName, () => <Map<String, dynamic>>[])
            .add(
              row,
            );
      }
    }

    try {
      final stopRows = await Supabase.instance.client
          .from('train_stops_kl')
          .select('stop_name,stop_id,route_id');
      final mappedRows = stopRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      collectRows(mappedRows);
      if (groupedRows.isNotEmpty) {
        return _buildSearchOptions(groupedRows);
      }
    } catch (_) {
      // Fallback below.
    }

    try {
      final rows = await _stationService.getUniqueStations();
      collectRows(rows);
      if (groupedRows.isNotEmpty) {
        return _buildSearchOptions(groupedRows);
      }
    } catch (_) {
      // Final fallback below.
    }

    final fallbackOptions = await _crowdReportsService.fetchStationOptions();
    for (final option in fallbackOptions) {
      final station = option.stationName.trim();
      if (station.isEmpty) continue;
      groupedRows.putIfAbsent(station, () => <Map<String, dynamic>>[]).add(
        <String, dynamic>{
          'station_name': station,
          'stop_id': option.stopId,
          'route_id': _inferRouteIdFromStopId(option.stopId),
        },
      );
    }
    return _buildSearchOptions(groupedRows);
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

  Future<void> _pickDepartureTime() async {
    final now = DateTime.now();
    final initial = _departureTime.isAfter(now) ? _departureTime : now;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) return;
    setState(() {
      _departureTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
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
        title: const _HomeAppTitle(),
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
                    status: _isLoadingLocation
                        ? 'Refreshing live location...'
                        : _locationStatus,
                    networkSource: _isLoadingMap
                        ? 'Syncing live station map...'
                        : _mapError == null
                            ? 'Live station map ready'
                            : 'Live station map offline',
                  ),
                  const SizedBox(height: 16),
                  _HomeRouteSearchCard(
                    stationNamesFuture: _stationSearchFuture,
                    controller: _routeSearchController,
                    departureLabel: _formatDepartureTime(_departureTime),
                    onPickTime: _pickDepartureTime,
                    onStationSelected: _handleStationSelected,
                    nearestCrowdFuture: _nearestCrowdFuture,
                    isPreparingTrip: _isPreparingTrip,
                  ),
                  const SizedBox(height: 16),
                  if (_mapError != null)
                    _InlineHomeError(
                      message: _mapError!,
                      onRetry: _loadMapStops,
                    )
                  else
                    const SizedBox.shrink(),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<ActiveTrip?>(
                    valueListenable: _activeTripService.activeTrip,
                    builder: (context, trip, _) {
                      if (trip == null) {
                        return const SizedBox.shrink();
                      }
                      return _LiveTripSummary(
                        trip: trip,
                        onOpenMap: _openMapTab,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
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

class _HomeRouteSearchCard extends StatefulWidget {
  final Future<List<_HomeStationSearchOption>> stationNamesFuture;
  final TextEditingController controller;
  final String departureLabel;
  final VoidCallback onPickTime;
  final ValueChanged<_HomeStationSearchOption> onStationSelected;
  final Future<List<NearbyStationCrowdForecast>>? nearestCrowdFuture;
  final bool isPreparingTrip;

  const _HomeRouteSearchCard({
    required this.stationNamesFuture,
    required this.controller,
    required this.departureLabel,
    required this.onPickTime,
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

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset > 0 ? 12 : 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.08)),
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
              'Search a destination and the app will switch to a calmer path when the direct option feels too packed.',
              style: TextStyle(
                color: Color(0xFF667085),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.isPreparingTrip) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 3),
            ],
            const SizedBox(height: 16),
            FutureBuilder<List<_HomeStationSearchOption>>(
              future: widget.stationNamesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: LinearProgressIndicator(minHeight: 2),
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
                  return const Text(
                    'No station names available yet.',
                    style: TextStyle(color: Color(0xFF667085)),
                  );
                }

                return Autocomplete<_HomeStationSearchOption>(
                  optionsBuilder: (value) {
                    final query = value.text.trim().toLowerCase();
                    if (query.isEmpty) {
                      return const Iterable<_HomeStationSearchOption>.empty();
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
                  onSelected: widget.onStationSelected,
                  fieldViewBuilder:
                      (context, textController, focusNode, onFieldSubmitted) {
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
                        fillColor:
                            Theme.of(context).inputDecorationTheme.fillColor,
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          onPressed: widget.onPickTime,
                          icon: const Icon(Icons.schedule_rounded),
                          tooltip: 'Choose departure time',
                        ),
                      ),
                      onTap: _ensureFieldVisible,
                      onChanged: (_) {
                        widget.controller.value = textController.value;
                      },
                      onSubmitted: (value) {
                        final text = value.trim();
                        if (text.isNotEmpty) {
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
                          widget.onStationSelected(match);
                        }
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
                                    .withValues(alpha: 0.06)),
                            boxShadow: appCardShadows(context),
                          ),
                          child:
                              FutureBuilder<List<NearbyStationCrowdForecast>>(
                            future: widget.nearestCrowdFuture,
                            builder: (context, crowdSnapshot) {
                              final crowdMap =
                                  <String, NearbyStationCrowdForecast>{};
                              if (crowdSnapshot.hasData) {
                                for (final forecast in crowdSnapshot.data!) {
                                  crowdMap[forecast.stationName.toUpperCase()] =
                                      forecast;
                                }
                              }

                              return ListView.separated(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                shrinkWrap: true,
                                itemCount: optionList.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1, thickness: 0.6),
                                itemBuilder: (context, index) {
                                  final option = optionList[index];
                                  final crowdForecast = crowdMap[
                                      option.stationName.toUpperCase()];
                                  final crowdUi = crowdForecast != null
                                      ? _HomeCrowdUi.fromLevel(crowdForecast
                                              .forecast?.occupancyLevel ??
                                          1)
                                      : null;

                                  return ListTile(
                                    dense: true,
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
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                        if (crowdUi != null) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
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
                                            (code) =>
                                                _HomeSearchCodeChip(code: code),
                                          )
                                          .toList(),
                                    ),
                                    onTap: () => onSelected(option),
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
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: widget.onPickTime,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: Theme.of(context)
                          .dividerColor
                          .withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_filled_rounded, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      widget.departureLabel,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ],
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

class _HomeAppTitle extends StatelessWidget {
  const _HomeAppTitle();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Smart ',
                style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF0A3A8B),
                    ),
              ),
              TextSpan(
                text: 'Commuter',
                style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A3A8B),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'ASSISTANT+',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  final ThemeData theme;
  final String title;
  final String subtitle;
  final String status;
  final String networkSource;

  const _HeroCard({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.networkSource,
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(icon: Icons.my_location_rounded, label: status),
              _StatusChip(icon: Icons.hub_rounded, label: networkSource),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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
    final originRouteId =
        trip.stops.isEmpty ? 'N/A' : normalizeRouteId(trip.stops.first.routeId);
    final destinationRouteId =
        trip.stops.isEmpty ? 'N/A' : normalizeRouteId(trip.stops.last.routeId);
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
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Crowd level: ${_HomeCrowdUi.fromLevel(trip.highestCrowdLevel).label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
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
    final ui = _HomeCrowdUi.fromLevel(item.occupancyLevel);
    final routeSummary =
        item.routeIds.isEmpty ? 'N/A' : item.routeIds.join(' • ');
    final stopSummary = item.stopIds.join(', ');
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${item.stopId} • ${item.sourceType}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
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
            child: const Text('Report packed'),
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
    final ui = _HomeCrowdUi.fromLevel(item.occupancyLevel);
    final routeSummary =
        item.routeIds.isEmpty ? 'N/A' : item.routeIds.join(' • ');
    final stopSummary = item.stopIds.join(', ');

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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$routeSummary • $stopSummary',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  item.sourceType,
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
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

String _formatDepartureTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return 'Depart $day/$month $hour:$minute $suffix';
}
