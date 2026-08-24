import 'dart:convert';

import 'package:flutter/services.dart';
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

  Future<TransitNetworkData> loadNetwork({bool forceRefresh = false}) {
    if (forceRefresh) {
      _cachedNetwork = null;
      _inFlightLoad = null;
    }
    final cached = _cachedNetwork;
    if (cached != null) return Future<TransitNetworkData>.value(cached);
    final inflight = _inFlightLoad;
    if (inflight != null) return inflight;

    final future = _fetchNetwork();
    _inFlightLoad = future;
    return future.then((data) {
      _cachedNetwork = data;
      _inFlightLoad = null;
      return data;
    }).catchError((Object error) {
      _inFlightLoad = null;
      throw error;
    });
  }

  Future<TransitNetworkData> _fetchNetwork() async {
    final rows = <Map<String, dynamic>>[];
    final client = _client;
    try {
      final remoteRows = await client!
          .from('train_stops_kl')
          .select('stop_id,stop_name,stop_lat,stop_lon,route_id,sequence_order')
          .timeout(const Duration(seconds: 5));
      final maps = remoteRows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      rows.addAll(maps);
      if (maps.isNotEmpty) {
        await _databaseService.cacheTrainStops(maps);
      }
    } catch (_) {
      // Fall back to cache.
    }

    if (rows.isEmpty) {
      final cachedRows = await _databaseService.getCachedTrainStops();
      rows.addAll(
        cachedRows.map((row) => Map<String, dynamic>.from(row)),
      );
    }

    if (rows.isEmpty) {
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
          ).timeout(const Duration(seconds: 5));
      final maps = remoteEdges
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      edgeRows.addAll(maps);
      if (maps.isNotEmpty) {
        await _databaseService.cacheRouteConnections(maps);
      }
    } catch (_) {
      // Fall back to cache.
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

  Future<TransitNetworkData> loadOfflineFallbackFromAsset() async {
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
