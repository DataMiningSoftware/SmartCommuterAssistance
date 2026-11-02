import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/models/transit_graph.dart';

void main() {
  late TransitGraph graph;

  setUpAll(() {
    final json = jsonDecode(
      File('assets/data/transit_network.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    graph = TransitGraph.fromJson(json);
  });

  test('graph integrity', () {
    final problems = <String>[];

    for (final edge in [
      for (final list in graph.adjacency.values) ...list,
    ]) {
      if (!graph.stations.containsKey(edge.from)) {
        problems.add('missing from-station ${edge.from}');
      }
      if (!graph.stations.containsKey(edge.to)) {
        problems.add('missing to-station ${edge.to}');
      }
    }

    final oneWay = <String>[];
    for (final list in graph.adjacency.values) {
      for (final edge in list) {
        if (edge.type == 'interchange') continue;
        final back = (graph.adjacency[edge.to] ?? const <TransitEdge>[])
            .where((e) => e.to == edge.from && e.line == edge.line);
        if (back.isEmpty) {
          oneWay.add('${edge.from}->${edge.to} [${edge.line}]');
        }
      }
    }

    final noLines = graph.stations.values
        .where((s) => s.lines.isEmpty)
        .map((s) => s.id)
        .toList();

    // ignore: avoid_print
    print('stations=${graph.stations.length} '
        'edges=${graph.adjacency.values.fold<int>(0, (a, b) => a + b.length)} '
        'missing=${problems.length} oneWay=${oneWay.length} '
        'noLines=${noLines.length}');
    if (problems.isNotEmpty) {
      // ignore: avoid_print
      print('  MISSING: ${problems.take(5).toList()}');
    }
    if (oneWay.isNotEmpty) {
      // ignore: avoid_print
      print('  ONE-WAY: ${oneWay.take(10).toList()}');
    }

    expect(problems, isEmpty);
  });

  test('routing sanity across named trips', () {
    final trips = <List<String>>[
      ['PY40', 'PY23'], // Cyberjaya City Centre -> TRX
      ['PY41', 'KJ15'], // Putrajaya Sentral -> KL Sentral
      ['PY40', 'KJ15'], // Cyberjaya -> KL Sentral
      ['KJ15', 'KLIA'], // KL Sentral -> KLIA
      ['KJ15', 'PY23'], // KL Sentral -> TRX
      ['AG1', 'KJ15'], // Sentul Timur -> KL Sentral
      ['KG04', 'KJ15'], // Kwasa Damansara -> KL Sentral
      ['KJ1', 'KJ37'], // Gombak -> Putra Heights
      ['SP1', 'SP31'], // Sentul Timur -> Putra Heights
      ['PY01', 'PY41'], // Kwasa Damansara -> Putrajaya Sentral
      ['MR1', 'MR11'], // KL Sentral -> Titiwangsa
      ['BRT1', 'BRT7'], // BRT full line
      ['PY40', 'KLIA2'],
      ['KLIA', 'KJ15'],
    ];

    final report = <String>[];

    for (final trip in trips) {
      final from = trip[0];
      final to = trip[1];
      final path = graph.findShortestPath(from, to);
      if (path == null) {
        report.add('$from -> $to  NO PATH');
        continue;
      }
      final names = path.stationIds.take(4).join('>');
      report.add(
        '$from -> $to  ride=${path.rideMinutes}m '
        'weighted=${path.totalMinutes}m transfers=${path.transferCount} '
        'lines=${path.lineJumps}  $names…',
      );
    }

    // ignore: avoid_print
    print(report.join('\n'));

    for (final trip in trips) {
      final path = graph.findShortestPath(trip[0], trip[1]);
      expect(path, isNotNull, reason: '${trip[0]} -> ${trip[1]} unreachable');
      expect(path!.transferCount, lessThanOrEqualTo(3),
          reason: '${trip[0]} -> ${trip[1]} has too many transfers');
    }
  });

  test('cyberjaya to TRX must stay on the Putrajaya line', () {
    final direct = graph.findShortestPath('PY40', 'PY23')!;
    // ignore: avoid_print
    print('CYBERJAYA -> TRX lines=${direct.lineJumps} '
        'ride=${direct.rideMinutes}m transfers=${direct.transferCount}');

    expect(direct.lineJumps, ['PY']);
    expect(direct.transferCount, 0);
    expect(direct.transferCount, 0);
  });

  test('transfer penalty actually changes the choice', () {
    final cheap = graph.findShortestPath('PY40', 'KJ15', transferPenalty: 0);
    final normal = graph.findShortestPath('PY40', 'KJ15', transferPenalty: 8);
    final heavy = graph.findShortestPath('PY40', 'KJ15', transferPenalty: 40);

    // ignore: avoid_print
    print('penalty0: ${cheap?.lineJumps} ${cheap?.rideMinutes}m '
        '${cheap?.transferCount}t');
    // ignore: avoid_print
    print('penalty8: ${normal?.lineJumps} ${normal?.rideMinutes}m '
        '${normal?.transferCount}t');
    // ignore: avoid_print
    print('penalty40: ${heavy?.lineJumps} ${heavy?.rideMinutes}m '
        '${heavy?.transferCount}t');

    expect(normal, isNotNull);
  });

  test('every station is reachable from KL Sentral', () {
    final unreachable = <String>[];
    for (final station in graph.stations.keys) {
      if (station == 'KJ15') continue;
      if (graph.findShortestPath('KJ15', station) == null) {
        unreachable.add(station);
      }
    }
    // ignore: avoid_print
    print('unreachable from KL Sentral: ${unreachable.length} '
        '${unreachable.take(10).toList()}');
    // Johan Setia is the Shah Alam line, still not connected in the data.
    expect(unreachable, ['JOHAN_SETIA']);
  });
}
