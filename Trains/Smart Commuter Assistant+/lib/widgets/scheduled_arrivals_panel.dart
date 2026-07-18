import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../services/gtfs_local_service.dart';
import '../services/train_arrival_service.dart';
import 'data_source_badge.dart';

class ScheduledArrivalsPanel extends StatefulWidget {
  final String stopId;
  final String? stationName;
  final int limit;
  final bool compact;

  const ScheduledArrivalsPanel({
    super.key,
    required this.stopId,
    this.stationName,
    this.limit = 4,
    this.compact = false,
  });

  @override
  State<ScheduledArrivalsPanel> createState() => _ScheduledArrivalsPanelState();
}

class _ScheduledArrivalsPanelState extends State<ScheduledArrivalsPanel> {
  final TrainArrivalService _arrivalService = TrainArrivalService();
  late Future<StationArrivalResult> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant ScheduledArrivalsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stopId != widget.stopId || oldWidget.limit != widget.limit) {
      _future = _load();
    }
  }

  Future<StationArrivalResult> _load() async {
    try {
      return await _arrivalService.fetchStationArrivals(
        widget.stopId,
        limit: widget.limit,
      );
    } catch (_) {
      return GtfsLocalService.getArrivals(
        widget.stopId,
        limit: widget.limit,
      );
    }
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StationArrivalResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 3);
        }
        if (snapshot.hasError) {
          return _ArrivalMessage(
            icon: Icons.schedule_send_outlined,
            title: 'Scheduled arrivals unavailable',
            message: 'Start the FastAPI backend or check the backend URL.',
            action: IconButton(
              tooltip: 'Retry arrivals',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final result = snapshot.data;
        final arrivals = result?.arrivals ?? const <ScheduledTrainArrival>[];
        if (arrivals.isEmpty) {
          return _ArrivalMessage(
            icon: Icons.schedule_rounded,
            title: 'No scheduled trains found',
            message:
                'This stop has no remaining GTFS Static arrivals in the current service window.',
            action: IconButton(
              tooltip: 'Retry arrivals',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          );
        }

        final title = widget.stationName?.trim().isNotEmpty == true
            ? widget.stationName!.trim()
            : result?.stopName ?? widget.stopId;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.train_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.compact ? 'Next scheduled trains' : title,
                    style: TextStyle(
                      fontSize: widget.compact ? 14 : 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const DataSourceBadge(source: 'gtfs_static_schedule', compact: true),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Refresh arrivals',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (!widget.compact) ...[
              const SizedBox(height: 2),
              Text(
                result?.stopId ?? widget.stopId,
                style: const TextStyle(
                  color: Color(0xFF667085),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            ...arrivals.map(
              (arrival) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ArrivalRow(arrival: arrival),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ArrivalRow extends StatelessWidget {
  final ScheduledTrainArrival arrival;

  const _ArrivalRow({
    required this.arrival,
  });

  @override
  Widget build(BuildContext context) {
    final routeColor = getRouteColor(arrival.routeId);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: routeColor,
            child: Text(
              normalizeRouteId(arrival.routeShortName),
              style: TextStyle(
                color: getRouteOnColor(arrival.routeId),
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  arrival.destination.isEmpty
                      ? arrival.routeLongName
                      : 'To ${arrival.destination}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      _formatClock(arrival.arrivalTime),
                      style: const TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    DataSourceBadge(
                      source: arrival.source,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            arrival.minutesUntil <= 0 ? 'Due' : '${arrival.minutesUntil} min',
            style: const TextStyle(
              color: Color(0xFF0A3A8B),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatClock(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ArrivalMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget action;

  const _ArrivalMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF667085)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          action,
        ],
      ),
    );
  }
}
