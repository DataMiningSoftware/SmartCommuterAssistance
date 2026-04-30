import '../constants/crowd_levels.dart';

class TrainPrediction {
  final String trainId;
  final String line;
  final String station;
  final String destination;
  final DateTime arrivalTime;
  final int delayMinutes;
  final String crowdLevel;
  final double confidence;

  TrainPrediction({
    required this.trainId,
    required this.line,
    required this.station,
    required this.destination,
    required this.arrivalTime,
    this.delayMinutes = 0,
    required this.crowdLevel,
    this.confidence = 0.95,
  });

  // Convert from JSON (for API responses)
  factory TrainPrediction.fromJson(Map<String, dynamic> json) {
    return TrainPrediction(
      trainId: json['trainId'] ?? '',
      line: json['line'] ?? '',
      station: json['station'] ?? '',
      destination: json['destination'] ?? '',
      arrivalTime: DateTime.parse(json['arrivalTime']),
      delayMinutes: json['delayMinutes'] ?? 0,
      crowdLevel: json['crowdLevel'] ?? 'Moderate',
      confidence: (json['confidence'] ?? 0.95).toDouble(),
    );
  }

  // Convert to JSON (for API requests)
  Map<String, dynamic> toJson() {
    return {
      'trainId': trainId,
      'line': line,
      'station': station,
      'destination': destination,
      'arrivalTime': arrivalTime.toIso8601String(),
      'delayMinutes': delayMinutes,
      'crowdLevel': crowdLevel,
      'confidence': confidence,
    };
  }

  // Get formatted arrival time string
  String get formattedArrivalTime {
    final now = DateTime.now();
    final difference = arrivalTime.difference(now);

    if (difference.inMinutes <= 0) {
      return 'Arriving now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} min';
    } else {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    }
  }

  // Check if train is delayed
  bool get isDelayed => delayMinutes > 0;

  // Get crowd level color
  String get crowdLevelColor {
    final color = crowdLevelStyleFromLabel(crowdLevel).color;
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }

  @override
  String toString() {
    return 'TrainPrediction(trainId: $trainId, station: $station, arrivalTime: $formattedArrivalTime, crowdLevel: $crowdLevel)';
  }

  // Create a copy with modified values
  TrainPrediction copyWith({
    String? trainId,
    String? line,
    String? station,
    String? destination,
    DateTime? arrivalTime,
    int? delayMinutes,
    String? crowdLevel,
    double? confidence,
  }) {
    return TrainPrediction(
      trainId: trainId ?? this.trainId,
      line: line ?? this.line,
      station: station ?? this.station,
      destination: destination ?? this.destination,
      arrivalTime: arrivalTime ?? this.arrivalTime,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      crowdLevel: crowdLevel ?? this.crowdLevel,
      confidence: confidence ?? this.confidence,
    );
  }
}
