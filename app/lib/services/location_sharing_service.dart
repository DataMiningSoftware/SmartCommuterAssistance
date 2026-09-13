import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';

import 'crowd_reports_service.dart';
import 'race_service.dart';
import 'social_service.dart';
import 'transit_network_service.dart';

/// Foreground-only, station-level location sharing for parties & races.
///
/// Deliberately avoids background location and raw-GPS pushes: it polls a
/// one-shot position, snaps to the nearest known station, and only writes
/// when the nearest station *changes* (backing off when stationary). This is
/// the battery-friendly core of the social features.
class LocationSharingService {
  static final LocationSharingService instance = LocationSharingService._();
  LocationSharingService._();

  static const Duration _moveInterval = Duration(seconds: 5);
  static const Duration _stationaryInterval = Duration(seconds: 20);
  static const int _stationaryThreshold = 3;

  final SocialService _social = SocialService.instance;
  final RaceService _race = RaceService.instance;

  Timer? _timer;
  bool _running = false;
  String? _lastSharedStationId;
  String? _lastCheckpointStationId;
  int _nextCheckpointSeq = 1;
  int _stationaryTicks = 0;

  void start() {
    if (_running) return;
    _running = true;
    _social.currentParty.addListener(_evaluate);
    _evaluate();
  }

  void _evaluate() {
    final party = _social.currentParty.value;
    final active = party != null && (party.isOpen || party.isActive);
    if (active && _timer == null) {
      _stationaryTicks = 0;
      _timer = Timer.periodic(_moveInterval, (_) => _tick());
      _tick();
    } else if (!active && _timer != null) {
      _timer?.cancel();
      _timer = null;
      _lastSharedStationId = null;
      _lastCheckpointStationId = null;
      _nextCheckpointSeq = 1;
      _stationaryTicks = 0;
    }
  }

  Future<void> _tick() async {
    final position = await _currentPosition();
    if (position == null) return;
    final network = await TransitNetworkService().loadNetwork();
    final nearest =
        _nearestStation(position.latitude, position.longitude, network.stopsById.values);
    if (nearest == null) return;
    final stationId = nearest.stopId;

    final party = _social.currentParty.value;
    final race = _race.currentRace.value;

    if (party == null && race == null) return;

    final moved = stationId != _lastSharedStationId;
    if (moved) {
      _stationaryTicks = 0;
      if (_timer != null) _reschedule(_moveInterval);
    } else {
      _stationaryTicks++;
      if (_stationaryTicks == _stationaryThreshold && _timer != null) {
        _reschedule(_stationaryInterval);
      }
    }

    if (party != null && stationId != _lastSharedStationId) {
      _lastSharedStationId = stationId;
      await _social.setLocation(party.id, stationId);
    }

    if (race != null && race.status == 'active' && stationId != _lastCheckpointStationId) {
      _lastCheckpointStationId = stationId;
      final crowdLevel = await _crowdAt(stationId);
      await _race.submitCheckpoint(
        raceId: race.id,
        stationId: stationId,
        seq: _nextCheckpointSeq++,
        crowdLevel: crowdLevel,
      );
    }
  }

  Future<int?> _crowdAt(String stationId) async {
    final report = await CrowdReportsService().fetchLatestCrowdReport(stationId);
    return report?.occupancyLevel;
  }

  void _reschedule(Duration interval) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  Future<Position?> _currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
    } catch (_) {
      return null;
    }
  }

  TransitStop? _nearestStation(
    double latitude,
    double longitude,
    Iterable<TransitStop> stops,
  ) {
    TransitStop? best;
    var bestDistance = double.infinity;
    for (final stop in stops) {
      final distance = _haversineMeters(
        latitude,
        longitude,
        stop.latitude,
        stop.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = stop;
      }
    }
    return best;
  }

  double _haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRadians(double degree) => degree * (pi / 180.0);
}
