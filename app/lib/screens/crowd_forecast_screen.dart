import 'package:flutter/material.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
import '../services/crowd_reports_service.dart';
import '../widgets/data_source_badge.dart';

class CrowdForecastScreen extends StatefulWidget {
  const CrowdForecastScreen({super.key});

  @override
  State<CrowdForecastScreen> createState() => _CrowdForecastScreenState();
}

class _CrowdForecastScreenState extends State<CrowdForecastScreen> {
  final CrowdReportsService _service = CrowdReportsService();
  late Future<List<StationOption>> _stationsFuture;
  Future<StopCrowdForecast?>? _forecastFuture;
  String? _selectedStationId;

  @override
  void initState() {
    super.initState();
    _stationsFuture = _service.fetchStationOptions();
  }

  void _onPickStation(String stopId) {
    setState(() {
      _selectedStationId = stopId;
      _forecastFuture = _fetchForecast(stopId);
    });
  }

  Future<StopCrowdForecast?> _fetchForecast(String stopId) async {
    final forecasts = await _service.fetchForecastForStopsAtTime(
      <String>[stopId],
      DateTime.now(),
    );
    return forecasts[stopId.trim().toUpperCase()];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crowd Outlook')),
      body: FutureBuilder<List<StationOption>>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          return _buildScreenContent(snapshot);
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
    _forecastFuture ??= _fetchForecast(_selectedStationId!);

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
            child: FutureBuilder<StopCrowdForecast?>(
              future: _forecastFuture,
              builder: (context, forecastSnap) {
                if (forecastSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (forecastSnap.hasError) {
                  return Center(
                    child: Text(
                      'Failed to load crowd forecast: ${forecastSnap.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final forecast = forecastSnap.data;
                if (forecast == null) {
                  return const Center(
                    child: Text('No forecast yet for this station.'),
                  );
                }

                final isClosed = forecast.isClosedHours;
                final ui = _levelUi(
                  forecast.occupancyLevel,
                  isClosedHours: isClosed,
                );
                return _CrowdLevelCard(
                  title: ui.title,
                  subtitle: ui.subtitle,
                  color: ui.color,
                  level: forecast.occupancyLevel,
                  sourceType: forecast.sourceType,
                  createdAt: forecast.updatedAt,
                  confidence: _forecastConfidence(
                    sourceType: forecast.sourceType,
                    level: forecast.occupancyLevel,
                  ),
                  explanation: _forecastExplanation(
                    sourceType: forecast.sourceType,
                    level: forecast.occupancyLevel,
                  ),
                  isClosedHours: isClosed,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  _LevelUi _levelUi(int level, {bool isClosedHours = false}) {
    if (isClosedHours) {
      return const _LevelUi(
        title: 'Closing hours',
        subtitle:
            'Train service is currently closed. Forecasts resume from 6:00 AM.',
        color: Color(0xFF98A2B3),
      );
    }
    final crowd = crowdLevelStyleFromIndex(level);
    return _LevelUi(
      title: crowd.label,
      subtitle: switch (level) {
        1 => 'Almost empty with seats widely available',
        2 => 'Comfortable ride with space to spare',
        3 => 'Moderate traffic with routine standing demand',
        4 => 'Heavy crowding with slower boarding likely',
        5 => 'Crowded conditions across the platform and carriage',
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
    if (CrowdReportsService.isClosedHoursSource(source)) {
      return 0.99;
    }
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
    if (level >= 4) {
      base -= 0.04;
    } else if (level <= 2) {
      base += 0.02;
    }
    return base.clamp(0.50, 0.97);
  }

  String _forecastExplanation({
    required String sourceType,
    required int level,
  }) {
    final source = sourceType.toLowerCase();
    if (CrowdReportsService.isClosedHoursSource(source)) {
      return 'Train service is outside operating hours. Stations are shown as unavailable until 6:00 AM.';
    }
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
      case 1:
        reasons.add('very low expected occupancy');
        break;
      case 2:
        reasons.add('comfortable space still available');
        break;
      case 3:
        reasons.add('moderate standing demand likely');
        break;
      case 4:
        reasons.add('standing demand likely');
        break;
      case 5:
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
  final bool isClosedHours;

  const _CrowdLevelCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.level,
    required this.sourceType,
    required this.createdAt,
    required this.confidence,
    required this.explanation,
    required this.isClosedHours,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isClosedHours ? const Color(0xFFF8FAFC) : Colors.white;
    final borderColor =
        isClosedHours ? const Color(0xFFD0D5DD) : const Color(0xFFE2E8F0);
    final primaryTextColor =
        isClosedHours ? const Color(0xFF667085) : const Color(0xFF101828);
    final secondaryTextColor =
        isClosedHours ? const Color(0xFF98A2B3) : const Color(0xFF64748B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
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
                isClosedHours ? 'Level $level · Closed' : 'Level $level',
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
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: primaryTextColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(color: secondaryTextColor),
          ),
          const SizedBox(height: 12),
          Text(
            'Forecast confidence: ${(confidence * 100).round()}%',
            style: TextStyle(
              color: isClosedHours
                  ? const Color(0xFF667085)
                  : const Color(0xFF475467),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            explanation,
            style: TextStyle(color: secondaryTextColor),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              DataSourceBadge(source: sourceType),
              const SizedBox(width: 8),
              Text(
                CrowdReportsService.displaySourceType(sourceType),
                style: TextStyle(color: secondaryTextColor, fontSize: 12),
              ),
            ],
          ),
          if (createdAt != null)
            Text(
              'Updated: ${createdAt!.toLocal()}',
              style: TextStyle(color: secondaryTextColor),
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
