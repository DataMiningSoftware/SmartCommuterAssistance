import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/crowd_reports_service.dart';
import '../widgets/map_preview.dart';
import '../widgets/prediction_card.dart';
import 'crowd_forecast_screen.dart';
import 'route_planner.dart';
import 'stations_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  Position? _position;
  String _locationStatus = 'Getting location...';
  bool _isLoadingLocation = false;
  late Future<List<CrowdReportDisplayItem>> _crowdFeedFuture;
  Future<List<NearbyStationCrowdForecast>>? _nearestCrowdFuture;

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _crowdFeedFuture =
        _crowdReportsService.fetchLatestCrowdDisplayFeed(limit: 5);
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

  void _refreshCrowdFeed() {
    setState(() {
      _crowdFeedFuture =
          _crowdReportsService.fetchLatestCrowdDisplayFeed(limit: 5);
    });
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
            const SizedBox(height: 12),
            _HomeCrowdFeedCard(
              crowdFeedFuture: _crowdFeedFuture,
              onRefresh: _refreshCrowdFeed,
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

class _HomeCrowdFeedCard extends StatelessWidget {
  final Future<List<CrowdReportDisplayItem>> crowdFeedFuture;
  final VoidCallback onRefresh;

  const _HomeCrowdFeedCard({
    required this.crowdFeedFuture,
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
              const Icon(Icons.groups_rounded),
              const SizedBox(width: 8),
              const Text(
                'Latest Crowd Predictions',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh crowd data',
              ),
            ],
          ),
          FutureBuilder<List<CrowdReportDisplayItem>>(
            future: crowdFeedFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Failed to load crowd feed: ${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFB42318)),
                );
              }

              final items = snapshot.data ?? const <CrowdReportDisplayItem>[];
              if (items.isEmpty) {
                return const Text(
                  'No crowd prediction data yet.',
                  style: TextStyle(color: Color(0xFF667085)),
                );
              }

              return Column(
                children:
                    items.map((item) => _CrowdFeedRow(item: item)).toList(),
              );
            },
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
    final ui = _CrowdFeedRow._crowdUiByLevel(level);
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

class _CrowdFeedRow extends StatelessWidget {
  final CrowdReportDisplayItem item;

  const _CrowdFeedRow({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final ui = _crowdUiByLevel(item.occupancyLevel);
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

  static _HomeCrowdUi _crowdUiByLevel(int level) {
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

class _HomeCrowdUi {
  final String label;
  final Color color;

  const _HomeCrowdUi({
    required this.label,
    required this.color,
  });
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
