import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/constants/route_colors.dart';
import 'package:smart_commuter/models/transit_graph.dart';
import 'package:smart_commuter/services/fare_service.dart';

void main() {
  group('ERL line identity', () {
    test('uses the official map colours', () {
      expect(getRouteColor('ER6'), const Color(0xFF99168C));
      expect(getRouteColor('ER7'), const Color(0xFF3EA4B4));
    });

    test('names the services rather than the raw line code', () {
      expect(getRouteDisplayName('ER6'), 'KLIA Ekspres');
      expect(getRouteDisplayName('ER7'), 'KLIA Transit');
    });

    test('does not reuse the monorail colour', () {
      expect(getRouteColor('ER7'), isNot(getRouteColor('MR')));
    });
  });

  group('FareService.forSegments', () {
    test('pools rapid transit into a single ticket', () {
      final breakdown = FareService.forSegments(const [
        FareSegmentInput(
          line: 'AG',
          fromStopId: 'AG1',
          toStopId: 'AG7',
          distanceKm: 9,
        ),
        FareSegmentInput(
          line: 'KJ',
          fromStopId: 'KJ13',
          toStopId: 'KJ15',
          distanceKm: 3,
        ),
      ]);

      expect(breakdown.ticketCount, 1);
      expect(breakdown.legs, hasLength(2));
      expect(breakdown.legs.every((leg) => !leg.separateTicket), isTrue);
      final sum = breakdown.legs.fold<double>(0, (total, leg) => total + leg.fare);
      expect(sum, closeTo(breakdown.total, 0.001));
    });

    test('charges the ERL as its own ticket on top of rapid transit', () {
      final breakdown = FareService.forSegments(const [
        FareSegmentInput(
          line: 'PY',
          fromStopId: 'PY40',
          toStopId: 'PY41',
          distanceKm: 1,
        ),
        FareSegmentInput(
          line: 'ER7',
          fromStopId: 'PY41',
          toStopId: 'KJ15',
          distanceKm: 20,
        ),
      ]);

      expect(breakdown.ticketCount, 2);
      expect(breakdown.hasSeparateTickets, isTrue);
      expect(breakdown.legs.first.fare, 1.53);
      expect(breakdown.legs.last.fare, 14.0);
      expect(breakdown.legs.last.separateTicket, isTrue);
      expect(breakdown.total, 15.53);
      expect(breakdown.separateTicketTotal, 14.0);
    });

    test('does not add a transfer surcharge to the fare', () {
      final withTransferLikeDistance = FareService.forSegments(const [
        FareSegmentInput(
          line: 'KJ',
          fromStopId: 'KJ1',
          toStopId: 'KJ2',
          distanceKm: 10,
        ),
      ]);

      expect(withTransferLikeDistance.total, 2.7);
    });

    test('looks up a leg by line and station pair', () {
      final breakdown = FareService.forSegments(const [
        FareSegmentInput(
          line: 'ER7',
          fromStopId: 'PY41',
          toStopId: 'KJ15',
          distanceKm: 20,
        ),
      ]);

      final leg = breakdown.legFor('ER7', 'PY41', 'KJ15');
      expect(leg, isNotNull);
      expect(leg!.fare, 14.0);
      expect(breakdown.legFor('ER6', 'PY41', 'KJ15'), isNull);
    });

    test('returns an empty breakdown for no segments', () {
      expect(FareService.forSegments(const []).isEmpty, isTrue);
      expect(FareService.forSegments(const []).ticketCount, 0);
    });
  });

  group('Cyberjaya City Centre to KL Sentral', () {
    late TransitGraph graph;

    setUpAll(() {
      final json = jsonDecode(
        File('assets/data/transit_network.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      graph = TransitGraph.fromJson(json);
    });

    test('routes via Putrajaya Sentral on KLIA Transit', () {
      final paths = graph.enumerateCandidatePaths('PY40', 'KJ15');
      expect(paths, isNotEmpty);

      final path = paths.first;
      expect(path.stationIds, ['PY40', 'PY41', 'SP15', 'KJ15']);
      expect(path.lineJumps, ['PY', 'ER7']);
      expect(path.transferCount, 1);
    });

    test('prices the trip as two tickets', () {
      final path = graph.findShortestPath('PY40', 'KJ15')!;
      final breakdown = FareService.breakdownForPath(path, graph);

      expect(breakdown.ticketCount, 2);
      expect(breakdown.legs.map((leg) => leg.line), ['PY', 'ER7']);
      expect(breakdown.legs.last.fare, 14.0);
      expect(breakdown.total, 15.53);
    });

    test('reports ride time separately from the weighted transfer cost', () {
      final path = graph.findShortestPath('PY40', 'KJ15')!;
      expect(path.rideMinutes, 21);
      expect(path.totalMinutes, greaterThanOrEqualTo(path.rideMinutes));
    });
  });

  group('Transfer penalty profiles', () {
    late TransitGraph graph;

    setUpAll(() {
      final json = jsonDecode(
        File('assets/data/transit_network.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      graph = TransitGraph.fromJson(json);
    });

    test('comfort finds a path with fewer transfers', () {
      final fastest = graph.findShortestPath('KJ31', 'PY24', transferPenalty: 4);
      final comfort = graph.findShortestPath('KJ31', 'PY24', transferPenalty: 40);

      expect(fastest, isNotNull);
      expect(comfort, isNotNull);
      expect(comfort!.transferCount, lessThan(fastest!.transferCount));
    });

    test('enumerates distinct candidates across profiles', () {
      final candidates = graph.enumerateCandidatePaths('KJ31', 'PY24');
      expect(candidates.length, greaterThan(1));

      final signatures = candidates.map((c) => c.stationIds.join('>')).toSet();
      expect(signatures.length, candidates.length);

      for (var i = 1; i < candidates.length; i++) {
        expect(
          candidates[i].rideMinutes,
          greaterThanOrEqualTo(candidates[i - 1].rideMinutes),
        );
      }
    });

    test('does not invent an alternative where only one route exists', () {
      expect(graph.enumerateCandidatePaths('PY40', 'KJ15'), hasLength(1));
    });
  });
}
