import 'dart:convert';

import 'package:http/http.dart' as http;

class WalkingRouteService {
  WalkingRouteService._();

  static final WalkingRouteService instance = WalkingRouteService._();

  static const String _endpoint =
      'https://valhalla1.openstreetmap.de/sources_to_targets';
  static const Duration _timeout = Duration(seconds: 7);
  static const Duration _cacheTtl = Duration(minutes: 10);

  final Map<String, _MatrixCacheEntry> _cache = {};

  Future<Map<int, ({double meters, int seconds})>> matrix({
    required double fromLat,
    required double fromLon,
    required List<({double lat, double lon})> targets,
  }) async {
    if (targets.isEmpty) return const {};
    final key = '${fromLat.toStringAsFixed(4)},${fromLon.toStringAsFixed(4)}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.createdAt) < _cacheTtl &&
        cached.targetCount == targets.length) {
      return cached.result;
    }

    Map<int, ({double meters, int seconds})> result = const {};
    try {
      final payload = jsonEncode({
        'sources': [
          {'lat': fromLat, 'lon': fromLon},
        ],
        'targets': [
          for (final target in targets) {'lat': target.lat, 'lon': target.lon},
        ],
        'costing': 'pedestrian',
      });
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {'json': payload},
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SmartCommuterAssistant/1.0'},
      ).timeout(_timeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final rows = decoded['sources_to_targets'];
        if (rows is List && rows.isNotEmpty) {
          final first = rows.first;
          if (first is List) {
            final parsed = <int, ({double meters, int seconds})>{};
            for (final row in first) {
              if (row is! Map) continue;
              final indexRaw = row['to_index'];
              final distance = (row['distance'] as num?)?.toDouble();
              final time = (row['time'] as num?)?.toDouble();
              final index = indexRaw is num ? indexRaw.toInt() : null;
              if (index == null || distance == null || time == null) continue;
              parsed[index] = (meters: distance * 1000, seconds: time.round());
            }
            result = parsed;
          }
        }
      }
    } catch (_) {}

    _cache[key] = _MatrixCacheEntry(
      createdAt: DateTime.now(),
      targetCount: targets.length,
      result: result,
    );
    return result;
  }
}

class _MatrixCacheEntry {
  final DateTime createdAt;
  final int targetCount;
  final Map<int, ({double meters, int seconds})> result;

  const _MatrixCacheEntry({
    required this.createdAt,
    required this.targetCount,
    required this.result,
  });
}
