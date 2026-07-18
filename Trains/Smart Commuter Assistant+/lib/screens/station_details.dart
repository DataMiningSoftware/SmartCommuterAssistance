import 'package:flutter/material.dart';

import '../services/crowd_reports_service.dart';
import '../services/train_arrival_service.dart';
import '../widgets/crowd_indicator.dart';
import '../widgets/data_source_badge.dart';
import '../widgets/scheduled_arrivals_panel.dart';

class StationDetails extends StatefulWidget {
  final String stopId;
  final String? stopName;

  const StationDetails({
    super.key,
    required this.stopId,
    this.stopName,
  });

  @override
  State<StationDetails> createState() => _StationDetailsState();
}

class _StationDetailsState extends State<StationDetails> {
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  Future<StationCrowdBoardItem?>? _crowdFuture;

  @override
  void initState() {
    super.initState();
    _crowdFuture = _loadCrowd();
  }

  Future<StationCrowdBoardItem?> _loadCrowd() async {
    final board = await _crowdReportsService.fetchStationCrowdBoard();
    try {
      return board.firstWhere(
        (item) => item.stopIds.any(
          (id) => id.trim().toUpperCase() == widget.stopId.trim().toUpperCase(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.stopName ?? widget.stopId),
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StationInfoCard(
              stopId: widget.stopId,
              stopName: widget.stopName,
              crowdFuture: _crowdFuture,
            ),
            const SizedBox(height: 20),
            Text(
              'Scheduled Arrivals',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ScheduledArrivalsPanel(
              stopId: widget.stopId,
              stationName: widget.stopName,
              limit: 5,
            ),
          ],
        ),
      ),
    );
  }
}

class StationInfoCard extends StatelessWidget {
  final String stopId;
  final String? stopName;
  final Future<StationCrowdBoardItem?>? crowdFuture;

  const StationInfoCard({
    super.key,
    required this.stopId,
    this.stopName,
    this.crowdFuture,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.train, size: 32, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stopName ?? stopId,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        stopId,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                DataSourceBadge(source: 'gtfs_static_schedule'),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<StationCrowdBoardItem?>(
              future: crowdFuture,
              builder: (context, snapshot) {
                final crowd = snapshot.data;
                if (crowd == null) {
                  return const Text('No crowd data available');
                }
                return Row(
                  children: [
                    const Text('Crowd Level: '),
                    CrowdIndicator(
                      level: crowdLevelLabel(crowd.occupancyLevel),
                    ),
                    if (crowd.sourceType.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      DataSourceBadge(
                        source: crowd.sourceType,
                        compact: true,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String crowdLevelLabel(int level) {
    switch (level) {
      case 1:
        return 'Empty';
      case 2:
        return 'Light';
      case 3:
        return 'Moderate';
      case 4:
        return 'Heavy';
      case 5:
        return 'Crowded';
      default:
        return 'Unknown';
    }
  }
}
