import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

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
    return _toCrowdReport(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<Map<String, CrowdReport>> fetchLatestCrowdReportsForStops(
    List<String> stopIds,
  ) async {
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
      if (report == null) continue;
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

    final rows = await _client
        .from('crowd_forecast_hourly')
        .select(
          'stop_id,forecast_hour,is_weekend,occupancy_level,expected_wait_minutes,eta_multiplier,source_type,updated_at',
        )
        .inFilter('stop_id', normalizedStopIds)
        .inFilter('forecast_hour', hours)
        .inFilter('is_weekend', weekendFlags);

    final forecasts = <String, StopCrowdForecast>{};
    for (final row in rows.whereType<Map>()) {
      final forecast = _toStopCrowdForecast(Map<String, dynamic>.from(row));
      if (forecast == null) continue;
      forecasts[forecastKey(
        stopId: forecast.stopId,
        forecastHour: forecast.forecastHour,
        isWeekend: forecast.isWeekend,
      )] = forecast;
    }

    final latestByStop =
        await fetchLatestCrowdReportsForStops(normalizedStopIds);
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
    final rows = await _client
        .from('train_stops_kl')
        .select('stop_id,stop_name,stop_lat,stop_lon,route_id');

    final nearestByName = <String, _StationDistanceCandidate>{};
    for (final row in rows.whereType<Map>()) {
      final map = Map<String, dynamic>.from(row);
      final stopId = map['stop_id']?.toString().trim().toUpperCase() ?? '';
      final stopName = map['stop_name']?.toString().trim() ?? '';
      final routeId = map['route_id']?.toString().trim().toUpperCase() ?? '';
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

    final forecasts = await fetchForecastForStopsAtTime(
      limited.map((item) => item.stopId).toList(),
      departureTime,
    );

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
