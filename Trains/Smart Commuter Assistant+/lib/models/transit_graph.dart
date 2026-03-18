class TransitStationNode {
  final String id;
  final String name;
  final String line;
  final double latitude;
  final double longitude;
  final double mapX;
  final double mapY;

  const TransitStationNode({
    required this.id,
    required this.name,
    required this.line,
    required this.latitude,
    required this.longitude,
    required this.mapX,
    required this.mapY,
  });
}

class TransitEdge {
  final String id;
  final String fromId;
  final String toId;
  final String line;
  final int travelMinutes;
  final double distanceKm;
  final bool isTransfer;

  const TransitEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.line,
    required this.travelMinutes,
    required this.distanceKm,
    this.isTransfer = false,
  });
}

class TransitPath {
  final List<String> stationIds;
  final List<TransitEdge> edges;

  const TransitPath({
    required this.stationIds,
    required this.edges,
  });

  int get totalMinutes => edges.fold<int>(0, (sum, edge) => sum + edge.travelMinutes);

  double get totalDistanceKm => edges.fold<double>(0, (sum, edge) => sum + edge.distanceKm);

  int get transferCount => edges.where((edge) => edge.isTransfer).length;
}

class TransitGraph {
  final Map<String, TransitStationNode> stationsById;
  final List<TransitEdge> edges;
  final Map<String, List<TransitEdge>> _adjacency;
  final List<List<String>> lineCorridors;

  TransitGraph({
    required this.stationsById,
    required this.edges,
    required this.lineCorridors,
  }) : _adjacency = _buildAdjacency(stationsById, edges);

  List<TransitStationNode> get stations => stationsById.values.toList();

  List<String> get stationIds => stationsById.keys.toList();

  TransitStationNode? station(String id) => stationsById[id];

  List<TransitEdge> neighbors(String stationId) => _adjacency[stationId] ?? const <TransitEdge>[];

  List<TransitPath> enumerateCandidatePaths(
    String originId,
    String destinationId, {
    int maxPaths = 4,
    int maxDepth = 8,
  }) {
    if (!stationsById.containsKey(originId) || !stationsById.containsKey(destinationId)) {
      return const <TransitPath>[];
    }
    if (originId == destinationId) {
      return [const TransitPath(stationIds: <String>[], edges: <TransitEdge>[])];
    }

    final paths = <TransitPath>[];
    _dfsEnumerate(
      currentId: originId,
      destinationId: destinationId,
      visited: <String>{originId},
      stationPath: <String>[originId],
      edgePath: <TransitEdge>[],
      maxDepth: maxDepth,
      output: paths,
    );

    paths.sort((a, b) {
      final scoreA = a.totalMinutes + (a.transferCount * 4);
      final scoreB = b.totalMinutes + (b.transferCount * 4);
      return scoreA.compareTo(scoreB);
    });

    final unique = <String>{};
    final selected = <TransitPath>[];
    for (final path in paths) {
      final key = path.stationIds.join('>');
      if (unique.add(key)) {
        selected.add(path);
      }
      if (selected.length >= maxPaths) break;
    }
    return selected;
  }

  void _dfsEnumerate({
    required String currentId,
    required String destinationId,
    required Set<String> visited,
    required List<String> stationPath,
    required List<TransitEdge> edgePath,
    required int maxDepth,
    required List<TransitPath> output,
  }) {
    if (stationPath.length > maxDepth) return;
    if (currentId == destinationId) {
      output.add(TransitPath(
        stationIds: List<String>.from(stationPath),
        edges: List<TransitEdge>.from(edgePath),
      ));
      return;
    }

    for (final edge in neighbors(currentId)) {
      if (visited.contains(edge.toId)) continue;

      visited.add(edge.toId);
      stationPath.add(edge.toId);
      edgePath.add(edge);

      _dfsEnumerate(
        currentId: edge.toId,
        destinationId: destinationId,
        visited: visited,
        stationPath: stationPath,
        edgePath: edgePath,
        maxDepth: maxDepth,
        output: output,
      );

      edgePath.removeLast();
      stationPath.removeLast();
      visited.remove(edge.toId);
    }
  }

  static TransitGraph klangValleyDemo() {
    final stations = <String, TransitStationNode>{
      'Batu Caves': const TransitStationNode(
        id: 'Batu Caves',
        name: 'Batu Caves',
        line: 'KTM Seremban',
        latitude: 3.2379,
        longitude: 101.6840,
        mapX: 0.54,
        mapY: 0.19,
      ),
      'Titiwangsa': const TransitStationNode(
        id: 'Titiwangsa',
        name: 'Titiwangsa',
        line: 'LRT Ampang/Sri Petaling',
        latitude: 3.1748,
        longitude: 101.6959,
        mapX: 0.57,
        mapY: 0.34,
      ),
      'KL Sentral': const TransitStationNode(
        id: 'KL Sentral',
        name: 'KL Sentral',
        line: 'LRT Kelana Jaya',
        latitude: 3.1346,
        longitude: 101.6860,
        mapX: 0.50,
        mapY: 0.52,
      ),
      'Pasar Seni': const TransitStationNode(
        id: 'Pasar Seni',
        name: 'Pasar Seni',
        line: 'MRT Kajang',
        latitude: 3.1427,
        longitude: 101.6951,
        mapX: 0.56,
        mapY: 0.52,
      ),
      'Masjid Jamek': const TransitStationNode(
        id: 'Masjid Jamek',
        name: 'Masjid Jamek',
        line: 'LRT Kelana Jaya',
        latitude: 3.1493,
        longitude: 101.6968,
        mapX: 0.59,
        mapY: 0.44,
      ),
      'KLCC': const TransitStationNode(
        id: 'KLCC',
        name: 'KLCC',
        line: 'LRT Kelana Jaya',
        latitude: 3.1579,
        longitude: 101.7123,
        mapX: 0.68,
        mapY: 0.35,
      ),
      'Bukit Bintang': const TransitStationNode(
        id: 'Bukit Bintang',
        name: 'Bukit Bintang',
        line: 'MRT Kajang',
        latitude: 3.1467,
        longitude: 101.7113,
        mapX: 0.65,
        mapY: 0.41,
      ),
      'Merdeka': const TransitStationNode(
        id: 'Merdeka',
        name: 'Merdeka',
        line: 'MRT Kajang',
        latitude: 3.1422,
        longitude: 101.7035,
        mapX: 0.61,
        mapY: 0.47,
      ),
      'Kajang': const TransitStationNode(
        id: 'Kajang',
        name: 'Kajang',
        line: 'MRT Kajang',
        latitude: 2.9927,
        longitude: 101.7909,
        mapX: 0.84,
        mapY: 0.69,
      ),
    };

    final directed = <TransitEdge>[
      const TransitEdge(
        id: 'E0',
        fromId: 'KL Sentral',
        toId: 'Batu Caves',
        line: 'KTM Seremban',
        travelMinutes: 14,
        distanceKm: 12.7,
      ),
      const TransitEdge(
        id: 'E1',
        fromId: 'Batu Caves',
        toId: 'Titiwangsa',
        line: 'KTM Seremban',
        travelMinutes: 9,
        distanceKm: 8.0,
      ),
      const TransitEdge(
        id: 'E2',
        fromId: 'Titiwangsa',
        toId: 'KL Sentral',
        line: 'LRT Kelana Jaya',
        travelMinutes: 10,
        distanceKm: 5.8,
      ),
      const TransitEdge(
        id: 'E3',
        fromId: 'KL Sentral',
        toId: 'Pasar Seni',
        line: 'MRT Kajang',
        travelMinutes: 5,
        distanceKm: 1.4,
      ),
      const TransitEdge(
        id: 'E4',
        fromId: 'Pasar Seni',
        toId: 'Merdeka',
        line: 'MRT Kajang',
        travelMinutes: 3,
        distanceKm: 1.0,
      ),
      const TransitEdge(
        id: 'E5',
        fromId: 'Merdeka',
        toId: 'Bukit Bintang',
        line: 'MRT Kajang',
        travelMinutes: 4,
        distanceKm: 1.2,
      ),
      const TransitEdge(
        id: 'E6',
        fromId: 'Bukit Bintang',
        toId: 'KLCC',
        line: 'MRT Kajang',
        travelMinutes: 4,
        distanceKm: 1.3,
      ),
      const TransitEdge(
        id: 'E7',
        fromId: 'Merdeka',
        toId: 'Kajang',
        line: 'MRT Kajang',
        travelMinutes: 19,
        distanceKm: 21.6,
      ),
      const TransitEdge(
        id: 'E8',
        fromId: 'KL Sentral',
        toId: 'Masjid Jamek',
        line: 'LRT Kelana Jaya',
        travelMinutes: 7,
        distanceKm: 2.6,
      ),
      const TransitEdge(
        id: 'E9',
        fromId: 'Masjid Jamek',
        toId: 'KLCC',
        line: 'LRT Kelana Jaya',
        travelMinutes: 6,
        distanceKm: 2.5,
      ),
      const TransitEdge(
        id: 'E10',
        fromId: 'Masjid Jamek',
        toId: 'Pasar Seni',
        line: 'Interchange',
        travelMinutes: 3,
        distanceKm: 0.35,
        isTransfer: true,
      ),
    ];

    final edges = <TransitEdge>[
      ...directed,
      ...directed.map((edge) => TransitEdge(
            id: '${edge.id}R',
            fromId: edge.toId,
            toId: edge.fromId,
            line: edge.line,
            travelMinutes: edge.travelMinutes,
            distanceKm: edge.distanceKm,
            isTransfer: edge.isTransfer,
          )),
    ];

    return TransitGraph(
      stationsById: stations,
      edges: edges,
      lineCorridors: const <List<String>>[
        <String>['Batu Caves', 'Titiwangsa', 'KL Sentral', 'Masjid Jamek', 'KLCC'],
        <String>['KL Sentral', 'Pasar Seni', 'Merdeka', 'Bukit Bintang', 'KLCC'],
        <String>['Merdeka', 'Kajang'],
      ],
    );
  }

  static Map<String, List<TransitEdge>> _buildAdjacency(
    Map<String, TransitStationNode> stations,
    List<TransitEdge> edges,
  ) {
    final adjacency = <String, List<TransitEdge>>{
      for (final id in stations.keys) id: <TransitEdge>[],
    };
    for (final edge in edges) {
      adjacency[edge.fromId]!.add(edge);
    }
    return adjacency;
  }
}
