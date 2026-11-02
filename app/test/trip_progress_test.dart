import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_commuter/services/active_trip_service.dart';

ActiveTripStop _stop(String id, String name, String routeId) {
  return ActiveTripStop(stopId: id, stopName: name, routeId: routeId);
}

ActiveTrip _trip({
  List<ActiveTripStop>? stops,
  int currentStopIndex = 0,
  int? estimatedTotalMinutes = 30,
}) {
  final resolved = stops ??
      <ActiveTripStop>[
        _stop('KJ01', 'Gombak', 'KJ'),
        _stop('KJ02', 'Taman Melati', 'KJ'),
        _stop('KJ03', 'Wangsa Maju', 'KJ'),
        _stop('KJ04', 'Sri Rampai', 'KJ'),
        _stop('KJ05', 'Setiawangsa', 'KJ'),
      ];
  return ActiveTrip(
    originStopId: resolved.isEmpty ? '' : resolved.first.stopId,
    destinationStopId: resolved.isEmpty ? '' : resolved.last.stopId,
    originName: resolved.isEmpty ? '' : resolved.first.stopName,
    destinationName: resolved.isEmpty ? '' : resolved.last.stopName,
    routePreference: 'efficiency',
    highestCrowdLevel: 2,
    createdAt: DateTime(2026, 1, 1, 8),
    estimatedTotalMinutes: estimatedTotalMinutes,
    stops: resolved,
    currentStopIndex: currentStopIndex,
  );
}

void main() {
  group('buildTripProgressStops', () {
    test('merges consecutive stops with the same name', () {
      final entries = buildTripProgressStops(<ActiveTripStop>[
        _stop('A1', 'Masjid Jamek', 'AG'),
        _stop('B1', 'Masjid Jamek', 'KJ'),
        _stop('B2', 'Dang Wangi', 'KJ'),
      ]);

      expect(entries, hasLength(2));
      expect(entries.first.stopName, 'Masjid Jamek');
      expect(entries.first.routeId, 'KJ');
      expect(entries.first.stopIndex, 1);
      expect(entries.last.stopName, 'Dang Wangi');
    });

    test('ignores case and extra whitespace when merging', () {
      final entries = buildTripProgressStops(<ActiveTripStop>[
        _stop('A1', 'KLCC', 'KJ'),
        _stop('A2', '  klcc  ', 'KJ'),
      ]);

      expect(entries, hasLength(1));
    });

    test('skips blank station names', () {
      final entries = buildTripProgressStops(<ActiveTripStop>[
        _stop('A1', '', 'KJ'),
        _stop('A2', 'Ampang Park', 'KJ'),
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.stopName, 'Ampang Park');
    });
  });

  group('buildTripProgressWindow', () {
    test('shows the current stop plus the next two', () {
      final window = buildTripProgressWindow(_trip(currentStopIndex: 1));

      expect(window.visible, hasLength(3));
      expect(window.current?.stopName, 'Taman Melati');
      expect(
        window.visible.map((entry) => entry.stopName),
        <String>['Taman Melati', 'Wangsa Maju', 'Sri Rampai'],
      );
      expect(window.hasMore, isTrue);
    });

    test('stops at the destination without reporting more', () {
      final window = buildTripProgressWindow(_trip(currentStopIndex: 3));

      expect(
        window.visible.map((entry) => entry.stopName),
        <String>['Sri Rampai', 'Setiawangsa'],
      );
      expect(window.current?.stopName, 'Sri Rampai');
      expect(window.hasMore, isFalse);
    });

    test('maps progress through merged interchange stops', () {
      final window = buildTripProgressWindow(
        _trip(
          currentStopIndex: 2,
          stops: <ActiveTripStop>[
            _stop('A1', 'Gombak', 'KJ'),
            _stop('A2', 'Masjid Jamek', 'AG'),
            _stop('B1', 'Masjid Jamek', 'KJ'),
            _stop('B2', 'Dang Wangi', 'KJ'),
          ],
        ),
      );

      expect(window.all, hasLength(3));
      expect(window.current?.stopName, 'Masjid Jamek');
      expect(window.current?.routeId, 'KJ');
      expect(window.visible.map((entry) => entry.stopName),
          <String>['Masjid Jamek', 'Dang Wangi']);
    });

    test('clamps an out-of-range progress index to the last stop', () {
      final window = buildTripProgressWindow(_trip(currentStopIndex: 99));

      expect(window.current?.stopName, 'Setiawangsa');
      expect(window.visible, hasLength(1));
      expect(window.hasMore, isFalse);
    });

    test('returns an empty window when there are no stops', () {
      final window = buildTripProgressWindow(
        _trip(stops: <ActiveTripStop>[], estimatedTotalMinutes: null),
      );

      expect(window.visible, isEmpty);
      expect(window.current, isNull);
      expect(window.hasMore, isFalse);
    });
  });

  group('ActiveTripService.updateProgress', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('advances forward, ignores backwards moves and clamps to the end',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final service = ActiveTripService.instance;
      await service.clearTrip();

      final trip = _trip(currentStopIndex: 0);
      await service.saveTrip(trip);

      await service.updateProgress(2);
      expect(service.activeTrip.value?.currentStopIndex, 2);

      await service.updateProgress(1);
      expect(service.activeTrip.value?.currentStopIndex, 2);

      await service.updateProgress(99);
      expect(
        service.activeTrip.value?.currentStopIndex,
        trip.stops.length - 1,
      );

      await service.clearTrip();
    });
  });

  group('ActiveTrip serialisation', () {
    test('round-trips the current stop index', () {
      final trip = _trip(currentStopIndex: 2);
      final restored = ActiveTrip.fromJson(trip.toJson());

      expect(restored.currentStopIndex, 2);
      expect(restored.stops, hasLength(trip.stops.length));
    });

    test('defaults a missing current stop index to zero', () {
      final json = _trip(currentStopIndex: 3).toJson()..remove('currentStopIndex');
      expect(ActiveTrip.fromJson(json).currentStopIndex, 0);
    });

    test('withProgress copies the trip and replaces only the index', () {
      final trip = _trip(currentStopIndex: 1);
      final advanced = trip.withProgress(3);

      expect(advanced.currentStopIndex, 3);
      expect(advanced.originName, trip.originName);
      expect(advanced.destinationName, trip.destinationName);
      expect(advanced.stops, trip.stops);
    });
  });
}
