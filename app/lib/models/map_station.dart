class MapStation {
  final String stationId;
  final String name;
  final double x;
  final double y;
  final List<String> lines;
  final double? latitude;
  final double? longitude;

  const MapStation({
    required this.stationId,
    required this.name,
    required this.x,
    required this.y,
    required this.lines,
    this.latitude,
    this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'station_id': stationId,
        'name': name,
        'x': x,
        'y': y,
        'lines': lines,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
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
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
      );
}
