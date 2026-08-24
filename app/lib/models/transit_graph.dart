import '../services/operating_hours_service.dart';

class TransitStation {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double gridX;
  final double gridY;
  final List<String> lines;

  TransitStation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.gridX,
    required this.gridY,
    required this.lines,
  });

  bool get isInterchange => lines.length > 1;
  String get line => lines.isNotEmpty ? lines.first : '';
}

class TransitEdge {
  final String from;
  final String to;
  final String line;
  final String type;
  final int minutes;

  TransitEdge({
    required this.from,
    required this.to,
    required this.line,
    required this.type,
    required this.minutes,
  });

  bool get isInterchange => type != 'standard_stop';
}

class TransitGraph {
  final Map<String, TransitStation> stations = {};
  final Map<String, List<TransitEdge>> adjacency = {};
  final Map<String, List<String>> lineStationOrder = {};

  static const int transferPenalty = 8;

  TransitGraph();

  TransitStation? station(String id) => stations[id];

  Map<String, TransitStation> get stationsById => stations;

  List<TransitPath> enumerateCandidatePaths(String from, String to, {int maxPaths = 3, DateTime? departureTime}) {
    final path = findShortestPath(from, to, departureTime: departureTime);
    if (path == null) return [];
    return [path];
  }

  static TransitGraph klangValleyDemo() => TransitGraph();

  factory TransitGraph.fromJson(Map<String, dynamic> json) {
    final graph = TransitGraph();
    final stationLines = <String, Set<String>>{};
    final lineStations = <String, Set<String>>{};

    for (final s in json['stations'] as List<dynamic>) {
      final station = s as Map<String, dynamic>;
      final id = station['id'] as String;
      final lines = station['lines'] as List<dynamic>;
      for (final line in lines) {
        stationLines.putIfAbsent(id, () => {}).add(line as String);
      }
    }

    for (final entry in stationLines.entries) {
      final id = entry.key;
      final lines = entry.value.toList();
      final s = (json['stations'] as List<dynamic>).firstWhere(
        (s) => (s as Map<String, dynamic>)['id'] == id,
      ) as Map<String, dynamic>;
      graph.stations[id] = TransitStation(
        id: id,
        name: s['name'] as String,
        lat: (s['lat'] as num).toDouble(),
        lng: (s['lng'] as num).toDouble(),
        gridX: (s['gridX'] as num?)?.toDouble() ?? 0,
        gridY: (s['gridY'] as num?)?.toDouble() ?? 0,
        lines: lines,
      );
    }

    for (final s in graph.stations.values) {
      for (final line in s.lines) {
        lineStations.putIfAbsent(line, () => {}).add(s.id);
      }
    }

    for (final entry in lineStations.entries) {
      final sorted = entry.value.toList()
        ..sort((a, b) {
          final sa = graph.stations[a]!;
          final sb = graph.stations[b]!;
          final latComp = sa.lat.compareTo(sb.lat);
          if (latComp != 0) return latComp;
          return sa.lng.compareTo(sb.lng);
        });
      graph.lineStationOrder[entry.key] = sorted;
    }

    for (final c in json['connections'] as List<dynamic>) {
      final conn = c as Map<String, dynamic>;
      final edge = TransitEdge(
        from: conn['from'] as String,
        to: conn['to'] as String,
        line: conn['route'] as String,
        type: conn['type'] as String,
        minutes: (conn['minutes'] as num).toInt(),
      );
      graph.adjacency.putIfAbsent(edge.from, () => []).add(edge);
    }

    return graph;
  }

  TransitPath? findShortestPath(String originId, String destinationId, {DateTime? departureTime}) {
    if (!stations.containsKey(originId) || !stations.containsKey(destinationId)) {
      return null;
    }

    final distances = <String, int>{};
    final previous = <String, _PathNode>{};
    final queue = <_QueueEntry>[_QueueEntry(originId, 0, null)];
    distances[originId] = 0;

    while (queue.isNotEmpty) {
      queue.sort((a, b) => a.cost.compareTo(b.cost));
      final current = queue.removeAt(0);
      final currentId = current.id;
      final currentCost = current.cost;

      if (currentId == destinationId) break;
      if (currentCost > (distances[currentId] ?? 999999)) continue;

      final edges = adjacency[currentId] ?? [];
      for (final edge in edges) {
        if (!stations.containsKey(edge.to)) continue;
        if (!OperatingHoursService.isLineRunning(edge.line, at: departureTime)) continue;
        final nextId = edge.to;
        final prev = previous[currentId];
        final switching = prev != null && prev.line != null && prev.line != edge.line;
        var cost = edge.minutes;
        if (switching) cost += transferPenalty;

        final newCost = currentCost + cost;
        if (newCost < (distances[nextId] ?? 999999)) {
          distances[nextId] = newCost;
          previous[nextId] = _PathNode(currentId, edge.line);
          queue.add(_QueueEntry(nextId, newCost, edge.line));
        }
      }
    }

    if (!previous.containsKey(destinationId)) return null;

    final path = <String>[];
    final edges = <TransitEdge>[];
    final lineJumps = <String>[];
    var cursor = destinationId;
    while (cursor != originId) {
      path.add(cursor);
      cursor = previous[cursor]!.parent;
    }
    path.add(originId);
    final reversedPath = path.reversed.toList();

    String? currentLine;
    for (var i = 0; i < reversedPath.length - 1; i++) {
      final from = reversedPath[i];
      final to = reversedPath[i + 1];
      final edge = (adjacency[from] ?? []).firstWhere(
        (e) => e.to == to,
        orElse: () => TransitEdge(from: from, to: to, line: '', type: '', minutes: 0),
      );
      edges.add(edge);
      if (edge.line != currentLine && edge.line.isNotEmpty && edge.line != 'INTERCHANGE') {
        lineJumps.add(edge.line);
        currentLine = edge.line;
      }
    }

    return TransitPath(
      stationIds: reversedPath,
      edges: edges,
      totalMinutes: distances[destinationId] ?? 0,
      lineJumps: lineJumps,
      transferCount: lineJumps.length - 1,
    );
  }
}

class _PathNode {
  final String parent;
  final String? line;
  _PathNode(this.parent, this.line);
}

class _QueueEntry {
  final String id;
  final int cost;
  final String? line;
  _QueueEntry(this.id, this.cost, this.line);
}

class TransitPath {
  final List<String> stationIds;
  final List<TransitEdge> edges;
  final int totalMinutes;
  final List<String> lineJumps;
  final int transferCount;

  TransitPath({
    required this.stationIds,
    required this.edges,
    required this.totalMinutes,
    required this.lineJumps,
    required this.transferCount,
  });

  List<TransitStation> get stations =>
      stationIds.map((id) => TransitStation(id: id, name: '', lat: 0, lng: 0, gridX: 0, gridY: 0, lines: [])).toList();

  String get summary {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    final time = h > 0 ? '${h}h ${m}min' : '${m}min';
    final transfers = transferCount > 0 ? '$transferCount transfer' : 'Direct';
    return '$time · $transfers';
  }

  // Backward compat
  double get totalDistanceKm => totalMinutes * 0.8;
  bool get isEmpty => stationIds.isEmpty;
}

extension TransitEdgeCompat on TransitEdge {
  String get toId => to;
  bool get isTransfer => isInterchange;
  int get travelMinutes => minutes;
}

typedef TransitStationNode = TransitStation;
