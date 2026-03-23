import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/route_colors.dart';
import '../services/crowd_reports_service.dart';
import '../services/station_service.dart';
import '../widgets/map_preview.dart';
import '../widgets/prediction_card.dart';
import 'crowd_forecast_screen.dart';
import 'map_view.dart';
import 'route_planner.dart';
import 'stations_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  final StationService _stationService = StationService();
  final TextEditingController _routeSearchController = TextEditingController();
  Position? _position;
  String _locationStatus = 'Getting location...';
  bool _isLoadingLocation = false;
  Future<List<NearbyStationCrowdForecast>>? _nearestCrowdFuture;
  late Future<List<_HomeStationSearchOption>> _stationSearchFuture;
  Timer? _nearestAutoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _stationSearchFuture = _loadStationSearchOptions();
    _startNearestCrowdAutoRefresh();
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

  Future<void> _openInGoogleMaps() async {
    final position = _position;
    if (position == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location is not available yet.')),
      );
      return;
    }

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.')),
      );
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

  void _openMapWithDestination(String stationName) {
    final trimmed = stationName.trim();
    if (trimmed.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapView(initialDestinationName: trimmed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Commuter Assistant+'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HeroCard(theme: theme),
            const SizedBox(height: 12),
            _HomeRouteSearchCard(
              stationNamesFuture: _stationSearchFuture,
              controller: _routeSearchController,
              onStationSelected: _openMapWithDestination,
            ),
            const SizedBox(height: 12),
            _LocationCard(
              position: _position,
              status: _locationStatus,
              isLoading: _isLoadingLocation,
              onRefresh: _loadLocation,
              onOpenMap: _openInGoogleMaps,
            ),
            const SizedBox(height: 12),
            _NearestCrowdForecastCard(
              nearestCrowdFuture: _nearestCrowdFuture,
              hasLocation: _position != null,
              onRefresh: _refreshNearestCrowd,
            ),
            const SizedBox(height: 18),
            const PredictionCard(
              title: 'Next Train',
              station: 'KL Sentral',
              arrivalTime: '3 min',
              crowdLevel: 'Medium',
            ),
            const SizedBox(height: 12),
            const PredictionCard(
              title: 'Today Commute',
              station: 'KLCC -> Bukit Bintang',
              arrivalTime: '12 min',
              crowdLevel: 'Low',
            ),
            const SizedBox(height: 18),
            Text(
              'Quick Actions',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.route_rounded,
                    label: 'Plan Route',
                    subtitle: 'Fastest option',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RoutePlanner()),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.train_rounded,
                    label: 'All Stations',
                    subtitle: 'From Supabase',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StationsScreen()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ActionTile(
              icon: Icons.groups_rounded,
              label: 'Crowd Forecast',
              subtitle: 'AI + traffic light levels',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CrowdForecastScreen()),
              ),
            ),
            const SizedBox(height: 18),
            const MapPreview(),
          ],
        ),
      ),
    );
  }
}

class _HomeRouteSearchCard extends StatelessWidget {
  final Future<List<_HomeStationSearchOption>> stationNamesFuture;
  final TextEditingController controller;
  final ValueChanged<String> onStationSelected;

  const _HomeRouteSearchCard({
    required this.stationNamesFuture,
    required this.controller,
    required this.onStationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.route_rounded),
              SizedBox(width: 8),
              Text(
                'Find Route Fast',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<_HomeStationSearchOption>>(
            future: stationNamesFuture,
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
                onSelected: (option) => onStationSelected(option.stationName),
                fieldViewBuilder:
                    (context, textController, focusNode, onFieldSubmitted) {
                  if (textController.text != controller.text) {
                    textController.value = controller.value;
                  }
                  return TextField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Type destination station',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        onPressed: () {
                          final value = textController.text.trim();
                          if (value.isNotEmpty) {
                            onStationSelected(value);
                          }
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                        tooltip: 'Open map route',
                      ),
                    ),
                    onChanged: (_) {
                      controller.value = textController.value;
                    },
                    onSubmitted: (value) {
                      final text = value.trim();
                      if (text.isNotEmpty) {
                        onStationSelected(text);
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
                        width: 420,
                        margin: const EdgeInsets.only(top: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFDCE6F5)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1F101828),
                              blurRadius: 16,
                              offset: Offset(0, 8),
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
                            return ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(
                                horizontal: -1,
                                vertical: -2,
                              ),
                              leading: _HomeSearchRouteBadge(
                                routeIds: option.routeIds,
                              ),
                              title: Text(
                                option.stationName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              subtitle: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: option.stopCodes
                                    .map(
                                      (code) => _HomeSearchCodeChip(code: code),
                                    )
                                    .toList(),
                              ),
                              onTap: () => onSelected(option),
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
        ],
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

class _LocationCard extends StatelessWidget {
  final Position? position;
  final String status;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback onOpenMap;

  const _LocationCard({
    required this.position,
    required this.status,
    required this.isLoading,
    required this.onRefresh,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final latText =
        position == null ? '-' : position!.latitude.toStringAsFixed(6);
    final lonText =
        position == null ? '-' : position!.longitude.toStringAsFixed(6);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.my_location_rounded),
              const SizedBox(width: 8),
              const Text(
                'Current Location',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: isLoading ? null : onRefresh,
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh location',
              ),
            ],
          ),
          Text('Latitude: $latText'),
          Text('Longitude: $lonText'),
          const SizedBox(height: 4),
          Text(
            status,
            style: const TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: position == null ? null : onOpenMap,
            icon: const Icon(Icons.map_rounded),
            label: const Text('Open in Google Maps'),
          ),
        ],
      ),
    );
  }
}

class _NearestCrowdForecastCard extends StatelessWidget {
  final Future<List<NearbyStationCrowdForecast>>? nearestCrowdFuture;
  final bool hasLocation;
  final VoidCallback onRefresh;

  const _NearestCrowdForecastCard({
    required this.nearestCrowdFuture,
    required this.hasLocation,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.near_me_rounded),
              const SizedBox(width: 8),
              const Text(
                'Nearest Station Crowd',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: hasLocation ? onRefresh : null,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh nearest crowd',
              ),
            ],
          ),
          if (!hasLocation || nearestCrowdFuture == null)
            const Text(
              'Enable location to see nearest station crowd forecast.',
              style: TextStyle(color: Color(0xFF667085)),
            )
          else
            FutureBuilder<List<NearbyStationCrowdForecast>>(
              future: nearestCrowdFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Text(
                    'Failed to load nearest crowd forecast: ${snapshot.error}',
                    style: const TextStyle(color: Color(0xFFB42318)),
                  );
                }

                final items =
                    snapshot.data ?? const <NearbyStationCrowdForecast>[];
                if (items.isEmpty) {
                  return const Text(
                    'No nearby stations found with forecast data.',
                    style: TextStyle(color: Color(0xFF667085)),
                  );
                }

                return Column(
                  children: items
                      .map((item) => _NearestCrowdRow(item: item))
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _NearestCrowdRow extends StatelessWidget {
  final NearbyStationCrowdForecast item;

  const _NearestCrowdRow({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final level = item.forecast?.occupancyLevel ?? -1;
    final ui = _HomeCrowdUi.fromLevel(level);
    final distanceText = item.distanceMeters < 1000
        ? '${item.distanceMeters.toStringAsFixed(0)} m'
        : '${(item.distanceMeters / 1000).toStringAsFixed(2)} km';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: ui.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${item.stationName} (${item.stopId})',
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            distanceText,
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            ui.label,
            style: TextStyle(
              color: ui.color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCrowdUi {
  final String label;
  final Color color;

  const _HomeCrowdUi({
    required this.label,
    required this.color,
  });

  static _HomeCrowdUi fromLevel(int level) {
    switch (level) {
      case 0:
        return const _HomeCrowdUi(label: 'Empty', color: Color(0xFF16A34A));
      case 1:
        return const _HomeCrowdUi(label: 'Moderate', color: Color(0xFFF59E0B));
      case 2:
        return const _HomeCrowdUi(label: 'Crowded', color: Color(0xFFF97316));
      case 3:
        return const _HomeCrowdUi(label: 'Crush', color: Color(0xFFDC2626));
      default:
        return const _HomeCrowdUi(label: 'Unknown', color: Color(0xFF667085));
    }
  }
}

class _HeroCard extends StatelessWidget {
  final ThemeData theme;

  const _HeroCard({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF0D3F96), Color(0xFFB7162C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good Morning',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Peak window starts in 34 minutes. Recommended: leave before 8:10 AM.',
            style: TextStyle(color: Colors.white, height: 1.35),
          ),
          SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(icon: Icons.cloud, label: 'Rain 2.1mm'),
              _StatusChip(icon: Icons.timer, label: 'Avg delay 4m'),
              _StatusChip(icon: Icons.groups, label: 'Crowd medium'),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE3EAF7)),
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
