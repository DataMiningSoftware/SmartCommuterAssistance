import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/station_name_matcher.dart';
import 'transit_graph.dart';

class SchematicLayoutStation {
  final String id;
  final String name;
  final double x;
  final double y;
  final List<String> lines;
  final bool isInterchange;

  const SchematicLayoutStation({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.lines,
    required this.isInterchange,
  });
}

class SchematicLayoutLine {
  final String id;
  final ui.Color color;
  final String label;
  final List<String> stationIds;

  const SchematicLayoutLine({
    required this.id,
    required this.color,
    required this.label,
    this.stationIds = const [],
  });
}

class SchematicLayout {
  final Map<String, SchematicLayoutStation> stations;
  final Map<String, SchematicLayoutLine> lines;

  SchematicLayout({
    required this.stations,
    required this.lines,
  });

  static Future<SchematicLayout> load() async {
    final raw = await rootBundle.loadString('assets/schematic_layout.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final gridW = (json['gridColumns'] as num?)?.toDouble() ?? 100;
    final gridH = (json['gridRows'] as num?)?.toDouble() ?? 140;

    final lineMap = <String, SchematicLayoutLine>{};
    for (final entry in (json['lines'] as Map<String, dynamic>).entries) {
      final id = entry.key;
      final data = entry.value as Map<String, dynamic>;
      final colorStr = data['color'] as String;
      lineMap[id] = SchematicLayoutLine(
        id: id,
        color: ui.Color(int.parse(colorStr.replaceFirst('#', '0xFF'))),
        label: data['label'] as String,
      );
    }

    final byLine = <String, Set<String>>{};
    for (final entry in (json['stations'] as Map<String, dynamic>).entries) {
      final sid = entry.key;
      final data = entry.value as Map<String, dynamic>;
      final lineIds = (data['lines'] as List<dynamic>).cast<String>();
      for (final lineId in lineIds) {
        byLine.putIfAbsent(lineId, () => {}).add(sid);
      }
    }
    for (final entry in lineMap.entries) {
      final ids = byLine[entry.key]?.toList() ?? <String>[];
      ids.sort();
      lineMap[entry.key] = SchematicLayoutLine(
        id: entry.key,
        color: entry.value.color,
        label: entry.value.label,
        stationIds: ids,
      );
    }

    final stationMap = <String, SchematicLayoutStation>{};
    for (final entry in (json['stations'] as Map<String, dynamic>).entries) {
      final id = entry.key;
      final data = entry.value as Map<String, dynamic>;
      stationMap[id] = SchematicLayoutStation(
        id: id,
        name: (data['name'] as String).toUpperCase(),
        x: (data['x'] as num).toDouble() / gridW,
        y: (data['y'] as num).toDouble() / gridH,
        lines: (data['lines'] as List<dynamic>).cast<String>(),
        isInterchange: data['is_interchange'] as bool? ?? (data['lines'] as List<dynamic>).length > 1,
      );
    }

    return SchematicLayout(
      stations: stationMap,
      lines: lineMap,
    );
  }

  void reorderUsingGraph(TransitGraph graph) {
    const lineToGraphRoutes = <String, List<String>>{
      '1': ['KT1', 'KC'],
      '2': ['KT2', 'KD'],
      '3': ['AG'],
      '4': ['SP', 'PH'],
      '5': ['KJ'],
      '6': ['KLIA EKSPRES', 'KLIA_EKSPRES', 'KLIA_EXSPRES'],
      '7': ['KLIA TRANSIT', 'KLIA_TRANSIT'],
      '8': ['MR'],
      '9': ['KG', 'MRT'],
      '10': ['KS'],
      '11': ['JS'],
      '12': ['PY', 'PYL'],
      'B1': ['BRT'],
    };

    final matcher = StationNameMatcher.instance;
    final nameToSid = <String, String>{};
    for (final entry in stations.entries) {
      nameToSid[matcher.normalize(entry.value.name)] = entry.key;
    }

    final updatedLines = <String, SchematicLayoutLine>{};
    for (final lineEntry in lines.entries) {
      final lineId = lineEntry.key;
      final schematicLine = lineEntry.value;
      final routeIds = lineToGraphRoutes[lineId] ?? [];

      final ordered = <String>[];
      final seen = <String>{};
      for (final routeId in routeIds) {
        final order = graph.lineStationOrder[routeId];
        if (order == null) continue;
        for (final graphId in order) {
          final gs = graph.stations[graphId];
          if (gs == null) continue;
          final normalized = matcher.normalize(gs.name);
          String? sid;
          for (final e in nameToSid.entries) {
            if (matcher.match(e.key, normalized)) {
              sid = e.value;
              break;
            }
          }
          if (sid != null && schematicLine.stationIds.contains(sid) && seen.add(sid)) {
            ordered.add(sid);
          }
        }
      }

      final appended = <String>[];
      for (final sid in schematicLine.stationIds) {
        if (seen.add(sid)) {
          ordered.add(sid);
          appended.add(sid);
        }
      }

      if (appended.isNotEmpty) {
        final names = appended.map((sid) => stations[sid]?.name ?? sid).toList();
        debugPrint(
          'reorderUsingGraph: Line $lineId (${schematicLine.label}): '
          '${appended.length} station(s) unmatched, appended: $names',
        );
      }

      updatedLines[lineId] = SchematicLayoutLine(
        id: lineId,
        color: schematicLine.color,
        label: schematicLine.label,
        stationIds: ordered,
      );
    }
    lines..clear()..addAll(updatedLines);
  }

  List<List<String>> computeLineOrders(TransitGraph graph) {
    final orders = <List<String>>[];
    final byLine = <String, Set<String>>{};
    for (final station in stations.values) {
      for (final line in station.lines) {
        byLine.putIfAbsent(line, () => {}).add(station.id);
      }
    }
    for (final entry in byLine.entries) {
      final line = entry.key;
      if (line == 'INTERCHANGE') continue;
      final stationsOnLine = entry.value;
      orders.add(_topologicalOrder(graph, line, stationsOnLine));
    }
    return orders;
  }

  List<String> _topologicalOrder(TransitGraph graph, String line, Set<String> stationsOnLine) {
    if (stationsOnLine.length < 2) return stationsOnLine.toList();
    final adj = <String, List<String>>{};
    for (final sid in stationsOnLine) {
      for (final edge in (graph.adjacency[sid] ?? [])) {
        if (edge.line == line && stationsOnLine.contains(edge.to)) {
          adj.putIfAbsent(sid, () => []).add(edge.to);
        }
      }
    }
    String? findTerminal() {
      for (final sid in stationsOnLine) {
        var outDeg = adj[sid]?.length ?? 0;
        var inDeg = 0;
        for (final other in stationsOnLine) {
          if (adj[other]?.contains(sid) == true) inDeg++;
        }
        if (outDeg + inDeg == 1) return sid;
      }
      return null;
    }
    final start = findTerminal() ?? stationsOnLine.first;
    final ordered = <String>[start];
    final visited = <String>{start};
    var current = start;
    while (true) {
      final next = (adj[current] ?? []).where((n) => !visited.contains(n));
      if (next.isEmpty) {
        final back = (stationsOnLine.where(
            (s) => (adj[s]?.contains(current) == true) && !visited.contains(s)));
        if (back.isEmpty) break;
        current = back.first;
      } else {
        current = next.first;
      }
      visited.add(current);
      ordered.add(current);
      if (ordered.length >= stationsOnLine.length) break;
    }
    return ordered;
  }
}
