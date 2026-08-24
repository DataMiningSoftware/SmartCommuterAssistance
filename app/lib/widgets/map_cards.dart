import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../models/map_station.dart';
import '../models/route_info.dart';
import '../services/map_selection_controller.dart';

class StationOrRouteCard extends StatelessWidget {
  const StationOrRouteCard({super.key, required this.controller});

  final MapSelectionController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.stage) {
      case SelectionStage.none:
        return const SizedBox.shrink();

      case SelectionStage.fromSelected:
        if (controller.to == null) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (controller.errorMessage != null)
                _ErrorBanner(message: controller.errorMessage!),
              _StationCard(station: controller.from!),
            ],
          );
        }
        return controller.isLoadingRoute
            ? const _LoadingCard()
            : const SizedBox.shrink();

      case SelectionStage.routePreview:
      case SelectionStage.confirmed:
        final route = controller.confirmedRoute ?? controller.candidateRoute;
        if (route == null) return const SizedBox.shrink();
        return _RouteSummaryCard(
          route: route,
          confirmed: controller.stage == SelectionStage.confirmed,
          onConfirm: controller.confirmRoute,
          onCancel: controller.clearSelection,
        );
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: const Color(0xFFFEF2F2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 18, color: Color(0xFFD7263D)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Color(0xFFD7263D),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationCard extends StatelessWidget {
  const _StationCard({required this.station});
  final MapStation station;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(station.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: station.lines
                  .map((lineId) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: getRouteColor(lineId),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          lineId,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap another station to plan a route from here.',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Finding the best route...'),
          ],
        ),
      ),
    );
  }
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({
    required this.route,
    required this.confirmed,
    required this.onConfirm,
    required this.onCancel,
  });

  final RouteInfo route;
  final bool confirmed;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transferCount = route.steps.where((s) => s.type == RouteStepType.transfer).length;
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.trip_origin_rounded, size: 14, color: Color(0xFF0F6FFF)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(route.origin, style: theme.textTheme.titleMedium?.copyWith(fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFFD7263D)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(route.destination, style: theme.textTheme.titleMedium?.copyWith(fontSize: 16)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${route.formattedDuration} · $transferCount transfer(s) · ${route.crowdLevel} crowd',
              style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF667085)),
            ),
            const SizedBox(height: 12),
            if (!confirmed)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      child: const Text('Choose different'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirm,
                      child: const Text('Start journey'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Journey started — tracking on the Track tab.',
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
