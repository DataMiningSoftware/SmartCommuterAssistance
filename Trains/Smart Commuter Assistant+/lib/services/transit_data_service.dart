import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/transit_graph.dart';

class TransitDataService {
  TransitDataService._();

  static final TransitDataService instance = TransitDataService._();

  TransitGraph? _graph;

  Future<TransitGraph> load() async {
    if (_graph != null) return _graph!;

    final raw = await rootBundle.loadString('assets/data/transit_network.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    _graph = TransitGraph.fromJson(json);
    return _graph!;
  }
}
