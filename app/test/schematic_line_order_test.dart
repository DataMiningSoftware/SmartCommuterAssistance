import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/models/schematic_layout.dart';
import 'package:smart_commuter/models/transit_graph.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const visibleLines = <String, String>{
    '3': 'AG',
    '4': 'SP',
    '5': 'KJ',
    '8': 'MR',
    '9': 'KG',
    '12': 'PY',
    'B1': 'BRT',
  };

  Future<(SchematicLayout, TransitGraph)> load() async {
    final raw = await rootBundle.loadString('assets/data/transit_network.json');
    final graph =
        TransitGraph.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    final layout = await SchematicLayout.load();
    layout.reorderUsingGraph(graph);
    return (layout, graph);
  }

  test('every visible line follows the graph physical stop sequence', () async {
    final (layout, graph) = await load();

    for (final entry in visibleLines.entries) {
      final lineId = entry.key;
      final prefix = entry.value;
      final line = layout.lines[lineId]!;

      final nativeGraphOrder = (graph.lineStationOrder[prefix] ?? const [])
          .where((id) => id.startsWith(prefix))
          .toList();

      expect(nativeGraphOrder, isNotEmpty, reason: 'no graph order for $prefix');
      expect(
        line.stationIds,
        equals(nativeGraphOrder),
        reason: 'line $lineId not ordered by TransitGraph.lineStationOrder',
      );
    }
  });

  test('consecutive stations are physically adjacent (no zigzag)', () async {
    final (layout, graph) = await load();

    for (final entry in visibleLines.entries) {
      final line = layout.lines[entry.key]!;
      final order = line.stationIds;
      expect(order.length, greaterThanOrEqualTo(2),
          reason: 'line ${entry.key} has fewer than 2 stations');

      for (var i = 0; i < order.length - 1; i++) {
        final a = order[i];
        final b = order[i + 1];
        final forward = (graph.adjacency[a] ?? const <TransitEdge>[])
            .any((e) => e.to == b);
        final backward = (graph.adjacency[b] ?? const <TransitEdge>[])
            .any((e) => e.to == a);
        expect(forward || backward, isTrue,
            reason: 'line ${entry.key}: $a -> $b are not adjacent in the graph');
      }
    }
  });

  test('lines contain only their native stations (trunk deduplicated)', () async {
    final (layout, _) = await load();

    for (final entry in visibleLines.entries) {
      final line = layout.lines[entry.key]!;
      final prefix = entry.value;
      for (final id in line.stationIds) {
        expect(id.startsWith(prefix), isTrue,
            reason: 'line ${entry.key} contains non-native station $id');
      }
    }
  });

  test('KJ line native stations are KJ1..KJ37 in order', () async {
    final (layout, _) = await load();
    final kj = layout.lines['5']!.stationIds
        .where((id) => id.startsWith('KJ'))
        .toList();
    final numbers = [
      for (final id in kj)
        int.parse(RegExp(r'^KJ(\d+)').firstMatch(id)!.group(1)!),
    ];
    final ascending = [for (var n = 1; n <= 37; n++) n];
    final descending = List<int>.from(ascending.reversed);
    expect(
      numbers,
      anyOf(equals(ascending), equals(descending)),
      reason: 'KJ order: $numbers',
    );
  });
}
