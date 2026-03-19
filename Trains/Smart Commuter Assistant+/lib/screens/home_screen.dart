import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/map_preview.dart';
import '../widgets/prediction_card.dart';
import 'route_planner.dart';
import 'station_details.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isFetchingStations = false;

  Future<void> _showTrainStops() async {
    setState(() => _isFetchingStations = true);
    try {
      final rows = await Supabase.instance.client
          .from('train_stops_kl')
          .select();
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) => _TrainStopsDialog(rows: rows),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load train stops: $e'),
          backgroundColor: const Color(0xFFD7263D),
        ),
      );
    } finally {
      if (mounted) setState(() => _isFetchingStations = false);
    }
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
                    label: 'Nearby Stations',
                    subtitle: 'Live arrivals',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StationDetails()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isFetchingStations ? null : _showTrainStops,
                icon: _isFetchingStations
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storage_rounded),
                label: Text(
                  _isFetchingStations
                      ? 'Loading train stops...'
                      : 'View Train Stops (Supabase)',
                ),
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

class _TrainStopsDialog extends StatelessWidget {
  final List<dynamic> rows;

  const _TrainStopsDialog({required this.rows});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('train_stops_kl (${rows.length})'),
      content: SizedBox(
        width: 420,
        child: rows.isEmpty
            ? const Text('No rows returned from Supabase.')
            : ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final map = row is Map ? row : <String, dynamic>{'value': row};
                  final stationName = (map['station_name'] ??
                          map['name'] ??
                          map['station'] ??
                          map['stop_name'] ??
                          'Unnamed station')
                      .toString();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stationName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        map.toString(),
                        style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                      ),
                    ],
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
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
