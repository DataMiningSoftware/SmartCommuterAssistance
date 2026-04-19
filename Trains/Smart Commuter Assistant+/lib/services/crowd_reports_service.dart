import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'database_service.dart';

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
  final DatabaseService _databaseService = DatabaseService();

  Future<List<StationOption>> fetchStationOptions() async {
    final rows = await _client
        .from('train_stops_kl')
        .select('stop_id,stop_name')
        .order('stop_name', ascending: true);

    final byId = <String, StationOption>{};
    for (final row in rows.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final stopId = map['stop_id']?.toString() ?? '';
      final stationName = map['stop_name']?.toString() ?? '';
      if (stopId.isEmpty || stationName.isEmpty) continue;
      byId.putIfAbsent(
        stopId,
        () => StationOption(stopId: stopId, stationName: stationName),
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

  Future<void> insertUserCrowdReport({
    required String stopId,
    required int occupancyLevel,
  }) async {
    await _client.from('crowd_reports').insert({
      'stop_id': stopId,
      'occupancy_level': occupancyLevel.clamp(0, 3),
      'source_type': 'user',
    });
  }

  Future<void> insertUserDelayReport({
    required String stopId,
  }) async {
    await _client.from('crowd_reports').insert({
      'stop_id': stopId,
      'occupancy_level': 0,
      'source_type': 'delay',
    });
  }

  Future<List<StationCrowdBoardItem>> fetchStationCrowdBoard({
    DateTime? time,
  }) async {
    final effectiveTime = time ?? DateTime.now();
    final rows = <Map<String, dynamic>>[];
    try {
      final remoteRows = await _client
          .from('train_stops_kl')
          .select('stop_id,stop_name,route_id');
      final mappedRows = remoteRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      rows.addAll(mappedRows);
    } catch (_) {
      // Fallback below.
    }

    if (rows.isEmpty) {
      final cachedRows = await _databaseService.getCachedTrainStops();
      rows.addAll(
        cachedRows.map((row) => Map<String, dynamic>.from(row)),
      );
    }

    final grouped = <String, _StationBoardGroup>{};
    for (final row in rows) {
      final stationName = (row['stop_name']?.toString() ?? '').trim();
      final stopId = (row['stop_id']?.toString() ?? '').trim().toUpperCase();
      if (stationName.isEmpty || stopId.isEmpty) continue;
      final routeRaw = (row['route_id']?.toString() ?? '').trim().toUpperCase();
      final routeId =
          routeRaw.isEmpty ? _inferRouteIdFromStopId(stopId) : routeRaw;
      grouped.putIfAbsent(
        stationName,
        () => _StationBoardGroup(stationName: stationName),
      )
        ..stopIds.add(stopId)
        ..routeIds.add(routeId);
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
    final stationRows = await _client
        .from('train_stops_kl')
        .select('stop_id,stop_name')
        .inFilter('stop_id', stopIds);

    final stopNameById = <String, String>{};
    for (final row in stationRows.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final stopId = map['stop_id']?.toString() ?? '';
      final stopName = map['stop_name']?.toString() ?? '';
      if (stopId.isEmpty || stopName.isEmpty) continue;
      stopNameById.putIfAbsent(stopId, () => stopName);
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
      // Offline or no table access: fallback simulation below.
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
    try {
      latestByStop = await fetchLatestCrowdReportsForStops(normalizedStopIds);
    } catch (_) {
      latestByStop = const <String, CrowdReport>{};
    }
    for (final stopId in normalizedStopIds) {
      final latest = latestByStop[stopId];
      for (final time in times) {
        final key = forecastKeyForTime(stopId: stopId, time: time);
        if (forecasts.containsKey(key) || latest == null) continue;
        forecasts[key] = StopCrowdForecast(
          stopId: stopId,
          forecastHour: time.hour,
          isWeekend: _isWeekend(time),
          occupancyLevel: latest.occupancyLevel,
          expectedWaitMinutes: _defaultWaitMinutes(latest.occupancyLevel),
          etaMultiplier: _defaultEtaMultiplier(latest.occupancyLevel),
          sourceType: latest.sourceType,
          updatedAt: latest.createdAt,
        );
      }
    }

    for (final stopId in normalizedStopIds) {
      for (final time in times) {
        final key = forecastKeyForTime(stopId: stopId, time: time);
        final existing = forecasts[key];
        if (existing != null) {
          forecasts[key] = _applyTenMinuteSimulation(
            base: existing,
            time: time,
          );
        } else {
          forecasts[key] = _simulateForecast(
            stopId: stopId,
            time: time,
            sourceType: 'simulated_10m',
          );
        }
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

  Future<List<NearbyStationCrowdForecast>> fetchNearestStationsWithCrowd({
    required double latitude,
    required double longitude,
    required DateTime departureTime,
    int limit = 5,
  }) async {
    final rows = <Map<String, dynamic>>[];
    try {
      final remoteRows = await _client
          .from('train_stops_kl')
          .select('stop_id,stop_name,stop_lat,stop_lon,route_id');
      final mappedRows = remoteRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      rows.addAll(mappedRows);
      if (mappedRows.isNotEmpty) {
        await _databaseService.cacheTrainStops(mappedRows);
      }
    } catch (_) {
      // Offline fallback below.
    }
    if (rows.isEmpty) {
      final cachedRows = await _databaseService.getCachedTrainStops();
      rows.addAll(
        cachedRows.map((row) => Map<String, dynamic>.from(row)),
      );
    }

    final nearestByName = <String, _StationDistanceCandidate>{};
    for (final map in rows) {
      final stopId = map['stop_id']?.toString().trim().toUpperCase() ?? '';
      final stopName = map['stop_name']?.toString().trim() ?? '';
      final routeRaw = map['route_id']?.toString().trim().toUpperCase() ?? '';
      final routeId =
          routeRaw.isEmpty ? _inferRouteIdFromStopId(stopId) : routeRaw;
      final lat = _toDouble(map['stop_lat']);
      final lon = _toDouble(map['stop_lon']);
      if (stopId.isEmpty || stopName.isEmpty || lat == null || lon == null) {
        continue;
      }

      final distance = _haversineMeters(
        latitude: latitude,
        longitude: longitude,
        targetLatitude: lat,
        targetLongitude: lon,
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
            forecast: forecasts[item.stopId] ??
                _simulateForecast(
                  stopId: item.stopId,
                  time: departureTime,
                  sourceType: 'simulated_10m',
                ),
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
      occupancyLevel: level.clamp(0, 3),
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
      occupancyLevel: occupancyLevel.clamp(0, 3),
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

  static int _defaultWaitMinutes(int level) {
    switch (level) {
      case 0:
        return 2;
      case 1:
        return 4;
      case 2:
        return 7;
      case 3:
        return 10;
      default:
        return 4;
    }
  }

  static double _defaultEtaMultiplier(int level) {
    switch (level) {
      case 0:
        return 1.0;
      case 1:
        return 1.08;
      case 2:
        return 1.18;
      case 3:
        return 1.3;
      default:
        return 1.1;
    }
  }

  static StopCrowdForecast _applyTenMinuteSimulation({
    required StopCrowdForecast base,
    required DateTime time,
  }) {
    final fluctuation = _tenMinuteFluctuation(base.stopId, time);
    final level = (base.occupancyLevel + fluctuation).clamp(0, 3);
    return StopCrowdForecast(
      stopId: base.stopId,
      forecastHour: time.hour,
      isWeekend: _isWeekend(time),
      occupancyLevel: level,
      expectedWaitMinutes: _defaultWaitMinutes(level),
      etaMultiplier: _defaultEtaMultiplier(level),
      sourceType: base.sourceType,
      updatedAt: DateTime.now(),
    );
  }

  static StopCrowdForecast _simulateForecast({
    required String stopId,
    required DateTime time,
    String sourceType = 'predicted',
  }) {
    final baseline = _baselineLevelForTime(time);
    final fluctuation = _tenMinuteFluctuation(stopId, time);
    final level = (baseline + fluctuation).clamp(0, 3);
    return StopCrowdForecast(
      stopId: stopId.trim().toUpperCase(),
      forecastHour: time.hour,
      isWeekend: _isWeekend(time),
      occupancyLevel: level,
      expectedWaitMinutes: _defaultWaitMinutes(level),
      etaMultiplier: _defaultEtaMultiplier(level),
      sourceType: sourceType,
      updatedAt: DateTime.now(),
    );
  }

  static int _baselineLevelForTime(DateTime time) {
    final hour = time.hour;
    if (hour <= 5 || hour >= 22) return 0;
    final peakHour = (hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 20);
    if (!_isWeekend(time) && peakHour) return 2;
    return 1;
  }

  static int _tenMinuteFluctuation(String stopId, DateTime time) {
    final bucket = time.minute ~/ 10; // 0..5
    final seed = stopId.toUpperCase().codeUnits.fold<int>(
          0,
          (sum, code) => sum + code,
        );
    final signal = (seed + time.hour + bucket) % 3; // 0,1,2
    return signal - 1; // -1,0,+1
  }

  static String _inferRouteIdFromStopId(String stopId) {
    final match = RegExp(r'^[A-Za-z]+').firstMatch(stopId.trim());
    return (match?.group(0) ?? 'N/A').toUpperCase();
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

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
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
