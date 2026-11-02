import 'package:flutter/material.dart';

import '../constants/app_shadows.dart';
import '../constants/crowd_levels.dart';
import '../l10n/generated/app_localizations.dart';
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

  Future<void> _refreshAll() async {
    final stopId = _selectedStationId;
    setState(() {
      _stationsFuture = _service.fetchStationOptions();
      if (stopId != null) {
        _forecastFuture = _fetchForecast(stopId);
      }
    });
    await _stationsFuture;
    final forecast = _forecastFuture;
    if (forecast != null) {
      await forecast;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.forecastTitle)),
      body: FutureBuilder<List<StationOption>>(
        future: _stationsFuture,
        builder: (context, snapshot) {
          return _buildScreenContent(snapshot);
        },
      ),
    );
  }

  Widget _buildScreenContent(AsyncSnapshot<List<StationOption>> snapshot) {
    final l10n = AppLocalizations.of(context);
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const SizedBox.shrink();
    }
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            l10n.homeLoadStationsFailed(snapshot.error.toString()),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final stations = snapshot.data ?? const <StationOption>[];
    if (stations.isEmpty) {
      return Center(child: Text(l10n.forecastNoStations));
    }

    _selectedStationId ??= stations.first.stopId;
    _forecastFuture ??= _fetchForecast(_selectedStationId!);

    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(_selectedStationId),
            initialValue: _selectedStationId,
            decoration: InputDecoration(
              labelText: l10n.forecastStationLabel,
              border: const OutlineInputBorder(),
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
                      l10n.forecastLoadFailed(
                        forecastSnap.error.toString(),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final forecast = forecastSnap.data;
                if (forecast == null) {
                  return Center(
                    child: Text(l10n.forecastEmpty),
                  );
                }

                final isClosed = forecast.isClosedHours;
                final ui = _levelUi(
                  l10n,
                  forecast.occupancyLevel,
                  isClosedHours: isClosed,
                );
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    _CrowdLevelCard(
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
                        l10n,
                        sourceType: forecast.sourceType,
                        level: forecast.occupancyLevel,
                      ),
                      isClosedHours: isClosed,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }

  _LevelUi _levelUi(
    AppLocalizations l10n,
    int level, {
    bool isClosedHours = false,
  }) {
    if (isClosedHours) {
      return _LevelUi(
        title: l10n.homeClosingHours,
        subtitle: l10n.forecastClosingHoursBody,
        color: const Color(0xFF98A2B3),
      );
    }
    final crowd = crowdLevelStyleFromIndex(level);
    return _LevelUi(
      title: localizedCrowdLevelLabel(l10n, level),
      subtitle: switch (level) {
        1 => l10n.forecastLevel1Subtitle,
        2 => l10n.forecastLevel2Subtitle,
        3 => l10n.forecastLevel3Subtitle,
        4 => l10n.forecastLevel4Subtitle,
        5 => l10n.forecastLevel5Subtitle,
        _ => l10n.forecastUnknownLevelSubtitle,
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

  String _forecastExplanation(
    AppLocalizations l10n, {
    required String sourceType,
    required int level,
  }) {
    final source = sourceType.toLowerCase();
    if (CrowdReportsService.isClosedHoursSource(source)) {
      return l10n.forecastExplanationClosed;
    }
    final reasons = <String>[];
    if (source.contains('user')) {
      reasons.add(l10n.forecastExplanationRecentReports);
    } else if (source.contains('trend') || source.contains('forecast')) {
      reasons.add(l10n.forecastExplanationHourlyForecast);
    } else if (source.contains('simulated')) {
      reasons.add(l10n.forecastExplanationSimulation);
    } else {
      reasons.add(l10n.forecastExplanationOfflineFallback);
    }

    switch (level) {
      case 1:
        reasons.add(l10n.forecastReasonVeryLowOccupancy);
        break;
      case 2:
        reasons.add(l10n.forecastReasonComfortableSpace);
        break;
      case 3:
        reasons.add(l10n.forecastReasonModerateStanding);
        break;
      case 4:
        reasons.add(l10n.stationsForecastReasonStandingDemand);
        break;
      case 5:
        reasons.add(l10n.stationsForecastReasonPeakLoad);
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
    final l10n = AppLocalizations.of(context);
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
                isClosedHours
                    ? l10n.forecastLevelClosed(level)
                    : l10n.forecastLevelLabel(level),
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
            l10n.stationsForecastConfidence(
              '${(confidence * 100).round()}%',
            ),
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
              l10n.forecastUpdated(createdAt!.toLocal().toString()),
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
