import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../l10n/generated/app_localizations.dart';
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

class _SheetShell extends StatelessWidget {
  final Widget child;

  const _SheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6E9EF)),
      ),
      child: child,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFBD5D5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Color(0xFFD7263D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineBullet extends StatelessWidget {
  final String lineId;

  const _LineBullet({required this.lineId});

  @override
  Widget build(BuildContext context) {
    final id = resolveSchematicLineId(lineId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: getRouteColor(id),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        normalizeRouteId(id),
        style: TextStyle(
          color: getRouteOnColor(id),
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
          letterSpacing: 0.3,
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
    final l10n = AppLocalizations.of(context);
    final lines = station.lines
        .map(resolveSchematicLineId)
        .where((id) => id.isNotEmpty)
        .toList();

    return _SheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            station.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final id in lines) _LineBullet(lineId: id)],
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: 15,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.mapTapAnotherStation,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(
            AppLocalizations.of(context).mapFindingRoute,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
    final l10n = AppLocalizations.of(context);
    final transfers =
        route.steps.where((s) => s.type == RouteStepType.transfer).length;
    final lines = <String>[];
    String? previous;
    for (final step in route.steps) {
      if (step.type == RouteStepType.transfer) continue;
      final id = normalizeRouteId(step.line);
      if (id == previous) continue;
      lines.add(id);
      previous = id;
    }

    return _SheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      route.origin,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      route.destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    route.formattedDuration,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  Text(
                    l10n.homeTransferCount(transfers),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final id in lines) _LineBullet(lineId: id)],
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.mapRouteSummary(
                    route.formattedDuration,
                    l10n.homeTransferCount(transfers),
                    route.crowdLevel,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              if (route.fare > 0)
                Text(
                  route.formattedFare,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!confirmed)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: Text(l10n.mapChooseDifferent),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: onConfirm,
                    child: Text(l10n.mapStartJourney),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF16A34A),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.mapJourneyStarted,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF16A34A),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
