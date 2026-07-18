import 'dart:convert';

import 'package:flutter/services.dart';

import 'train_arrival_service.dart';

class GtfsLocalService {
  GtfsLocalService._();

  static Map<String, _StopSchedule>? _cache;

  static Future<Map<String, _StopSchedule>> _load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/data/gtfs_schedule.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final stopsJson = json['stops'] as Map<String, dynamic>;
    final result = <String, _StopSchedule>{};
    for (final entry in stopsJson.entries) {
      final sid = entry.key;
      final s = entry.value as Map<String, dynamic>;
      final groups = <_ArrivalGroup>[];
      for (final g in (s['s'] as List<dynamic>)) {
        final gMap = g as Map<String, dynamic>;
        final times = <int, List<int>>{};
        for (final dayKey in gMap.keys) {
          if (dayKey == 'r' || dayKey == 'rs' || dayKey == 'rl' || dayKey == 'd') continue;
          if (dayKey == '*') {
            final arr = (gMap['*'] as List<dynamic>).cast<num>().map((e) => e.toInt()).toList();
            for (var d = 0; d < 7; d++) {
              times[d] = arr;
            }
          } else {
            final d = int.tryParse(dayKey);
            if (d != null) {
              times[d] = (gMap[dayKey] as List<dynamic>).cast<num>().map((e) => e.toInt()).toList();
            }
          }
        }
        groups.add(_ArrivalGroup(
          routeId: gMap['r'] as String? ?? '',
          routeShortName: gMap['rs'] as String? ?? '',
          routeLongName: gMap['rl'] as String? ?? '',
          destination: gMap['d'] as String? ?? '',
          timesByDay: times,
        ));
      }
      result[sid] = _StopSchedule(name: s['n'] as String? ?? '', groups: groups);
    }
    _cache = result;
    return result;
  }

  static Future<StationArrivalResult> getArrivals(
    String stopId, {
    int limit = 4,
    DateTime? at,
  }) async {
    final now = at ?? DateTime.now();
    final dayOfWeek = now.weekday == 7 ? 0 : now.weekday;
    final secs = now.hour * 3600 + now.minute * 60 + now.second;

    final schedule = await _load();
    final stop = schedule[stopId.toUpperCase()];
    if (stop == null) {
      return StationArrivalResult(
        stopId: stopId,
        stopName: stopId,
        generatedAt: now,
        arrivals: [],
      );
    }

    final arrivals = <ScheduledTrainArrival>[];
    for (final group in stop.groups) {
      final times = group.timesByDay[dayOfWeek] ?? group.timesByDay.values.expand((t) => t).toList()..sort();
      for (final t in times) {
        if (t < secs) continue;
        if (arrivals.length >= limit * 4) break;
        final arrivalDt = DateTime(now.year, now.month, now.day)
            .add(Duration(seconds: t))
            .add(now.timeZoneOffset);
        arrivals.add(ScheduledTrainArrival(
          stopId: stopId,
          stopName: stop.name,
          routeId: group.routeId,
          routeShortName: group.routeShortName,
          routeLongName: group.routeLongName,
          destination: group.destination,
          arrivalTime: arrivalDt,
          minutesUntil: (t - secs) ~/ 60,
          source: 'gtfs_static_schedule',
        ));
        if (arrivals.length >= limit * 4) break;
      }
    }

    arrivals.sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
    return StationArrivalResult(
      stopId: stopId,
      stopName: stop.name,
      generatedAt: now,
      arrivals: arrivals.take(limit).toList(),
    );
  }
}

class _StopSchedule {
  final String name;
  final List<_ArrivalGroup> groups;
  const _StopSchedule({required this.name, required this.groups});
}

class _ArrivalGroup {
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final String destination;
  final Map<int, List<int>> timesByDay;
  const _ArrivalGroup({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.destination,
    required this.timesByDay,
  });
}
