import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'transit_network_service.dart';

class StationOption {
  final String stopId;
  final String stationName;

  const StationOption({
    required this.stopId,
    required this.stationName,
  });
}

class CrowdReport {
  final String stopId;
  final int occupancyLevel;
  final String sourceType;
  final DateTime? createdAt;

  const CrowdReport({
    required this.stopId,
    required this.occupancyLevel,
    required this.sourceType,
    required this.createdAt,
  });

  bool get isClosedHours => CrowdReportsService.isClosedHoursSource(sourceType);
}

class CrowdReportDisplayItem {
  final String stopId;
  final String stationName;
  final int occupancyLevel;
  final String sourceType;
  final DateTime? createdAt;

  const CrowdReportDisplayItem({
    required this.stopId,
    required this.stationName,
    required this.occupancyLevel,
    required this.sourceType,
    required this.createdAt,
  });
}

class StationCrowdBoardItem {
  final String stationName;
  final List<String> stopIds;
  final List<String> routeIds;
  final int occupancyLevel;
  final String sourceType;
  final DateTime? updatedAt;

  const StationCrowdBoardItem({
    required this.stationName,
    required this.stopIds,
    required this.routeIds,
    required this.occupancyLevel,
    required this.sourceType,
    required this.updatedAt,
  });

  String get stopId => stopIds.isEmpty ? '' : stopIds.first;

  bool get isClosedHours => CrowdReportsService.isClosedHoursSource(sourceType);
}

class StopCrowdForecast {
  final String stopId;
  final int forecastHour;
  final bool isWeekend;
  final int occupancyLevel;
  final int expectedWaitMinutes;
  final double etaMultiplier;
  final String sourceType;
  final DateTime? updatedAt;

  const StopCrowdForecast({
    required this.stopId,
    required this.forecastHour,
    required this.isWeekend,
    required this.occupancyLevel,
    required this.expectedWaitMinutes,
    required this.etaMultiplier,
    required this.sourceType,
    required this.updatedAt,
  });

  bool get isClosedHours => CrowdReportsService.isClosedHoursSource(sourceType);
}

class NearbyStationCrowdForecast {
  final String stopId;
  final String stationName;
  final String routeId;
  final double distanceMeters;
  final StopCrowdForecast? forecast;

  const NearbyStationCrowdForecast({
    required this.stopId,
    required this.stationName,
    required this.routeId,
    required this.distanceMeters,
    required this.forecast,
  });
}

class CrowdReportsService {
  final SupabaseClient _client = Supabase.instance.client;
  final TransitNetworkService _transitNetworkService = TransitNetworkService();

  static bool isClosedHoursSource(String sourceType) {
    return sourceType.trim().toLowerCase() == 'closed_hours';
  }

  static String displaySourceType(String sourceType) {
    final normalized = sourceType.trim().toLowerCase();
    if (normalized.isEmpty) return 'Unknown';
    if (normalized == 'closed_hours') return 'Closing hours';
    if (normalized == 'user') return 'Rider report';
    if (normalized == 'user_blend') return 'Forecast + rider reports';
    if (normalized.startsWith('forecast+')) {
      return 'Forecast + rider reports';
    }
    if (normalized.contains('trend') || normalized == 'forecast') {
      return 'Hourly forecast';
    }
    if (normalized.contains('simulated')) {
      return 'Simulation fallback';
    }
    if (normalized == 'delay') return 'Delay report';
    if (normalized == 'fallback' || normalized == 'unknown') {
      return 'Offline fallback';
    }
    return normalized
        .split('_')
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  Future<List<StationOption>> fetchStationOptions() async {
    final network = await _transitNetworkService.loadNetwork();
    final byId = <String, StationOption>{};
    for (final stop in network.stopsById.values) {
      byId.putIfAbsent(
        stop.stopId,
        () => StationOption(stopId: stop.stopId, stationName: stop.stopName),
      );
    }
    final list = byId.values.toList();
    list.sort((a, b) => a.stationName.compareTo(b.stationName));
    return list;
  }

  Future<CrowdReport?> fetchLatestCrowdReport(String stopId) async {
    final rows = await _client
        .from('crowd_reports')
        .select('stop_id,occupancy_level,source_type,created_at')
        .eq('stop_id', stopId)
        .order('created_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    for (final row in rows.whereType<Map>()) {
      final report = _toCrowdReport(Map<String, dynamic>.from(row));
      if (report == null || report.sourceType == 'delay') continue;
      return report;
    }
    return null;
  }

  Future<Map<String, CrowdReport>> fetchLatestCrowdReportsForStops(
      List<String> stopIds,
      {bool includeDelayReports = false}) async {
    if (stopIds.isEmpty) return const <String, CrowdReport>{};

    final rows = await _client
        .from('crowd_reports')
        .select('stop_id,occupancy_level,source_type,created_at')
        .inFilter('stop_id', stopIds)
        .order('created_at', ascending: false);

    final latestByStop = <String, CrowdReport>{};
    for (final row in rows.whereType<Map>()) {
      final report = _toCrowdReport(Map<String, dynamic>.from(row));
      if (report == null) continue;
      if (!includeDelayReports && report.sourceType == 'delay') continue;
      latestByStop.putIfAbsent(report.stopId, () => report);
    }
    return latestByStop;
  }

  Future<Map<String, CrowdReport>> fetchLatestUserCrowdReportsForStops(
    List<String> stopIds,
  ) async {
    if (stopIds.isEmpty) return const <String, CrowdReport>{};

    final rows = await _client
        .from('crowd_reports')
        .select('stop_id,occupancy_level,source_type,created_at')
        .inFilter('stop_id', stopIds)
        .eq('source_type', 'user')
        .order('created_at', ascending: false);

    final latestByStop = <String, CrowdReport>{};
    for (final row in rows.whereType<Map>()) {
      final report = _toCrowdReport(Map<String, dynamic>.from(row));
      if (report == null) continue;
      latestByStop.putIfAbsent(report.stopId, () => report);
    }
    return latestByStop;
  }

  Future<void> insertUserCrowdReport({
    required String stopId,
    required int occupancyLevel,
  }) async {
    await _client.rpc(
      'submit_crowd_report',
      params: {
        'p_stop_id': stopId.trim().toUpperCase(),
        'p_source_type': 'user',
        'p_occupancy_level': occupancyLevel.clamp(1, 5),
      },
    );
  }

  Future<void> insertUserDelayReport({
    required String stopId,
  }) async {
    await _client.rpc(
      'submit_crowd_report',
      params: {
        'p_stop_id': stopId.trim().toUpperCase(),
        'p_source_type': 'delay',
        'p_occupancy_level': 0,
      },
    );
  }

  Future<List<StationCrowdBoardItem>> fetchStationCrowdBoard({
    DateTime? time,
  }) async {
    final effectiveTime = time ?? DateTime.now();
    final grouped = <String, _StationBoardGroup>{};
    final network = await _transitNetworkService.loadNetwork();
    for (final stop in network.stopsById.values) {
      final stationName = stop.stopName.trim();
      final stopId = stop.stopId.trim().toUpperCase();
      if (stationName.isEmpty || stopId.isEmpty) continue;
      grouped.putIfAbsent(
        stationName,
        () => _StationBoardGroup(stationName: stationName),
      )
        ..stopIds.add(stopId)
        ..routeIds.add(stop.routeId);
    }

    if (grouped.isEmpty) return const <StationCrowdBoardItem>[];

    final stopIds =
        grouped.values.expand((group) => group.stopIds).toSet().toList();
    final forecasts = await fetchForecastForStopsAtTime(stopIds, effectiveTime);
    final latestReports = await fetchLatestCrowdReportsForStops(stopIds);

    final items = <StationCrowdBoardItem>[];
    for (final group in grouped.values) {
      var bestLevel = 0;
      var bestSourceType = 'forecast';
      DateTime? bestUpdatedAt;
      var hasValue = false;

      for (final stopId in group.stopIds) {
        final forecast = forecasts[stopId];
        final report = latestReports[stopId];
        final level = forecast?.occupancyLevel ?? report?.occupancyLevel ?? 0;
        final sourceType =
            forecast?.sourceType ?? report?.sourceType ?? 'forecast';
        final updatedAt = forecast?.updatedAt ?? report?.createdAt;

        if (!hasValue ||
            level > bestLevel ||
            (level == bestLevel &&
                (updatedAt?.millisecondsSinceEpoch ?? 0) >
                    (bestUpdatedAt?.millisecondsSinceEpoch ?? 0))) {
          bestLevel = level;
          bestSourceType = sourceType;
          bestUpdatedAt = updatedAt;
          hasValue = true;
        }
      }

      items.add(
        StationCrowdBoardItem(
          stationName: group.stationName,
          stopIds: group.stopIds.toList()..sort(),
          routeIds: group.routeIds.toList()..sort(),
          occupancyLevel: bestLevel,
          sourceType: bestSourceType,
          updatedAt: bestUpdatedAt,
        ),
      );
    }

    items.sort((a, b) => a.stationName.compareTo(b.stationName));
    return items;
  }

  Future<List<CrowdReportDisplayItem>> fetchLatestCrowdDisplayFeed({
    int limit = 5,
  }) async {
    final rows = await _client
        .from('crowd_reports')
        .select('stop_id,occupancy_level,source_type,created_at')
        .order('created_at', ascending: false)
        .limit(300);

    final latestByStop = <String, CrowdReport>{};
    for (final row in rows.whereType<Map>()) {
      final report = _toCrowdReport(Map<String, dynamic>.from(row));
      if (report == null || report.sourceType == 'delay') continue;
      latestByStop.putIfAbsent(report.stopId, () => report);
      if (latestByStop.length >= limit) break;
    }
    if (latestByStop.isEmpty) return const <CrowdReportDisplayItem>[];

    final stopIds = latestByStop.keys.toList();
    final stopNameById = <String, String>{};
    try {
      final network = await _transitNetworkService.loadNetwork();
      for (final stopId in stopIds) {
        final stop = network.stopsById[stopId.trim().toUpperCase()];
        if (stop == null) continue;
        stopNameById.putIfAbsent(stopId, () => stop.stopName);
      }
    } catch (_) {
      // Keep fallback ids below.
    }

    final items = latestByStop.values.map((report) {
      return CrowdReportDisplayItem(
        stopId: report.stopId,
        stationName: stopNameById[report.stopId] ?? report.stopId,
        occupancyLevel: report.occupancyLevel,
        sourceType: report.sourceType,
        createdAt: report.createdAt,
      );
    }).toList();

    items.sort((a, b) {
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return items;
  }

  Future<Map<String, StopCrowdForecast>> fetchForecastGrid({
    required List<String> stopIds,
    required List<DateTime> times,
  }) async {
    if (stopIds.isEmpty || times.isEmpty) {
      return const <String, StopCrowdForecast>{};
    }

    final normalizedStopIds = stopIds
        .map((id) => id.trim().toUpperCase())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedStopIds.isEmpty) return const <String, StopCrowdForecast>{};

    final hours = <int>{
      for (final time in times) time.hour,
    }.toList();
    final weekendFlags = <bool>{
      for (final time in times) _isWeekend(time),
    }.toList();

    final rows = <Map<String, dynamic>>[];
    try {
      final remoteRows = await _client
          .from('crowd_forecast_hourly')
          .select(
            'stop_id,forecast_hour,is_weekend,occupancy_level,expected_wait_minutes,eta_multiplier,source_type,updated_at',
          )
          .inFilter('stop_id', normalizedStopIds)
          .inFilter('forecast_hour', hours)
          .inFilter('is_weekend', weekendFlags);
      rows.addAll(
        remoteRows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row)),
      );
    } catch (_) {
      // Fall back to latest crowd reports below.
    }

    final forecasts = <String, StopCrowdForecast>{};
    for (final row in rows) {
      final forecast = _toStopCrowdForecast(row);
      if (forecast == null) continue;
      forecasts[forecastKey(
        stopId: forecast.stopId,
        forecastHour: forecast.forecastHour,
        isWeekend: forecast.isWeekend,
      )] = forecast;
    }

    Map<String, CrowdReport> latestByStop = const <String, CrowdReport>{};
    Map<String, CrowdReport> latestUserByStop = const <String, CrowdReport>{};
    try {
      latestByStop = await fetchLatestCrowdReportsForStops(normalizedStopIds);
      latestUserByStop = await fetchLatestUserCrowdReportsForStops(
        normalizedStopIds,
      );
    } catch (_) {
      latestByStop = const <String, CrowdReport>{};
      latestUserByStop = const <String, CrowdReport>{};
    }

    final now = DateTime.now();
    for (final stopId in normalizedStopIds) {
      final latest = latestByStop[stopId];
      final latestUser = latestUserByStop[stopId];
      final userBlendWeight = latestUser == null
          ? 0.0
          : _liveReportBlendWeight(report: latestUser, now: now);
      for (final time in times) {
        final key = forecastKeyForTime(stopId: stopId, time: time);
        final existing = forecasts[key];
        if (existing != null) {
          forecasts[key] = userBlendWeight > 0
              ? _blendForecastWithLiveReport(
                  base: existing,
                  liveReport: latestUser!,
                  weight: userBlendWeight,
                )
              : existing;
          continue;
        }

        if (userBlendWeight > 0) {
          forecasts[key] = _forecastFromCrowdReport(
            report: latestUser!,
            time: time,
            sourceType: 'user_blend',
          );
          continue;
        }

        if (latest != null &&
            _liveReportBlendWeight(report: latest, now: now) > 0) {
          forecasts[key] = _forecastFromCrowdReport(
            report: latest,
            time: time,
          );
        }
      }
    }

    for (final stopId in normalizedStopIds) {
      for (final time in times) {
        if (!_isSystemClosed(time)) continue;
        final key = forecastKeyForTime(stopId: stopId, time: time);
        forecasts[key] = _closedHoursForecast(
          stopId: stopId,
          time: time,
        );
      }
    }

    return forecasts;
  }

  Future<Map<String, StopCrowdForecast>> fetchForecastForStopsAtTime(
    List<String> stopIds,
    DateTime time,
  ) async {
    final grid = await fetchForecastGrid(
      stopIds: stopIds,
      times: <DateTime>[time],
    );
    final output = <String, StopCrowdForecast>{};
    for (final stopId in stopIds) {
      final normalized = stopId.trim().toUpperCase();
      if (normalized.isEmpty) continue;
      final key = forecastKeyForTime(stopId: normalized, time: time);
      final value = grid[key];
      if (value != null) {
        output[normalized] = value;
      }
    }
    return output;
  }

  Future<Map<String, bool>> fetchClosedStatusForStopsAtTime(
    List<String> stopIds,
    DateTime time,
  ) async {
    final forecasts = await fetchForecastForStopsAtTime(stopIds, time);
    return <String, bool>{
      for (final entry in forecasts.entries)
        entry.key: entry.value.isClosedHours,
    };
  }

  Future<List<NearbyStationCrowdForecast>> fetchNearestStationsWithCrowd({
    required double latitude,
    required double longitude,
    required DateTime departureTime,
    int limit = 5,
  }) async {
    final nearestByName = <String, _StationDistanceCandidate>{};
    final network = await _transitNetworkService.loadNetwork();
    for (final stop in network.stopsById.values) {
      final stopId = stop.stopId;
      final stopName = stop.stopName;
      final routeId = stop.routeId;

      final distance = _haversineMeters(
        latitude: latitude,
        longitude: longitude,
        targetLatitude: stop.latitude,
        targetLongitude: stop.longitude,
      );

      final key = stopName.toUpperCase();
      final existing = nearestByName[key];
      if (existing == null || distance < existing.distanceMeters) {
        nearestByName[key] = _StationDistanceCandidate(
          stopId: stopId,
          stationName: stopName,
          routeId: routeId,
          distanceMeters: distance,
        );
      }
    }

    final nearest = nearestByName.values.toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    final limited = nearest.take(limit).toList();
    if (limited.isEmpty) return const <NearbyStationCrowdForecast>[];

    Map<String, StopCrowdForecast> forecasts =
        const <String, StopCrowdForecast>{};
    try {
      forecasts = await fetchForecastForStopsAtTime(
        limited.map((item) => item.stopId).toList(),
        departureTime,
      );
    } catch (_) {
      forecasts = const <String, StopCrowdForecast>{};
    }

    return limited
        .map(
          (item) => NearbyStationCrowdForecast(
            stopId: item.stopId,
            stationName: item.stationName,
            routeId: item.routeId,
            distanceMeters: item.distanceMeters,
            forecast: forecasts[item.stopId],
          ),
        )
        .toList();
  }

  CrowdReport? _toCrowdReport(Map<String, dynamic> map) {
    final stopId = map['stop_id']?.toString() ?? '';
    if (stopId.isEmpty) return null;
    final levelRaw = map['occupancy_level'];
    final level = levelRaw is num
        ? levelRaw.toInt()
        : int.tryParse(levelRaw.toString()) ?? 0;

    DateTime? createdAt;
    final createdAtRaw = map['created_at']?.toString();
    if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
      createdAt = DateTime.tryParse(createdAtRaw);
    }

    return CrowdReport(
      stopId: stopId,
      occupancyLevel: level.clamp(0, 5),
      sourceType: map['source_type']?.toString() ?? 'unknown',
      createdAt: createdAt,
    );
  }

  StopCrowdForecast? _toStopCrowdForecast(Map<String, dynamic> map) {
    final stopId = map['stop_id']?.toString().trim().toUpperCase() ?? '';
    if (stopId.isEmpty) return null;

    final hourRaw = map['forecast_hour'];
    final forecastHour = hourRaw is num
        ? hourRaw.toInt()
        : int.tryParse(hourRaw?.toString() ?? '');
    if (forecastHour == null || forecastHour < 0 || forecastHour > 23) {
      return null;
    }

    final isWeekendRaw = map['is_weekend'];
    final isWeekend = switch (isWeekendRaw) {
      bool value => value,
      num value => value != 0,
      _ => (isWeekendRaw?.toString().toLowerCase() ?? 'false') == 'true',
    };

    final levelRaw = map['occupancy_level'];
    final occupancyLevel = levelRaw is num
        ? levelRaw.toInt()
        : int.tryParse(levelRaw?.toString() ?? '') ?? 0;

    final waitRaw = map['expected_wait_minutes'];
    final expectedWait = waitRaw is num
        ? waitRaw.toInt()
        : int.tryParse(waitRaw?.toString() ?? '') ??
            _defaultWaitMinutes(occupancyLevel);

    final etaRaw = map['eta_multiplier'];
    final etaMultiplier = etaRaw is num
        ? etaRaw.toDouble()
        : double.tryParse(etaRaw?.toString() ?? '') ??
            _defaultEtaMultiplier(occupancyLevel);

    DateTime? updatedAt;
    final updatedRaw = map['updated_at']?.toString();
    if (updatedRaw != null && updatedRaw.isNotEmpty) {
      updatedAt = DateTime.tryParse(updatedRaw);
    }

    return StopCrowdForecast(
      stopId: stopId,
      forecastHour: forecastHour,
      isWeekend: isWeekend,
      occupancyLevel: occupancyLevel.clamp(0, 5),
      expectedWaitMinutes: expectedWait.clamp(0, 30),
      etaMultiplier: etaMultiplier.clamp(1.0, 2.5),
      sourceType: map['source_type']?.toString() ?? 'forecast',
      updatedAt: updatedAt,
    );
  }

  static String forecastKey({
    required String stopId,
    required int forecastHour,
    required bool isWeekend,
  }) {
    return '${stopId.trim().toUpperCase()}|$forecastHour|${isWeekend ? 1 : 0}';
  }

  static String forecastKeyForTime({
    required String stopId,
    required DateTime time,
  }) {
    return forecastKey(
      stopId: stopId,
      forecastHour: time.hour,
      isWeekend: _isWeekend(time),
    );
  }

  static bool _isWeekend(DateTime time) {
    return time.weekday == DateTime.saturday || time.weekday == DateTime.sunday;
  }

  static bool _isSystemClosed(DateTime time) {
    return time.hour < 6;
  }

  static int _defaultWaitMinutes(int level) {
    switch (level) {
      case 1:
        return 2;
      case 2:
        return 4;
      case 3:
        return 6;
      case 4:
        return 8;
      case 5:
        return 10;
      default:
        return 4;
    }
  }

  static double _defaultEtaMultiplier(int level) {
    switch (level) {
      case 1:
        return 1.0;
      case 2:
        return 1.05;
      case 3:
        return 1.12;
      case 4:
        return 1.22;
      case 5:
        return 1.35;
      default:
        return 1.1;
    }
  }

  static StopCrowdForecast _closedHoursForecast({
    required String stopId,
    required DateTime time,
  }) {
    return StopCrowdForecast(
      stopId: stopId.trim().toUpperCase(),
      forecastHour: time.hour,
      isWeekend: _isWeekend(time),
      occupancyLevel: 1,
      expectedWaitMinutes: 0,
      etaMultiplier: 1.0,
      sourceType: 'closed_hours',
      updatedAt: null,
    );
  }

  static StopCrowdForecast _forecastFromCrowdReport({
    required CrowdReport report,
    required DateTime time,
    String? sourceType,
  }) {
    final level = report.occupancyLevel.clamp(1, 5);
    return StopCrowdForecast(
      stopId: report.stopId.trim().toUpperCase(),
      forecastHour: time.hour,
      isWeekend: _isWeekend(time),
      occupancyLevel: level,
      expectedWaitMinutes: _defaultWaitMinutes(level),
      etaMultiplier: _defaultEtaMultiplier(level),
      sourceType: sourceType ?? report.sourceType,
      updatedAt: report.createdAt,
    );
  }

  static StopCrowdForecast _blendForecastWithLiveReport({
    required StopCrowdForecast base,
    required CrowdReport liveReport,
    required double weight,
  }) {
    final level = ((base.occupancyLevel * (1 - weight)) +
            (liveReport.occupancyLevel * weight))
        .round()
        .clamp(1, 5);
    return StopCrowdForecast(
      stopId: base.stopId,
      forecastHour: base.forecastHour,
      isWeekend: base.isWeekend,
      occupancyLevel: level,
      expectedWaitMinutes: _defaultWaitMinutes(level),
      etaMultiplier: _defaultEtaMultiplier(level),
      sourceType: 'forecast+${liveReport.sourceType}',
      updatedAt: liveReport.createdAt ?? base.updatedAt,
    );
  }

  static double _liveReportBlendWeight({
    required CrowdReport report,
    required DateTime now,
  }) {
    final createdAt = report.createdAt;
    if (createdAt == null) {
      return report.sourceType == 'user' ? 0.55 : 0.2;
    }

    final ageMinutes = now.difference(createdAt.toLocal()).inMinutes.abs();
    if (ageMinutes > 120) return 0;

    if (report.sourceType == 'user') {
      if (ageMinutes <= 15) return 0.75;
      if (ageMinutes <= 45) return 0.55;
      return 0.35;
    }

    if (ageMinutes <= 15) return 0.35;
    if (ageMinutes <= 45) return 0.25;
    return 0.15;
  }

  static double _haversineMeters({
    required double latitude,
    required double longitude,
    required double targetLatitude,
    required double targetLongitude,
  }) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(targetLatitude - latitude);
    final dLon = _toRadians(targetLongitude - longitude);
    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(targetLatitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _toRadians(double degree) => degree * (math.pi / 180.0);
}

class _StationDistanceCandidate {
  final String stopId;
  final String stationName;
  final String routeId;
  final double distanceMeters;

  const _StationDistanceCandidate({
    required this.stopId,
    required this.stationName,
    required this.routeId,
    required this.distanceMeters,
  });
}

class _StationBoardGroup {
  final String stationName;
  final Set<String> stopIds = <String>{};
  final Set<String> routeIds = <String>{};

  _StationBoardGroup({
    required this.stationName,
  });
}
