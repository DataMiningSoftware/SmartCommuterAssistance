import 'dart:convert';
import 'package:flutter/services.dart';

class MapStation {
  final String stationId;
  final String name;
  final double x;
  final double y;
  final List<String> lines;

  const MapStation({
    required this.stationId,
    required this.name,
    required this.x,
    required this.y,
    required this.lines,
  });

  Map<String, dynamic> toJson() => {
        'station_id': stationId,
        'name': name,
        'x': x,
        'y': y,
        'lines': lines,
      };

  factory MapStation.fromJson(Map<String, dynamic> json) => MapStation(
        stationId: json['station_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0.0,
        y: (json['y'] as num?)?.toDouble() ?? 0.0,
        lines: (json['lines'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );
}

class MapStationData {
  static List<MapStation>? _cached;

  static Future<List<MapStation>> load() async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString('assets/data/map_stations.json');
    final list = (jsonDecode(raw) as List<dynamic>)
        .map((e) => MapStation.fromJson(e as Map<String, dynamic>))
        .toList();
    _cached = list;
    return list;
  }
}
