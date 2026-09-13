import 'dart:math';

import '../constants/route_colors.dart';
import 'transit_graph.dart';

const Map<String, String> kLineDisplayNames = {
  'KJ': 'LRT Kelana Jaya',
  'MRT': 'MRT Kajang',
  'PYL': 'MRT Putrajaya',
  'AG': 'LRT Ampang',
  'PH': 'LRT Sri Petaling',
  'MR': 'KL Monorail',
  'BRT': 'BRT Sunway',
};

String lineDisplayName(String routeId) {
  final normalized = normalizeRouteId(routeId);
  return kLineDisplayNames[normalized] ?? normalized;
}

class TriviaQuestion {
  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String kind;
  final String? stationId;
  final String explanation;

  const TriviaQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.kind,
    this.stationId,
    required this.explanation,
  });
}

class TriviaGenerator {
  final Random _rng;
  TriviaGenerator([Random? rng]) : _rng = rng ?? Random();

  static const List<String> _allLineIds = ['KJ', 'MRT', 'PYL', 'AG', 'PH', 'MR', 'BRT'];

  TriviaQuestion generate(TransitGraph graph) {
    final stations = graph.stations.values.toList();
    if (stations.isEmpty) {
      return const TriviaQuestion(
        prompt: 'No stations loaded',
        options: ['Retry'],
        correctIndex: 0,
        kind: 'station_identify',
        explanation: '',
      );
    }
    // ~50/50 mix of station-identify and route-knowledge questions.
    if (_rng.nextBool() && stations.length >= 2) {
      return _routeKnowledge(graph, stations);
    }
    return _stationIdentify(stations);
  }

  TriviaQuestion _stationIdentify(List<TransitStation> stations) {
    final station = stations[_rng.nextInt(stations.length)];
    final correctLine = normalizeRouteId(station.line);
    final distractors = _allLineIds
        .where((id) => id != correctLine)
        .toList()
      ..shuffle(_rng);
    final options = [correctLine, distractors[0], distractors[1]]
      ..shuffle(_rng);
    final correctIndex = options.indexOf(correctLine);
    return TriviaQuestion(
      prompt: 'Which line serves ${station.name}?',
      options: options.map(lineDisplayName).toList(),
      correctIndex: correctIndex,
      kind: 'station_identify',
      stationId: station.id,
      explanation: '${station.name} is on the ${lineDisplayName(correctLine)}.',
    );
  }

  TriviaQuestion _routeKnowledge(
      TransitGraph graph, List<TransitStation> stations) {
    final a = stations[_rng.nextInt(stations.length)];
    final b = stations[_rng.nextInt(stations.length)];
    final path = graph.findShortestPath(a.id, b.id);
    if (path == null) return _stationIdentify(stations);
    final transfers = path.transferCount;
    final options = <int>{0, 1, 2, 3, 4}
      ..add(transfers)
      ..removeWhere((v) => false);
    final optionsList = options.toList()..shuffle(_rng);
    final unique = optionsList.take(4).toList();
    final correctIndex = unique.indexOf(transfers);
    return TriviaQuestion(
      prompt: 'How many transfers between ${a.name} and ${b.name}?',
      options: unique
          .map((v) => v == 0 ? 'Direct (0)' : '$v transfer${v == 1 ? '' : 's'}')
          .toList(),
      correctIndex: correctIndex,
      kind: 'route_knowledge',
      explanation: transfers == 0
          ? '${a.name} and ${b.name} are connected directly.'
          : 'The shortest route needs $transfers transfer${transfers == 1 ? '' : 's'}.',
    );
  }
}
