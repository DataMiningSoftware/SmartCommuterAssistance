class RouteInfo {
  final String routeId;
  final String origin;
  final String destination;
  final List<RouteStep> steps;
  final int totalDurationMinutes;
  final double totalDistance;
  final String crowdLevel;
  final double fare;
  final bool isFavorite;

  RouteInfo({
    required this.routeId,
    required this.origin,
    required this.destination,
    required this.steps,
    required this.totalDurationMinutes,
    required this.totalDistance,
    required this.crowdLevel,
    required this.fare,
    this.isFavorite = false,
  });

  // Convert from JSON
  factory RouteInfo.fromJson(Map<String, dynamic> json) {
    return RouteInfo(
      routeId: json['routeId'] ?? '',
      origin: json['origin'] ?? '',
      destination: json['destination'] ?? '',
      steps: (json['steps'] as List<dynamic>?)
          ?.map((step) => RouteStep.fromJson(step))
          .toList() ?? [],
      totalDurationMinutes: json['totalDurationMinutes'] ?? 0,
      totalDistance: (json['totalDistance'] ?? 0.0).toDouble(),
      crowdLevel: json['crowdLevel'] ?? 'Medium',
      fare: (json['fare'] ?? 0.0).toDouble(),
      isFavorite: json['isFavorite'] ?? false,
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'routeId': routeId,
      'origin': origin,
      'destination': destination,
      'steps': steps.map((step) => step.toJson()).toList(),
      'totalDurationMinutes': totalDurationMinutes,
      'totalDistance': totalDistance,
      'crowdLevel': crowdLevel,
      'fare': fare,
      'isFavorite': isFavorite,
    };
  }

  // Get formatted duration
  String get formattedDuration {
    if (totalDurationMinutes < 60) {
      return '$totalDurationMinutes min';
    } else {
      final hours = totalDurationMinutes ~/ 60;
      final minutes = totalDurationMinutes % 60;
      return '${hours}h ${minutes}m';
    }
  }

  // Get formatted fare
  String get formattedFare {
    return 'RM ${fare.toStringAsFixed(2)}';
  }

  // Get route summary
  String get routeSummary {
    if (steps.isEmpty) return '$origin → $destination';
    
    final stationNames = [origin];
    for (final step in steps) {
      if (step.type == RouteStepType.transfer) {
        stationNames.add(step.station);
      }
    }
    stationNames.add(destination);
    
    return stationNames.join(' → ');
  }

  // Create a copy with modified values
  RouteInfo copyWith({
    String? routeId,
    String? origin,
    String? destination,
    List<RouteStep>? steps,
    int? totalDurationMinutes,
    double? totalDistance,
    String? crowdLevel,
    double? fare,
    bool? isFavorite,
  }) {
    return RouteInfo(
      routeId: routeId ?? this.routeId,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      steps: steps ?? this.steps,
      totalDurationMinutes: totalDurationMinutes ?? this.totalDurationMinutes,
      totalDistance: totalDistance ?? this.totalDistance,
      crowdLevel: crowdLevel ?? this.crowdLevel,
      fare: fare ?? this.fare,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class RouteStep {
  final RouteStepType type;
  final String line;
  final String station;
  final int durationMinutes;
  final String instruction;

  RouteStep({
    required this.type,
    required this.line,
    required this.station,
    required this.durationMinutes,
    required this.instruction,
  });

  // Convert from JSON
  factory RouteStep.fromJson(Map<String, dynamic> json) {
    return RouteStep(
      type: RouteStepType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => RouteStepType.train,
      ),
      line: json['line'] ?? '',
      station: json['station'] ?? '',
      durationMinutes: json['durationMinutes'] ?? 0,
      instruction: json['instruction'] ?? '',
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'type': type.toString().split('.').last,
      'line': line,
      'station': station,
      'durationMinutes': durationMinutes,
      'instruction': instruction,
    };
  }

  // Get formatted duration
  String get formattedDuration {
    return '$durationMinutes min';
  }
}

enum RouteStepType {
  train,
  walk,
  transfer,
  wait,
}