import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

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
      lineMap[entry.key] = SchematicLayoutLine(
        id: entry.key,
        color: entry.value.color,
        label: entry.value.label,
        stationIds: _orderLineStations(entry.key, ids),
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
    final updatedLines = <String, SchematicLayoutLine>{};
    for (final lineEntry in lines.entries) {
      final lineId = lineEntry.key;
      final schematicLine = lineEntry.value;
      updatedLines[lineId] = SchematicLayoutLine(
        id: lineId,
        color: schematicLine.color,
        label: schematicLine.label,
        stationIds: _orderLineStations(
          lineId,
          schematicLine.stationIds,
          graph: graph,
        ),
      );
    }
    lines..clear()..addAll(updatedLines);
  }

  static const Map<String, String> _lineToGraphRoute = {
    '1': 'KT1',
    '2': 'KT2',
    '3': 'AG',
    '4': 'SP',
    '5': 'KJ',
    '6': 'ER6',
    '7': 'ER7',
    '8': 'MR',
    '9': 'KG',
    '10': 'KS',
    '11': 'JS',
    '12': 'PY',
    'B1': 'BRT',
  };

  static const Map<String, List<String>> _lineStationPrefixes = {
    '1': ['KT1'],
    '2': ['KT2'],
    '3': ['AG'],
    '4': ['SP'],
    '5': ['KJ'],
    '6': ['ER6'],
    '7': ['ER7'],
    '8': ['MR'],
    '9': ['KG'],
    '10': ['KS'],
    '11': ['JS'],
    '12': ['PY'],
    'B1': ['BRT'],
  };

  static List<String> _orderLineStations(
    String lineId,
    List<String> stationIds, {
    TransitGraph? graph,
  }) {
    final prefixes = _lineStationPrefixes[lineId] ?? const <String>[];
    final owned = <String>[];
    for (final sid in stationIds) {
      if (prefixes.any((p) => sid.startsWith(p))) owned.add(sid);
    }

    // Numeric-prefixed lines filter to their own stops; name-based lines
    // (KTM / ERL) keep the full station set and rely on the graph order.
    final candidateIds = owned.isNotEmpty ? owned : stationIds;

    final routeId = _lineToGraphRoute[lineId];
    if (graph != null && routeId != null && candidateIds.isNotEmpty) {
      final graphOrder = graph.lineStationOrder[routeId] ?? const <String>[];
      final candidateSet = candidateIds.toSet();
      final ordered = <String>[];
      final seen = <String>{};
      for (final id in graphOrder) {
        if (candidateSet.contains(id) && seen.add(id)) ordered.add(id);
      }
      for (final id in candidateIds) {
        if (seen.add(id)) ordered.add(id);
      }
      return ordered;
    }

    final result = List<String>.from(candidateIds);
    result.sort(_compareStationIds);
    return result;
  }

  static int _compareStationIds(String a, String b) {
    final pa = _StationIdParts.tryParse(a);
    final pb = _StationIdParts.tryParse(b);
    if (pa != null && pb != null) {
      final prefixCmp = pa.prefix.compareTo(pb.prefix);
      if (prefixCmp != 0) return prefixCmp;
      final numberCmp = pa.number.compareTo(pb.number);
      if (numberCmp != 0) return numberCmp;
      return pa.suffix.compareTo(pb.suffix);
    }
    return a.compareTo(b);
  }
}

class _StationIdParts {
  final String prefix;
  final int number;
  final String suffix;

  const _StationIdParts({
    required this.prefix,
    required this.number,
    required this.suffix,
  });

  static _StationIdParts? tryParse(String stationId) {
    final match = RegExp(r'^([A-Za-z]+)(\d+)([A-Za-z]*)$')
        .firstMatch(stationId.trim().toUpperCase());
    if (match == null) return null;
    final number = int.tryParse(match.group(2) ?? '');
    if (number == null) return null;
    return _StationIdParts(
      prefix: match.group(1) ?? '',
      number: number,
      suffix: match.group(3) ?? '',
    );
  }
}
