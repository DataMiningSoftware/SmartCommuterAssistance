import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_config_service.dart';

class ScheduledTrainArrival {
  final String stopId;
  final String stopName;
  final String routeId;
  final String routeShortName;
  final String routeLongName;
  final String destination;
  final DateTime arrivalTime;
  final int minutesUntil;
  final String source;

  const ScheduledTrainArrival({
    required this.stopId,
    required this.stopName,
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.destination,
    required this.arrivalTime,
    required this.minutesUntil,
    required this.source,
  });

  factory ScheduledTrainArrival.fromJson(Map<String, dynamic> json) {
    return ScheduledTrainArrival(
      stopId: json['stopId']?.toString() ?? '',
      stopName: json['stopName']?.toString() ?? '',
      routeId: json['routeId']?.toString() ?? '',
      routeShortName: json['routeShortName']?.toString() ?? '',
      routeLongName: json['routeLongName']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      arrivalTime: DateTime.tryParse(json['arrivalTime']?.toString() ?? '') ??
          DateTime.now(),
      minutesUntil: _toInt(json['minutesUntil']),
      source: json['source']?.toString() ?? 'gtfs_static_schedule',
    );
  }

  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class StationArrivalResult {
  final String stopId;
  final String stopName;
  final DateTime? generatedAt;
  final List<ScheduledTrainArrival> arrivals;

  const StationArrivalResult({
    required this.stopId,
    required this.stopName,
    required this.generatedAt,
    required this.arrivals,
  });

  factory StationArrivalResult.fromJson(Map<String, dynamic> json) {
    final arrivalsJson = json['arrivals'];
    return StationArrivalResult(
      stopId: json['stopId']?.toString() ?? '',
      stopName: json['stopName']?.toString() ?? '',
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      arrivals: arrivalsJson is List
          ? arrivalsJson
              .whereType<Map>()
              .map(
                (item) => ScheduledTrainArrival.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
          : const <ScheduledTrainArrival>[],
    );
  }
}

class TrainArrivalService {
  final BackendConfigService _backendConfigService = BackendConfigService();
  final http.Client _client;

  TrainArrivalService({
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<StationArrivalResult> fetchStationArrivals(
    String stopId, {
    int limit = 4,
  }) async {
    final baseUrl = _backendConfigService.baseUrl.value.replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final uri = Uri.parse('$baseUrl/arrivals/station/$stopId')
        .replace(queryParameters: <String, String>{
      'limit': '$limit',
    });

    final response = await _client.get(uri).timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Arrivals API returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Arrivals API response format invalid');
    }
    return StationArrivalResult.fromJson(body);
  }
}
