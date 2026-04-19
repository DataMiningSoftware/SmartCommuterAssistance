import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActiveTripStop {
  final String stopId;
  final String stopName;
  final String routeId;

  const ActiveTripStop({
    required this.stopId,
    required this.stopName,
    required this.routeId,
  });

  factory ActiveTripStop.fromJson(Map<String, dynamic> json) {
    return ActiveTripStop(
      stopId: json['stopId']?.toString() ?? '',
      stopName: json['stopName']?.toString() ?? '',
      routeId: json['routeId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'stopId': stopId,
      'stopName': stopName,
      'routeId': routeId,
    };
  }
}

class ActiveTrip {
  final String originStopId;
  final String destinationStopId;
  final String originName;
  final String destinationName;
  final String routePreference;
  final int highestCrowdLevel;
  final DateTime createdAt;
  final List<ActiveTripStop> stops;

  const ActiveTrip({
    required this.originStopId,
    required this.destinationStopId,
    required this.originName,
    required this.destinationName,
    required this.routePreference,
    required this.highestCrowdLevel,
    required this.createdAt,
    required this.stops,
  });

  factory ActiveTrip.fromJson(Map<String, dynamic> json) {
    final rawStops = json['stops'];
    final stops = rawStops is List
        ? rawStops
            .whereType<Map>()
            .map((item) => ActiveTripStop.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList()
        : <ActiveTripStop>[];

    return ActiveTrip(
      originStopId: json['originStopId']?.toString() ?? '',
      destinationStopId: json['destinationStopId']?.toString() ?? '',
      originName: json['originName']?.toString() ?? '',
      destinationName: json['destinationName']?.toString() ?? '',
      routePreference: json['routePreference']?.toString() ?? 'efficiency',
      highestCrowdLevel: json['highestCrowdLevel'] is num
          ? (json['highestCrowdLevel'] as num).toInt()
          : int.tryParse(json['highestCrowdLevel']?.toString() ?? '') ?? 0,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      stops: stops,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'originStopId': originStopId,
      'destinationStopId': destinationStopId,
      'originName': originName,
      'destinationName': destinationName,
      'routePreference': routePreference,
      'highestCrowdLevel': highestCrowdLevel,
      'createdAt': createdAt.toIso8601String(),
      'stops': stops.map((stop) => stop.toJson()).toList(),
    };
  }
}

class ActiveTripService {
  ActiveTripService._();

  static final ActiveTripService instance = ActiveTripService._();
  static const String _storageKey = 'active_trip_v1';

  final ValueNotifier<ActiveTrip?> activeTrip =
      ValueNotifier<ActiveTrip?>(null);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        activeTrip.value = ActiveTrip.fromJson(json);
      } else if (json is Map) {
        activeTrip.value = ActiveTrip.fromJson(Map<String, dynamic>.from(json));
      }
    } catch (_) {
      await prefs.remove(_storageKey);
    }
  }

  Future<void> saveTrip(ActiveTrip trip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(trip.toJson()));
    activeTrip.value = trip;
  }

  Future<void> clearTrip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    activeTrip.value = null;
  }
}
