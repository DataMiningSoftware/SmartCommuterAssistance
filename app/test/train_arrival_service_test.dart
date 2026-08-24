import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/services/train_arrival_service.dart';

void main() {
  group('ScheduledTrainArrival fromJson', () {
    test('parses full JSON correctly', () {
      final json = {
        'stopId': 'KJ1',
        'stopName': 'KL Sentral',
        'routeId': 'MRT',
        'routeShortName': 'MRT',
        'routeLongName': 'MRT Kajang Line',
        'destination': 'Kajang',
        'arrivalTime': '2026-07-18T08:30:00+08:00',
        'minutesUntil': 12,
        'source': 'gtfs_static_schedule',
      };

      final arrival = ScheduledTrainArrival.fromJson(json);

      expect(arrival.stopId, 'KJ1');
      expect(arrival.stopName, 'KL Sentral');
      expect(arrival.routeId, 'MRT');
      expect(arrival.minutesUntil, 12);
      expect(arrival.source, 'gtfs_static_schedule');
      expect(arrival.destination, 'Kajang');
    });

    test('handles missing fields gracefully', () {
      final json = <String, dynamic>{};

      final arrival = ScheduledTrainArrival.fromJson(json);

      expect(arrival.stopId, '');
      expect(arrival.minutesUntil, 0);
      expect(arrival.source, 'gtfs_static_schedule');
    });
  });

  group('StationArrivalResult fromJson', () {
    test('parses response with arrivals', () {
      final json = {
        'stopId': 'KJ1',
        'stopName': 'KL Sentral',
        'generatedAt': '2026-07-18T08:00:00Z',
        'arrivals': [
          {
            'stopId': 'KJ1',
            'stopName': 'KL Sentral',
            'routeId': 'MRT',
            'routeShortName': 'MRT',
            'routeLongName': 'MRT Kajang Line',
            'destination': 'Kajang',
            'arrivalTime': '2026-07-18T08:30:00+08:00',
            'minutesUntil': 12,
            'source': 'gtfs_static_schedule',
          }
        ],
      };

      final result = StationArrivalResult.fromJson(json);

      expect(result.stopId, 'KJ1');
      expect(result.arrivals.length, 1);
      expect(result.arrivals.first.minutesUntil, 12);
    });

    test('handles empty arrivals list', () {
      final json = {
        'stopId': 'KJ1',
        'stopName': 'KL Sentral',
        'arrivals': [],
      };

      final result = StationArrivalResult.fromJson(json);

      expect(result.arrivals, isEmpty);
    });

    test('handles missing arrivals field', () {
      final json = {
        'stopId': 'KJ1',
        'stopName': 'KL Sentral',
      };

      final result = StationArrivalResult.fromJson(json);

      expect(result.arrivals, isEmpty);
    });
  });
}
