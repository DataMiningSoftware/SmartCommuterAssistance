import 'package:flutter/material.dart';

import '../services/crowd_reports_service.dart';
import '../widgets/train_loading_transition.dart';

class CrowdForecastScreen extends StatefulWidget {
  const CrowdForecastScreen({super.key});

  @override
  State<CrowdForecastScreen> createState() => _CrowdForecastScreenState();
}

class _CrowdForecastScreenState extends State<CrowdForecastScreen> {
  final CrowdReportsService _service = CrowdReportsService();
  late Future<List<StationOption>> _stationsFuture;
  Future<CrowdReport?>? _reportFuture;
  String? _selectedStationId;

  @override
  void initState() {
    super.initState();
    _stationsFuture = _service.fetchStationOptions();
  }

  void _onPickStation(String stopId) {
    setState(() {
      _selectedStationId = stopId;
      _reportFuture = _service.fetchLatestCrowdReport(stopId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crowd Forecast Demo')),
      body: FutureBuilder<List<StationOption>>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          final bool isLoading =
              snapshot.connectionState == ConnectionState.waiting;
          return TrainLoadingTransition(
            isLoading: isLoading,
            loadingLabel: 'Loading crowd forecast...',
            arrivalLabel: 'Forecast ready',
            child: _buildScreenContent(snapshot),
          );
        },
      ),
    );
  }

  Widget _buildScreenContent(AsyncSnapshot<List<StationOption>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox.shrink();
    }
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Failed to load stations: ${snapshot.error}',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final stations = snapshot.data ?? const <StationOption>[];
    if (stations.isEmpty) {
      return const Center(child: Text('No stations found.'));
    }

    _selectedStationId ??= stations.first.stopId;
    _reportFuture ??= _service.fetchLatestCrowdReport(_selectedStationId!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedStationId),
            initialValue: _selectedStationId,
            decoration: const InputDecoration(
              labelText: 'Station',
              border: OutlineInputBorder(),
            ),
            items: stations
                .map(
                  (station) => DropdownMenuItem(
                    value: station.stopId,
                    child: Text('${station.stationName} (${station.stopId})'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              _onPickStation(value);
            },
          ),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<CrowdReport?>(
              future: _reportFuture,
              builder: (context, reportSnap) {
                if (reportSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (reportSnap.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load crowd report: ${reportSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final report = reportSnap.data;
                if (report == null) {
                  return const Center(
                    child: Text('No prediction yet for this station.'),
                  );
                }

                final ui = _levelUi(report.occupancyLevel);
                return _CrowdLevelCard(
                  title: ui.title,
                  subtitle: ui.subtitle,
                  color: ui.color,
                  level: report.occupancyLevel,
                  sourceType: report.sourceType,
                  createdAt: report.createdAt,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  _LevelUi _levelUi(int level) {
    switch (level) {
      case 0:
        return const _LevelUi(
          title: 'Many seats available',
          subtitle: 'Low occupancy expected',
          color: Color(0xFF16A34A),
        );
      case 1:
        return const _LevelUi(
          title: 'Standing room only',
          subtitle: 'Moderate occupancy expected',
          color: Color(0xFFF59E0B),
        );
      case 2:
        return const _LevelUi(
          title: 'Very crowded',
          subtitle: 'High occupancy expected',
          color: Color(0xFFF97316),
        );
      case 3:
        return const _LevelUi(
          title: 'Crush capacity',
          subtitle: 'Consider waiting for next train',
          color: Color(0xFFDC2626),
        );
      default:
        return const _LevelUi(
          title: 'Unknown',
          subtitle: 'No valid occupancy level',
          color: Color(0xFF6B7280),
        );
    }
  }
}

class _CrowdLevelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final int level;
  final String sourceType;
  final DateTime? createdAt;

  const _CrowdLevelCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.level,
    required this.sourceType,
    required this.createdAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                'Level $level',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Text('Source: $sourceType',
              style: const TextStyle(color: Color(0xFF64748B))),
          if (createdAt != null)
            Text(
              'Updated: ${createdAt!.toLocal()}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
        ],
      ),
    );
  }
}

class _LevelUi {
  final String title;
  final String subtitle;
  final Color color;

  const _LevelUi({
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
