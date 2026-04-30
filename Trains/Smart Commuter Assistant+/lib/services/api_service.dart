import 'dart:math';

import '../models/train_prediction.dart';
import '../models/route_info.dart';

class ApiService {
  static const String baseUrl = 'https://api.smartcommuter.my'; // Mock API URL

  // Singleton pattern
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  // Mock data for development
  final List<String> _stations = [
    'KL Sentral',
    'KLCC',
    'Bukit Bintang',
    'Pasar Seni',
    'Masjid Jamek',
    'Dang Wangi',
    'Ampang Park',
    'Titiwangsa',
    'Sentul',
    'Batu Caves',
  ];

  final List<String> _trainLines = [
    'Kelana Jaya Line',
    'Ampang Line',
    'Sri Petaling Line',
    'KTM Komuter',
    'MRT Kajang Line',
  ];

  static const List<String> _crowdLevels = <String>[
    'Empty',
    'Light',
    'Moderate',
    'Heavy',
    'Crowded',
  ];

  // Get train forecasts for a station
  Future<List<TrainPrediction>> getTrainPredictions(String stationName) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Generate mock forecasts
    final predictions = <TrainPrediction>[];
    final random = Random();

    for (int i = 0; i < 4; i++) {
      predictions.add(TrainPrediction(
        trainId: 'T${random.nextInt(999).toString().padLeft(3, '0')}',
        line: _trainLines[random.nextInt(_trainLines.length)],
        station: stationName,
        destination: _stations[random.nextInt(_stations.length)],
        arrivalTime:
            DateTime.now().add(Duration(minutes: random.nextInt(30) + 1)),
        delayMinutes: random.nextBool() ? random.nextInt(5) : 0,
        crowdLevel: _crowdLevels[random.nextInt(_crowdLevels.length)],
        confidence: 0.85 + random.nextDouble() * 0.15,
      ));
    }

    return predictions;
  }

  // Get route information between two stations
  Future<List<RouteInfo>> getRoutes(String origin, String destination) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 800));

    final routes = <RouteInfo>[];
    final random = Random();

    // Generate 2-3 route options
    for (int i = 0; i < 2 + random.nextInt(2); i++) {
      final steps = <RouteStep>[];

      // Add some route steps
      if (random.nextBool()) {
        steps.add(RouteStep(
          type: RouteStepType.train,
          line: _trainLines[random.nextInt(_trainLines.length)],
          station: origin,
          durationMinutes: 5 + random.nextInt(10),
          instruction: 'Board train at $origin',
        ));

        steps.add(RouteStep(
          type: RouteStepType.transfer,
          line: _trainLines[random.nextInt(_trainLines.length)],
          station: _stations[random.nextInt(_stations.length)],
          durationMinutes: 2 + random.nextInt(3),
          instruction: 'Transfer at interchange',
        ));
      }

      routes.add(RouteInfo(
        routeId: 'R${i + 1}',
        origin: origin,
        destination: destination,
        steps: steps,
        totalDurationMinutes: 15 + random.nextInt(30),
        totalDistance: 5.0 + random.nextDouble() * 15.0,
        crowdLevel: _crowdLevels[random.nextInt(_crowdLevels.length)],
        fare: 2.0 + random.nextDouble() * 4.0,
      ));
    }

    return routes;
  }

  // Get nearby stations based on location
  Future<List<String>> getNearbyStations({double? lat, double? lng}) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 300));

    // Return mock nearby stations
    final random = Random();
    final nearbyStations = <String>[];

    for (int i = 0; i < 5; i++) {
      nearbyStations.add(_stations[random.nextInt(_stations.length)]);
    }

    return nearbyStations.toSet().toList(); // Remove duplicates
  }

  // Get crowd forecasts for a station
  Future<Map<String, String>> getCrowdPredictions(String stationName) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 400));

    final random = Random();
    return {
      'current': _crowdLevels[random.nextInt(_crowdLevels.length)],
      'nextHour': _crowdLevels[random.nextInt(_crowdLevels.length)],
      'peakTime':
          '${8 + random.nextInt(4)}:${random.nextInt(60).toString().padLeft(2, '0')} AM',
    };
  }

  // Search stations by name
  Future<List<String>> searchStations(String query) async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 200));

    if (query.isEmpty) return _stations.take(5).toList();

    return _stations
        .where((station) => station.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  // Get service announcements
  Future<List<Map<String, dynamic>>> getServiceAnnouncements() async {
    // Simulate API delay
    await Future.delayed(const Duration(milliseconds: 300));

    return [
      {
        'id': '1',
        'title': 'Scheduled Maintenance',
        'message': 'KTM Komuter service will be affected on Sunday 2-4 AM',
        'type': 'maintenance',
        'timestamp':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      },
      {
        'id': '2',
        'title': 'New Route Available',
        'message': 'Direct service from KLCC to Bukit Bintang now available',
        'type': 'info',
        'timestamp':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      },
    ];
  }
}
