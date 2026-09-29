import 'dart:math';

import '../models/transit_graph.dart';

class FareService {
  FareService._();

  static const Map<String, Map<String, double>> erlFares = {
    'ER6': {
      'KJ15|KLIA': 55.0,
      'KJ15|KLIA2': 55.0,
      'KLIA|KLIA2': 2.0,
    },
    'ER7': {
      'KJ15|SP15': 6.5,
      'KJ15|PY41': 14.0,
      'KJ15|SALAK_TINGGI': 18.3,
      'KJ15|KLIA': 55.0,
      'KJ15|KLIA2': 55.0,
      'SP15|PY41': 8.0,
      'SP15|SALAK_TINGGI': 12.4,
      'SP15|KLIA': 38.4,
      'SP15|KLIA2': 38.4,
      'PY41|SALAK_TINGGI': 4.7,
      'PY41|KLIA': 9.4,
      'PY41|KLIA2': 9.4,
      'SALAK_TINGGI|KLIA': 4.9,
      'SALAK_TINGGI|KLIA2': 4.9,
      'KLIA|KLIA2': 2.0,
    },
  };

  static const double _base = 1.4;
  static const double _perKm = 0.13;
  static const double _perTransfer = 0.35;
  static const double _minFare = 1.4;
  static const double _maxFare = 8.0;

  static double fareForPath(TransitPath path, TransitGraph graph) {
    final edges = path.edges;
    if (edges.isEmpty) return 0.0;

    final transferCount = path.transferCount;
    var erlTotal = 0.0;
    var otherDistance = 0.0;
    var index = 0;
    while (index < edges.length) {
      final edge = edges[index];
      if (edge.isTransfer) {
        index += 1;
        continue;
      }
      var end = index;
      while (end + 1 < edges.length &&
          !edges[end + 1].isTransfer &&
          edges[end + 1].line == edge.line) {
        end += 1;
      }
      var distance = 0.0;
      for (var i = index; i <= end; i++) {
        distance += _distanceKm(graph, edges[i].from, edges[i].to);
      }
      final fare = _erlLookup(edge.line, edges[index].from, edges[end].to);
      if (fare != null) {
        erlTotal += fare;
      } else {
        otherDistance += distance;
      }
      index = end + 1;
    }

    if (erlTotal > 0) {
      final estimate = otherDistance > 0
          ? _estimate(otherDistance, transferCount)
          : 0.0;
      return _round(erlTotal + estimate);
    }
    return _estimate(otherDistance, transferCount);
  }

  static double? _erlLookup(String line, String from, String to) {
    final table = erlFares[line];
    if (table == null) return null;
    return table['$from|$to'] ?? table['$to|$from'];
  }

  static double _estimate(double distanceKm, int transferCount) {
    final fare = _base + distanceKm * _perKm + transferCount * _perTransfer;
    return _round(fare.clamp(_minFare, _maxFare).toDouble());
  }

  static double _round(double value) => (value * 100).roundToDouble() / 100;

  static double _distanceKm(TransitGraph graph, String from, String to) {
    final source = graph.station(from);
    final target = graph.station(to);
    if (source == null || target == null) return 0.0;
    return _haversineKm(source.lat, source.lng, target.lat, target.lng);
  }

  static double _haversineKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const radius = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_radians(lat1)) * cos(_radians(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return 2 * radius * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * pi / 180;
}
