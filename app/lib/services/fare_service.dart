import 'dart:math';

import '../models/transit_graph.dart';

class FareSegmentInput {
  final String line;
  final String fromStopId;
  final String toStopId;
  final double distanceKm;

  const FareSegmentInput({
    required this.line,
    required this.fromStopId,
    required this.toStopId,
    required this.distanceKm,
  });
}

class FareLeg {
  final String line;
  final String fromStopId;
  final String toStopId;
  final double distanceKm;
  final double fare;
  final bool separateTicket;

  const FareLeg({
    required this.line,
    required this.fromStopId,
    required this.toStopId,
    required this.distanceKm,
    required this.fare,
    required this.separateTicket,
  });
}

class FareBreakdown {
  final List<FareLeg> legs;
  final double total;
  final int ticketCount;

  const FareBreakdown({
    required this.legs,
    required this.total,
    required this.ticketCount,
  });

  static const empty = FareBreakdown(
    legs: <FareLeg>[],
    total: 0,
    ticketCount: 0,
  );

  bool get isEmpty => legs.isEmpty;

  bool get hasSeparateTickets => ticketCount > 1;

  double get separateTicketTotal => legs
      .where((leg) => leg.separateTicket)
      .fold<double>(0, (sum, leg) => sum + leg.fare);

  FareLeg? legFor(String line, String fromStopId, String toStopId) {
    final targetLine = FareService._normalizedLine(line);
    final target = '${fromStopId.trim().toUpperCase()}|${toStopId.trim().toUpperCase()}';
    for (final leg in legs) {
      if (FareService._normalizedLine(leg.line) != targetLine) continue;
      final key = '${leg.fromStopId.trim().toUpperCase()}|${leg.toStopId.trim().toUpperCase()}';
      if (key == target) return leg;
    }
    return null;
  }
}

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
  static const double _minFare = 1.4;
  static const double _maxFare = 8.0;

  static FareBreakdown forSegments(List<FareSegmentInput> segments) {
    if (segments.isEmpty) return FareBreakdown.empty;

    final erlFaresByIndex = <int, double>{};
    final rapidIndices = <int>[];
    var rapidDistance = 0.0;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (_isErl(segment.line)) {
        erlFaresByIndex[i] = _erlLookup(
              segment.line,
              segment.fromStopId,
              segment.toStopId,
            ) ??
            _estimate(segment.distanceKm);
        continue;
      }
      rapidIndices.add(i);
      rapidDistance += segment.distanceKm;
    }

    final rapidFare =
        rapidIndices.isEmpty ? 0.0 : _estimate(rapidDistance);
    final allocated = List<double>.filled(segments.length, 0);

    var running = 0.0;
    for (final index in rapidIndices) {
      final share = rapidDistance <= 0
          ? rapidFare / rapidIndices.length
          : rapidFare * (segments[index].distanceKm / rapidDistance);
      final rounded = _round(share);
      allocated[index] = rounded;
      running += rounded;
    }

    final drift = _round(rapidFare - running);
    if (rapidIndices.isNotEmpty && drift != 0) {
      final target = rapidIndices.reduce(
        (a, b) => segments[a].distanceKm >= segments[b].distanceKm ? a : b,
      );
      allocated[target] = _round(allocated[target] + drift);
    }

    final legs = <FareLeg>[];
    var total = 0.0;
    var erlLegCount = 0;
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isErl = _isErl(segment.line);
      final fare = isErl ? erlFaresByIndex[i]! : allocated[i];
      if (isErl) erlLegCount += 1;
      total += fare;
      legs.add(
        FareLeg(
          line: segment.line,
          fromStopId: segment.fromStopId,
          toStopId: segment.toStopId,
          distanceKm: segment.distanceKm,
          fare: _round(fare),
          separateTicket: isErl,
        ),
      );
    }

    final ticketCount = (rapidIndices.isEmpty ? 0 : 1) + erlLegCount;

    return FareBreakdown(
      legs: legs,
      total: _round(total),
      ticketCount: ticketCount,
    );
  }

  static FareBreakdown breakdownForPath(TransitPath path, TransitGraph graph) {
    final edges = path.edges;
    if (edges.isEmpty) return FareBreakdown.empty;

    final segments = <FareSegmentInput>[];
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
      segments.add(
        FareSegmentInput(
          line: edge.line,
          fromStopId: edges[index].from,
          toStopId: edges[end].to,
          distanceKm: distance,
        ),
      );
      index = end + 1;
    }

    return forSegments(segments);
  }

  static double fareForPath(TransitPath path, TransitGraph graph) {
    return breakdownForPath(path, graph).total;
  }

  static String _normalizedLine(String line) => line.trim().toUpperCase();

  static bool _isErl(String line) {
    final id = _normalizedLine(line);
    return id.startsWith('ER6') || id.startsWith('ER7');
  }

  static double? _erlLookup(String line, String from, String to) {
    final table = erlFares[_normalizedLine(line)];
    if (table == null) return null;
    return table['$from|$to'] ?? table['$to|$from'];
  }

  static double _estimate(double distanceKm) {
    final fare = _base + distanceKm * _perKm;
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
