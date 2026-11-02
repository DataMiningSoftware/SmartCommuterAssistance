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

class TripProgressStop {
  final String stopId;
  final String stopName;
  final String routeId;
  final int stopIndex;

  const TripProgressStop({
    required this.stopId,
    required this.stopName,
    required this.routeId,
    required this.stopIndex,
  });
}

class TripProgressWindow {
  final List<TripProgressStop> all;
  final List<TripProgressStop> visible;
  final int currentIndex;
  final bool hasMore;

  const TripProgressWindow({
    required this.all,
    required this.visible,
    required this.currentIndex,
    required this.hasMore,
  });

  static const empty = TripProgressWindow(
    all: <TripProgressStop>[],
    visible: <TripProgressStop>[],
    currentIndex: 0,
    hasMore: false,
  );

  TripProgressStop? get current =>
      currentIndex >= 0 && currentIndex < all.length ? all[currentIndex] : null;
}

class ActiveTrip {
  final String originStopId;
  final String destinationStopId;
  final String originName;
  final String destinationName;
  final String routePreference;
  final int highestCrowdLevel;
  final DateTime createdAt;
  final int? estimatedTotalMinutes;
  final List<ActiveTripStop> stops;
  final int currentStopIndex;

  const ActiveTrip({
    required this.originStopId,
    required this.destinationStopId,
    required this.originName,
    required this.destinationName,
    required this.routePreference,
    required this.highestCrowdLevel,
    required this.createdAt,
    required this.estimatedTotalMinutes,
    required this.stops,
    this.currentStopIndex = 0,
  });

  ActiveTrip withProgress(int index) {
    return ActiveTrip(
      originStopId: originStopId,
      destinationStopId: destinationStopId,
      originName: originName,
      destinationName: destinationName,
      routePreference: routePreference,
      highestCrowdLevel: highestCrowdLevel,
      createdAt: createdAt,
      estimatedTotalMinutes: estimatedTotalMinutes,
      stops: stops,
      currentStopIndex: index,
    );
  }

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
      estimatedTotalMinutes: json['estimatedTotalMinutes'] is num
          ? (json['estimatedTotalMinutes'] as num).toInt()
          : int.tryParse(json['estimatedTotalMinutes']?.toString() ?? ''),
      stops: stops,
      currentStopIndex: json['currentStopIndex'] is num
          ? (json['currentStopIndex'] as num).toInt()
          : int.tryParse(json['currentStopIndex']?.toString() ?? '') ?? 0,
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
      'estimatedTotalMinutes': estimatedTotalMinutes,
      'stops': stops.map((stop) => stop.toJson()).toList(),
      'currentStopIndex': currentStopIndex,
    };
  }

  DateTime? get estimatedArrivalTime {
    final minutes = estimatedTotalMinutes;
    if (minutes == null) return null;
    return createdAt.add(Duration(minutes: minutes < 0 ? 0 : minutes));
  }
}

class ActiveTripService {
  ActiveTripService._();

  static final ActiveTripService instance = ActiveTripService._();
  static const String _storageKey = 'active_trip_v1';

  final ValueNotifier<ActiveTrip?> activeTrip =
      ValueNotifier<ActiveTrip?>(null);

  final ValueNotifier<int?> pinnedRemainingMinutes = ValueNotifier<int?>(null);
  final ValueNotifier<DateTime?> pinnedArrivalTime = ValueNotifier<DateTime?>(null);

  void pinEta({required int remainingMinutes, required DateTime arrivalTime}) {
    pinnedRemainingMinutes.value = remainingMinutes;
    pinnedArrivalTime.value = arrivalTime;
  }

  void extendPinnedEta(int additionalMinutes) {
    final current = pinnedArrivalTime.value;
    if (current == null) return;
    pinnedArrivalTime.value = current.add(Duration(minutes: additionalMinutes));
    final remaining = pinnedRemainingMinutes.value;
    if (remaining != null) {
      pinnedRemainingMinutes.value = remaining + additionalMinutes;
    }
  }

  void clearPinnedEta() {
    pinnedRemainingMinutes.value = null;
    pinnedArrivalTime.value = null;
  }

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

  Future<void> updateProgress(int index) async {
    final trip = activeTrip.value;
    if (trip == null || trip.stops.isEmpty) return;
    final clamped = index.clamp(0, trip.stops.length - 1).toInt();
    if (clamped <= trip.currentStopIndex) return;
    await saveTrip(trip.withProgress(clamped));
  }
}

String _progressNameKey(String value) {
  return value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
}

List<TripProgressStop> buildTripProgressStops(List<ActiveTripStop> stops) {
  final merged = <TripProgressStop>[];
  for (var i = 0; i < stops.length; i++) {
    final stop = stops[i];
    final name = stop.stopName.trim();
    if (name.isEmpty) continue;
    final key = _progressNameKey(name);
    if (merged.isNotEmpty && _progressNameKey(merged.last.stopName) == key) {
      merged[merged.length - 1] = TripProgressStop(
        stopId: stop.stopId,
        stopName: name,
        routeId: stop.routeId,
        stopIndex: i,
      );
      continue;
    }
    merged.add(
      TripProgressStop(
        stopId: stop.stopId,
        stopName: name,
        routeId: stop.routeId,
        stopIndex: i,
      ),
    );
  }
  return merged;
}

TripProgressWindow buildTripProgressWindow(
  ActiveTrip trip, {
  int ahead = 2,
}) {
  final all = buildTripProgressStops(trip.stops);
  if (all.isEmpty) return TripProgressWindow.empty;

  var current = 0;
  for (var i = 0; i < all.length; i++) {
    if (all[i].stopIndex <= trip.currentStopIndex) {
      current = i;
    } else {
      break;
    }
  }

  final visible = <TripProgressStop>[];
  for (var i = current; i < all.length && visible.length <= ahead; i++) {
    visible.add(all[i]);
  }

  return TripProgressWindow(
    all: all,
    visible: visible,
    currentIndex: current,
    hasMore: current + visible.length < all.length,
  );
}
