import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants/route_colors.dart';
import 'database_service.dart';

class TransitStop {
  final String stopId;
  final String stopName;
  final String routeId;
  final double latitude;
  final double longitude;
  final int sequenceOrder;

  const TransitStop({
    required this.stopId,
    required this.stopName,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    this.sequenceOrder = 0,
  });
}

class TransitConnection {
  final String fromStopId;
  final String toStopId;
  final String routeId;
  final String connectionType;
  final int travelMinutes;

  const TransitConnection({
    required this.fromStopId,
    required this.toStopId,
    required this.routeId,
    required this.connectionType,
    required this.travelMinutes,
  });

  TransitConnection reversed() {
    return TransitConnection(
      fromStopId: toStopId,
      toStopId: fromStopId,
      routeId: routeId,
      connectionType: connectionType,
      travelMinutes: travelMinutes,
    );
  }
}

class TransitStationOption {
  final String stationName;
  final List<String> stopIds;
  final List<String> routeIds;

  const TransitStationOption({
    required this.stationName,
    required this.stopIds,
    required this.routeIds,
  });
}

class TransitNetworkData {
  final Map<String, TransitStop> stopsById;
  final List<TransitConnection> connections;
  final List<TransitStationOption> stationOptions;

  const TransitNetworkData({
    required this.stopsById,
    required this.connections,
    required this.stationOptions,
  });
}

class TransitNetworkService {
  static final TransitNetworkService _instance =
      TransitNetworkService._internal();

  factory TransitNetworkService() => _instance;

  TransitNetworkService._internal();

  final DatabaseService _databaseService = DatabaseService();

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  TransitNetworkData? _cachedNetwork;
  Future<TransitNetworkData>? _inFlightLoad;
  bool _lastLoadWasFallback = false;
  DateTime? _lastFallbackAt;

  Future<TransitNetworkData> loadNetwork({bool forceRefresh = false}) {
    if (forceRefresh) {
      _cachedNetwork = null;
      _inFlightLoad = null;
    }
    final cached = _cachedNetwork;
    if (cached != null) {
      final fallbackExpired = _lastLoadWasFallback &&
          (_lastFallbackAt == null ||
              DateTime.now().difference(_lastFallbackAt!) >
                  const Duration(seconds: 60));
      if (!fallbackExpired) {
        return Future<TransitNetworkData>.value(cached);
      }
      _cachedNetwork = null;
    }
    final inflight = _inFlightLoad;
    if (inflight != null) return inflight;

    final future = _fetchNetwork();
    _inFlightLoad = future;
    return future.then((data) {
      _cachedNetwork = data;
      _lastFallbackAt = _lastLoadWasFallback ? DateTime.now() : null;
      _inFlightLoad = null;
      return data;
    }).catchError((Object error) {
      _inFlightLoad = null;
      throw error;
    });
  }

  Future<TransitNetworkData> _fetchNetwork() async {
    _lastLoadWasFallback = false;
    final rows = <Map<String, dynamic>>[];
    final client = _client;
    try {
      final remoteRows = await client!
          .from('train_stops_kl')
          .select('stop_id,stop_name,stop_lat,stop_lon,route_id,sequence_order')
          .timeout(const Duration(seconds: 10));
      final maps = remoteRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      rows.addAll(maps);
      debugPrint('TransitNetworkService: fetched ${maps.length} stops from Supabase');
      if (maps.isEmpty) {
        final restRows = await _fetchRowsViaRest(
          'train_stops_kl',
          'stop_id,stop_name,stop_lat,stop_lon,route_id,sequence_order',
        );
        debugPrint('TransitNetworkService: REST fallback returned ${restRows.length} stops');
        rows.addAll(restRows);
        if (restRows.isNotEmpty) {
          await _databaseService.cacheTrainStops(restRows);
        }
      } else {
        await _databaseService.cacheTrainStops(maps);
      }
    } catch (error) {
      debugPrint('TransitNetworkService: Supabase stop fetch failed: $error');
    }

    if (rows.isEmpty) {
      final cachedRows = await _databaseService.getCachedTrainStops();
      rows.addAll(
        cachedRows.map((row) => Map<String, dynamic>.from(row)),
      );
    }

    if (rows.isEmpty) {
      debugPrint('TransitNetworkService: using bundled offline station catalog');
      _lastLoadWasFallback = true;
      return loadOfflineFallbackFromAsset();
    }

    final stopsById = <String, TransitStop>{};
    for (final row in rows) {
      final stopId = (row['stop_id']?.toString() ?? '').trim().toUpperCase();
      final stopName = (row['stop_name']?.toString() ?? '').trim();
      final latitude = _toDouble(row['stop_lat']);
      final longitude = _toDouble(row['stop_lon']);
      if (stopId.isEmpty ||
          stopName.isEmpty ||
          latitude == null ||
          longitude == null) {
        continue;
      }

      final routeId = normalizeRouteId(
        (row['route_id']?.toString() ?? inferRouteIdFromStopId(stopId))
            .trim()
            .toUpperCase(),
      );

      stopsById[stopId] = TransitStop(
        stopId: stopId,
        stopName: stopName,
        routeId: routeId,
        latitude: latitude,
        longitude: longitude,
        sequenceOrder: _toInt(row['sequence_order']),
      );
    }

    if (stopsById.isEmpty) {
      throw StateError('No train stop data is available.');
    }

    final edgeRows = <Map<String, dynamic>>[];
    try {
      final remoteEdges = await client!.from('route_connections').select(
            'from_stop_id,to_stop_id,route_id,travel_time_minutes,connection_type',
          ).timeout(const Duration(seconds: 10));
      final maps = remoteEdges
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      edgeRows.addAll(maps);
      debugPrint('TransitNetworkService: fetched ${maps.length} connections from Supabase');
      if (maps.isEmpty) {
        final restEdges = await _fetchRowsViaRest(
          'route_connections',
          'from_stop_id,to_stop_id,route_id,travel_time_minutes,connection_type',
        );
        debugPrint('TransitNetworkService: REST fallback returned ${restEdges.length} connections');
        edgeRows.addAll(restEdges);
        if (restEdges.isNotEmpty) {
          await _databaseService.cacheRouteConnections(restEdges);
        }
      } else {
        await _databaseService.cacheRouteConnections(maps);
      }
    } catch (error) {
      debugPrint('TransitNetworkService: Supabase connection fetch failed: $error');
    }

    if (edgeRows.isEmpty) {
      final cachedEdges = await _databaseService.getCachedRouteConnections();
      edgeRows.addAll(
        cachedEdges.map((row) => Map<String, dynamic>.from(row)),
      );
    }

    final connections = _mapConnections(
      edgeRows: edgeRows,
      stopsById: stopsById,
    );
    if (connections.isEmpty) {
      connections.addAll(_buildFallbackConnections(stopsById.values.toList()));
    }

    return TransitNetworkData(
      stopsById: stopsById,
      connections: connections,
      stationOptions: _buildStationOptions(stopsById.values),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRowsViaRest(
    String path,
    String select,
  ) async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isEmpty || key.isEmpty) return const [];
    try {
      final uri = Uri.parse('$url/rest/v1/$path')
          .replace(queryParameters: {'select': select});
      final response = await http.get(
        uri,
        headers: {'apikey': key, 'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('TransitNetworkService: REST $path status ${response.statusCode}');
        return const [];
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    } catch (error) {
      debugPrint('TransitNetworkService: REST $path failed: $error');
      return const [];
    }
  }

  Future<TransitNetworkData?> _loadBundledNetworkAsset() async {
    try {
      final raw = await rootBundle.loadString('assets/data/transit_network.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final stopsById = <String, TransitStop>{};
      for (final entry in json['stations'] as List<dynamic>) {
        final station = entry as Map<String, dynamic>;
        final id = (station['id'] as String? ?? '').trim().toUpperCase();
        final name = (station['name'] as String? ?? '').trim();
        final latitude = (station['lat'] as num?)?.toDouble();
        final longitude = (station['lng'] as num?)?.toDouble();
        if (id.isEmpty ||
            name.isEmpty ||
            latitude == null ||
            longitude == null ||
            (latitude == 0 && longitude == 0)) {
          continue;
        }
        final lines = (station['lines'] as List<dynamic>? ?? const [])
            .map((line) => line.toString().toUpperCase())
            .toList();
        stopsById[id] = TransitStop(
          stopId: id,
          stopName: name,
          routeId: lines.isEmpty ? '' : normalizeRouteId(lines.first),
          latitude: latitude,
          longitude: longitude,
        );
      }
      if (stopsById.isEmpty) return null;

      final connections = <TransitConnection>[];
      for (final entry in json['connections'] as List<dynamic>) {
        final connection = entry as Map<String, dynamic>;
        final from = (connection['from'] as String? ?? '').trim().toUpperCase();
        final to = (connection['to'] as String? ?? '').trim().toUpperCase();
        if (!stopsById.containsKey(from) || !stopsById.containsKey(to)) {
          continue;
        }
        connections.add(
          TransitConnection(
            fromStopId: from,
            toStopId: to,
            routeId: normalizeRouteId(
              (connection['route'] as String? ?? '').trim().toUpperCase(),
            ),
            connectionType:
                (connection['type'] as String? ?? 'standard_stop').trim(),
            travelMinutes: (connection['minutes'] as num?)?.toInt() ?? 2,
          ),
        );
      }

      return TransitNetworkData(
        stopsById: stopsById,
        connections: connections,
        stationOptions: _buildStationOptions(stopsById.values),
      );
    } catch (_) {
      return null;
    }
  }

  Future<TransitNetworkData> loadOfflineFallbackFromAsset() async {
    final bundled = await _loadBundledNetworkAsset();
    if (bundled != null) return bundled;

    final raw = await rootBundle.loadString('assets/train_stops_kl.csv');
    final rows = const LineSplitter().convert(raw).skip(1).where((line) => line.trim().isNotEmpty).toList();

    final stopsById = <String, TransitStop>{};
    var sequence = 0;
    for (final line in rows) {
      final columns = line.split(',');
      if (columns.length < 5) continue;
      final stopId = columns[0].trim().toUpperCase();
      final stopName = columns[1].trim();
      final routeId = normalizeRouteId(columns[2].trim().toUpperCase());
      final latitude = double.tryParse(columns[3].trim());
      final longitude = double.tryParse(columns[4].trim());
      if (stopId.isEmpty || stopName.isEmpty || latitude == null || longitude == null) {
        continue;
      }
      sequence++;
      stopsById[stopId] = TransitStop(
        stopId: stopId,
        stopName: stopName,
        routeId: routeId,
        latitude: latitude,
        longitude: longitude,
        sequenceOrder: sequence,
      );
    }

    if (stopsById.isEmpty) {
      throw StateError('No local station data is available.');
    }

    final connections = _buildFallbackConnections(stopsById.values.toList());
    return TransitNetworkData(
      stopsById: stopsById,
      connections: connections,
      stationOptions: _buildStationOptions(stopsById.values),
    );
  }

  static List<TransitConnection> _mapConnections({
    required List<Map<String, dynamic>> edgeRows,
    required Map<String, TransitStop> stopsById,
  }) {
    final output = <TransitConnection>[];
    for (final row in edgeRows) {
      final from = (row['from_stop_id']?.toString() ?? '').trim().toUpperCase();
      final to = (row['to_stop_id']?.toString() ?? '').trim().toUpperCase();
      if (!stopsById.containsKey(from) || !stopsById.containsKey(to)) {
        continue;
      }
      final routeId = normalizeRouteId(
        (row['route_id']?.toString() ?? '').trim().toUpperCase(),
      );
      final type =
          (row['connection_type']?.toString() ?? 'standard_stop').trim();
      final minutesRaw = row['travel_time_minutes'];
      final minutes = minutesRaw is num
          ? minutesRaw.toInt()
          : int.tryParse(minutesRaw?.toString() ?? '') ?? 2;

      output.add(
        TransitConnection(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          connectionType: type,
          travelMinutes: minutes,
        ),
      );
    }
    return output;
  }

  static List<TransitConnection> _buildFallbackConnections(
    List<TransitStop> stops,
  ) {
    final edges = <TransitConnection>[];
    final seen = <String>{};

    void addEdge({
      required String from,
      required String to,
      required String routeId,
      required String type,
      required int minutes,
    }) {
      final key = '$from|$to|$routeId|$type';
      if (!seen.add(key)) return;
      edges.add(
        TransitConnection(
          fromStopId: from,
          toStopId: to,
          routeId: routeId,
          connectionType: type,
          travelMinutes: minutes,
        ),
      );
    }

    final byLine = <String, List<TransitStop>>{};
    for (final stop in stops) {
      byLine.putIfAbsent(stop.routeId, () => <TransitStop>[]).add(stop);
    }

    for (final entry in byLine.entries) {
      final ordered = List<TransitStop>.from(entry.value)
        ..sort((a, b) => compareStopCode(a.stopId, b.stopId));
      for (var i = 0; i < ordered.length - 1; i++) {
        addEdge(
          from: ordered[i].stopId,
          to: ordered[i + 1].stopId,
          routeId: entry.key,
          type: 'standard_stop',
          minutes: 2,
        );
        addEdge(
          from: ordered[i + 1].stopId,
          to: ordered[i].stopId,
          routeId: entry.key,
          type: 'standard_stop',
          minutes: 2,
        );
      }
    }

    final byStation = <String, List<TransitStop>>{};
    for (final stop in stops) {
      byStation
          .putIfAbsent(stop.stopName.toUpperCase(), () => <TransitStop>[])
          .add(stop);
    }

    for (final stationStops in byStation.values) {
      if (stationStops.length < 2) continue;
      for (var i = 0; i < stationStops.length - 1; i++) {
        for (var j = i + 1; j < stationStops.length; j++) {
          final a = stationStops[i];
          final b = stationStops[j];
          if (a.routeId == b.routeId) continue;
          addEdge(
            from: a.stopId,
            to: b.stopId,
            routeId: b.routeId,
            type: 'interchange_transfer',
            minutes: 3,
          );
          addEdge(
            from: b.stopId,
            to: a.stopId,
            routeId: a.routeId,
            type: 'interchange_transfer',
            minutes: 3,
          );
        }
      }
    }

    return edges;
  }

  static List<TransitStationOption> _buildStationOptions(
    Iterable<TransitStop> stops,
  ) {
    final grouped = <String, List<TransitStop>>{};
    for (final stop in stops) {
      grouped
          .putIfAbsent(stop.stopName.toUpperCase(), () => <TransitStop>[])
          .add(stop);
    }

    final options = grouped.values.map((groupedStops) {
      final sorted = List<TransitStop>.from(groupedStops)
        ..sort((a, b) => compareStopCode(a.stopId, b.stopId));
      final routeIds = <String>{
        for (final stop in sorted) stop.routeId,
      }.toList()
        ..sort();
      return TransitStationOption(
        stationName: sorted.first.stopName,
        stopIds: sorted.map((stop) => stop.stopId).toList(),
        routeIds: routeIds,
      );
    }).toList()
      ..sort((a, b) => a.stationName.compareTo(b.stationName));

    return options;
  }

  static String inferRouteIdFromStopId(String stopId) {
    final match = RegExp(r'^[A-Za-z]+').firstMatch(stopId.trim());
    return (match?.group(0) ?? 'N/A').toUpperCase();
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }
}

int compareStopCode(String a, String b) {
  final pa = _StopIdParts.tryParse(a);
  final pb = _StopIdParts.tryParse(b);
  if (pa == null || pb == null) return a.compareTo(b);
  if (pa.prefix != pb.prefix) return pa.prefix.compareTo(pb.prefix);
  if (pa.number != pb.number) return pa.number.compareTo(pb.number);
  return pa.suffix.compareTo(pb.suffix);
}

class _StopIdParts {
  final String prefix;
  final int number;
  final String suffix;

  const _StopIdParts({
    required this.prefix,
    required this.number,
    required this.suffix,
  });

  static _StopIdParts? tryParse(String stopId) {
    final match = RegExp(r'^([A-Z]+)(\d+)([A-Z]*)$')
        .firstMatch(stopId.trim().toUpperCase());
    if (match == null) return null;
    final number = int.tryParse(match.group(2) ?? '');
    if (number == null) return null;
    return _StopIdParts(
      prefix: match.group(1) ?? '',
      number: number,
      suffix: match.group(3) ?? '',
    );
  }
}
