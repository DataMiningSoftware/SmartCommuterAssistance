import 'package:flutter/material.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
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
      appBar: AppBar(title: const Text('Crowd Outlook')),
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
                    child: Text('No forecast yet for this station.'),
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
                  confidence: _forecastConfidence(
                    sourceType: report.sourceType,
                    level: report.occupancyLevel,
                  ),
                  explanation: _forecastExplanation(
                    sourceType: report.sourceType,
                    level: report.occupancyLevel,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  _LevelUi _levelUi(int level) {
    final crowd = crowdLevelStyleFromIndex(level);
    return _LevelUi(
      title: crowd.label,
      subtitle: switch (level) {
        0 => 'Plenty of space across the carriage',
        1 => 'A smooth ride with room to spare',
        2 => 'Standing is likely during this window',
        3 => 'Expect shoulder-to-shoulder boarding',
        _ => 'No valid occupancy level',
      },
      color: crowd.color,
    );
  }

  double _forecastConfidence({
    required String sourceType,
    required int level,
  }) {
    final source = sourceType.toLowerCase();
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
    if (level >= 3) {
      base -= 0.04;
    } else if (level <= 0) {
      base += 0.02;
    }
    return base.clamp(0.50, 0.97);
  }

  String _forecastExplanation({
    required String sourceType,
    required int level,
  }) {
    final source = sourceType.toLowerCase();
    final reasons = <String>[];
    if (source.contains('user')) {
      reasons.add('based on recent rider reports');
    } else if (source.contains('trend') || source.contains('forecast')) {
      reasons.add('based on hourly ridership forecasts');
    } else if (source.contains('simulated')) {
      reasons.add('using 10-minute simulation fallback');
    } else {
      reasons.add('using offline fallback estimate');
    }

    switch (level) {
      case 0:
        reasons.add('low expected occupancy');
        break;
      case 1:
        reasons.add('comfortable space still available');
        break;
      case 2:
        reasons.add('standing demand likely');
        break;
      case 3:
        reasons.add('peak-load conditions likely');
        break;
    }

    return reasons.join(' • ');
  }
}

class _CrowdLevelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final int level;
  final String sourceType;
  final DateTime? createdAt;
  final double confidence;
  final String explanation;

  const _CrowdLevelCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.level,
    required this.sourceType,
    required this.createdAt,
    required this.confidence,
    required this.explanation,
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
        boxShadow: appCardShadows(context),
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
          Text(
            'Forecast confidence: ${(confidence * 100).round()}%',
            style: const TextStyle(
              color: Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            explanation,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          Text(
            'Forecast source: $sourceType',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
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
