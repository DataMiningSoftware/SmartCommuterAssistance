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

  CrowdReport? _toCrowdReport(Map<String, dynamic> map) {
    final stopId = map['stop_id']?.toString() ?? '';
    if (stopId.isEmpty) return null;
    final levelRaw = map['occupancy_level'];
    final level = levelRaw is num ? levelRaw.toInt() : int.tryParse(levelRaw.toString()) ?? 0;

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
}
