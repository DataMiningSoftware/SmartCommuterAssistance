import 'package:flutter/foundation.dart';

import '../models/map_station.dart';
import '../models/route_info.dart';
import '../services/transit_planner_service.dart';
import '../services/active_trip_service.dart';

enum SelectionStage { none, fromSelected, routePreview, confirmed }

class MapSelectionController extends ChangeNotifier {
  MapSelectionController({
    required TransitPlannerService plannerService,
    required ActiveTripService activeTripService,
    this.resolveStationId,
  })  : _plannerService = plannerService,
        _activeTripService = activeTripService;

  final TransitPlannerService _plannerService;
  final ActiveTripService _activeTripService;

  /// Maps a schematic/geo station to its transit-graph station ID.
  ///
  /// The schematic map keys stations by lowercase slugs (e.g. `tanjung_malim`)
  /// while the transit graph keys them by line IDs (e.g. `KJ15`). When provided,
  /// this resolver converts a [MapStation] into the ID used for route planning.
  final String? Function(MapStation station)? resolveStationId;

  SelectionStage stage = SelectionStage.none;
  MapStation? from;
  MapStation? to;
  RouteInfo? candidateRoute;
  RouteInfo? confirmedRoute;
  bool isLoadingRoute = false;
  String? errorMessage;

  int get durationMinutes => candidateRoute?.totalDurationMinutes ?? 0;
  int get transferCount {
    if (candidateRoute == null) return 0;
    return candidateRoute!.steps.where((s) => s.type == RouteStepType.transfer).length;
  }

  Future<void> selectStation(MapStation station) async {
    errorMessage = null;

    switch (stage) {
      case SelectionStage.none:
        from = station;
        stage = SelectionStage.fromSelected;
        notifyListeners();
        break;

      case SelectionStage.fromSelected:
        if (from?.stationId == station.stationId) {
          clearSelection();
          return;
        }
        to = station;
        await _fetchRoute();
        break;

      case SelectionStage.routePreview:
      case SelectionStage.confirmed:
        clearSelection();
        from = station;
        stage = SelectionStage.fromSelected;
        notifyListeners();
        break;
    }
  }

  Future<void> _fetchRoute() async {
    if (from == null || to == null) return;
    isLoadingRoute = true;
    notifyListeners();

    try {
      final originId = resolveStationId?.call(from!) ?? from!.stationId;
      final destId = resolveStationId?.call(to!) ?? to!.stationId;
      final result = await _plannerService.planTripById(
        originStopId: originId,
        destinationStopId: destId,
      );

      candidateRoute = result.candidates.isNotEmpty
          ? result.candidates.first
          : null;
      if (candidateRoute != null) {
        stage = SelectionStage.routePreview;
      } else {
        errorMessage = 'Could not find a route between those stations.';
        stage = SelectionStage.fromSelected;
        to = null;
      }
    } catch (e) {
      errorMessage = 'Could not find a route between those stations.';
      stage = SelectionStage.fromSelected;
      to = null;
    } finally {
      isLoadingRoute = false;
      notifyListeners();
    }
  }

  void pickAlternative(RouteInfo route) {
    candidateRoute = route;
    notifyListeners();
  }

  Future<void> confirmRoute() async {
    if (candidateRoute == null) return;
    confirmedRoute = candidateRoute;
    stage = SelectionStage.confirmed;
    notifyListeners();

    final originStop = from;
    final destStop = to;
    if (originStop == null || destStop == null) return;

    final trip = ActiveTrip(
      originStopId: resolveStationId?.call(originStop) ?? originStop.stationId,
      destinationStopId:
          resolveStationId?.call(destStop) ?? destStop.stationId,
      originName: originStop.name,
      destinationName: destStop.name,
      routePreference: 'efficiency',
      highestCrowdLevel: _parseCrowdLevel(candidateRoute!.crowdLevel),
      createdAt: DateTime.now(),
      estimatedTotalMinutes: candidateRoute!.totalDurationMinutes,
      stops: candidateRoute!.steps
          .where((s) => s.stationId.isNotEmpty)
          .map((s) => ActiveTripStop(
                stopId: s.stationId,
                stopName: s.station,
                routeId: s.line,
              ))
          .toList(),
    );
    await _activeTripService.saveTrip(trip);
  }

  int _parseCrowdLevel(String label) {
    switch (label.toLowerCase()) {
      case 'empty':
        return 1;
      case 'light':
        return 2;
      case 'moderate':
        return 3;
      case 'heavy':
        return 4;
      case 'crowded':
        return 5;
      default:
        return 3;
    }
  }

  void clearSelection() {
    from = null;
    to = null;
    candidateRoute = null;
    confirmedRoute = null;
    errorMessage = null;
    stage = SelectionStage.none;
    notifyListeners();
  }
}
