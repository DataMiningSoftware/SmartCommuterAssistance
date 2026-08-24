import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/route_info.dart';
import '../models/transit_graph.dart';
import 'commuter_ml_service.dart';

class TransitPlanRequest {
  final String originId;
  final String destinationId;
  final DateTime departureTime;
  final double rainfallMm;
  final double temperatureC;
  final bool eventNearby;

  const TransitPlanRequest({
    required this.originId,
    required this.destinationId,
    required this.departureTime,
    this.rainfallMm = 2.0,
    this.temperatureC = 30.0,
    this.eventNearby = false,
  });
}

class TransitPlanResult {
  final List<RouteInfo> candidates;
  final List<RouteRecommendation> ranked;
  final DelayCrowdPrediction originPrediction;

  const TransitPlanResult({
    required this.candidates,
    required this.ranked,
    required this.originPrediction,
  });
}

abstract class TransitPlanningGateway {
  TransitGraph get graph;

  Future<List<RouteInfo>> fetchRouteCandidates({
    required String originId,
    required String destinationId,
    required DateTime departureTime,
    int maxRoutes = 4,
  });
}

/// Local graph-backed gateway.
/// This is the current default and can be replaced with a backend gateway later.
class LocalTransitPlanningGateway implements TransitPlanningGateway {
  @override
  final TransitGraph graph;

  LocalTransitPlanningGateway({
    required this.graph,
  });

  @override
  Future<List<RouteInfo>> fetchRouteCandidates({
    required String originId,
    required String destinationId,
    required DateTime departureTime,
    int maxRoutes = 4,
  }) async {
    final paths = graph.enumerateCandidatePaths(
      originId,
      destinationId,
      maxPaths: maxRoutes,
      departureTime: departureTime,
    );
    return paths.asMap().entries.map((entry) {
      final index = entry.key;
      final path = entry.value;
      return _toRouteInfo(path, index + 1);
    }).toList();
  }

  RouteInfo _toRouteInfo(TransitPath path, int sequence) {
    if (path.stationIds.isEmpty) {
      final station = graph
          .station(path.stationIds.isNotEmpty ? path.stationIds.first : '');
      final originName = station?.name ?? '';
      return RouteInfo(
        routeId: 'route_$sequence',
        origin: originName,
        destination: originName,
        steps: const <RouteStep>[],
        totalDurationMinutes: 0,
        totalDistance: 0,
        crowdLevel: 'Light',
        fare: 0,
      );
    }

    final origin = graph.station(path.stationIds.first)!;
    final destination = graph.station(path.stationIds.last)!;
    final steps = <RouteStep>[];
    for (var i = 0; i < path.edges.length; i++) {
      final edge = path.edges[i];
      final nextStation = graph.station(edge.toId)!;
      final stepType =
          edge.isTransfer ? RouteStepType.transfer : RouteStepType.train;
      steps.add(
        RouteStep(
          type: stepType,
          line: edge.line,
          station: nextStation.name,
          stationId: edge.toId,
          durationMinutes: edge.travelMinutes,
          instruction: edge.isTransfer
              ? 'Transfer to ${nextStation.name}'
              : 'Take ${edge.line} to ${nextStation.name}',
        ),
      );
    }

    final crowd = path.transferCount >= 2
        ? 'Crowded'
        : path.totalMinutes > 30
            ? 'Moderate'
            : 'Light';

    final fare =
        (1.4 + (path.totalDistanceKm * 0.13) + (path.transferCount * 0.35))
            .clamp(1.4, 8.0);

    return RouteInfo(
      routeId: 'route_$sequence',
      origin: origin.name,
      destination: destination.name,
      steps: steps,
      totalDurationMinutes: path.totalMinutes,
      totalDistance: path.totalDistanceKm,
      crowdLevel: crowd,
      fare: fare.toDouble(),
    );
  }
}

/// API-ready gateway stub.
/// Replace with HTTP implementation once backend endpoints exist.
class ApiTransitPlanningGateway implements TransitPlanningGateway {
  @override
  final TransitGraph graph;
  final String baseUrl;
  final http.Client client;
  final Duration requestTimeout;

  ApiTransitPlanningGateway({
    required this.graph,
    required this.baseUrl,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 3),
  }) : client = client ?? http.Client();

  @override
  Future<List<RouteInfo>> fetchRouteCandidates({
    required String originId,
    required String destinationId,
    required DateTime departureTime,
    int maxRoutes = 4,
  }) async {
    final uri = Uri.parse('$baseUrl/plan-trip').replace(queryParameters: {
      'origin': originId,
      'destination': destinationId,
      'departure': departureTime.toIso8601String(),
      'maxRoutes': '$maxRoutes',
    });

    final response = await client.get(uri).timeout(requestTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Planner API returned ${response.statusCode}');
    }
    final body = jsonDecode(response.body);
    if (body is! Map<String, dynamic>) {
      throw Exception('Planner API response format invalid');
    }
    final routesJson = body['routes'];
    if (routesJson is! List) {
      throw Exception('Planner API response missing routes list');
    }

    return routesJson.map((json) {
      if (json is! Map<String, dynamic>) {
        throw Exception('Route format invalid');
      }
      return RouteInfo.fromJson(json);
    }).toList();
  }
}

class ResilientTransitPlanningGateway implements TransitPlanningGateway {
  final TransitPlanningGateway primary;
  final TransitPlanningGateway fallback;

  ResilientTransitPlanningGateway({
    required this.primary,
    required this.fallback,
  });

  @override
  TransitGraph get graph => primary.graph;

  @override
  Future<List<RouteInfo>> fetchRouteCandidates({
    required String originId,
    required String destinationId,
    required DateTime departureTime,
    int maxRoutes = 4,
  }) async {
    try {
      final routes = await primary.fetchRouteCandidates(
        originId: originId,
        destinationId: destinationId,
        departureTime: departureTime,
        maxRoutes: maxRoutes,
      );
      if (routes.isNotEmpty) {
        return routes;
      }
    } catch (_) {
      // Silent failover to local routing fallback.
    }

    return fallback.fetchRouteCandidates(
      originId: originId,
      destinationId: destinationId,
      departureTime: departureTime,
      maxRoutes: maxRoutes,
    );
  }
}

class TransitPlannerService {
  final TransitPlanningGateway gateway;
  final CommuterMlService mlService;

  TransitPlannerService({
    required this.gateway,
    required this.mlService,
  });

  TransitGraph get graph => gateway.graph;

  Future<TransitPlanResult> planTrip(TransitPlanRequest request) async {
    final candidates = await gateway.fetchRouteCandidates(
      originId: request.originId,
      destinationId: request.destinationId,
      departureTime: request.departureTime,
      maxRoutes: 4,
    );

    final ranked = mlService.optimizeRoutes(
      departureTime: request.departureTime,
      rainfallMm: request.rainfallMm,
      temperatureC: request.temperatureC,
      eventNearby: request.eventNearby,
      candidates: candidates,
    );

    final bestLine = ranked.isNotEmpty && ranked.first.route.steps.isNotEmpty
        ? ranked.first.route.steps.first.line
        : (graph.station(request.originId)?.line ?? 'MRT Kajang');
    final originPrediction = mlService.predict(
      OperationalSnapshot(
        station: request.originId,
        line: bestLine,
        timestamp: request.departureTime,
        rainfallMm: request.rainfallMm,
        temperatureC: request.temperatureC,
        eventNearby: request.eventNearby,
      ),
    );

    return TransitPlanResult(
      candidates: candidates,
      ranked: ranked,
      originPrediction: originPrediction,
    );
  }

  Future<TransitPlanResult> planTripById({
    required String originStopId,
    required String destinationStopId,
  }) async {
    return planTrip(TransitPlanRequest(
      originId: originStopId,
      destinationId: destinationStopId,
      departureTime: DateTime.now(),
    ));
  }
}
