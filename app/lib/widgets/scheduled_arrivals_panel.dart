import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/route_colors.dart';
import '../services/gtfs_local_service.dart';
import '../services/train_arrival_service.dart';

class CRTMonitor extends StatelessWidget {
  final Widget child;
  final double height;
  final Color phosphor;

  const CRTMonitor({
    super.key,
    required this.child,
    this.height = 320,
    this.phosphor = const Color(0xFF00FF41),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF444444), width: 3),
        boxShadow: [
          BoxShadow(
            color: phosphor.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          child,
          CustomPaint(
            size: Size.infinite,
            painter: _ScanlinePainter(phosphor: phosphor),
          ),
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  final Color phosphor;

  const _ScanlinePainter({required this.phosphor});

  @override
  void paint(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => true;
}

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

  List<ScheduledTrainArrival>? _arrivals;
  StationArrivalResult? _result;
  String? _errorMessage;
  Timer? _tickTimer;
  Timer? _refreshTimer;
  final Map<String, int> _departureBlinks = <String, int>{};

  @override
  void initState() {
    super.initState();
    _load();
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(covariant ScheduledArrivalsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stopId != widget.stopId || oldWidget.limit != widget.limit) {
      _load();
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  int get _fetchLimit => widget.limit < 4 ? 4 : widget.limit;

  Future<void> _load() async {
    _tickTimer?.cancel();
    _refreshTimer?.cancel();
    setState(() => _departureBlinks.clear());

    try {
      _result = await _arrivalService.fetchStationArrivals(
        widget.stopId,
        limit: _fetchLimit,
      );
      _arrivals = _result!.arrivals;
      _errorMessage = null;
    } catch (_) {
      try {
        final local = await GtfsLocalService.getArrivals(
          widget.stopId,
          limit: _fetchLimit,
        );
        _arrivals = local.arrivals;
        _result = local;
        _errorMessage = null;
      } catch (e) {
        _errorMessage = e.toString();
        _arrivals = null;
        _result = null;
      }
    }

    if (!mounted) return;
    _startTicker();
    _startRefreshTimer();
  }

  void _startTicker() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _tickTimer?.cancel();
        return;
      }
      setState(() {
        _pruneExpired();
        _processDepartureBlinks();
      });
    });
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) {
        _refreshTimer?.cancel();
        return;
      }
      _refresh();
    });
  }

  void _pruneExpired() {
    if (_arrivals == null) return;
    final now = DateTime.now();
    final threshold = now.subtract(const Duration(minutes: 2));
    for (final a in _arrivals!) {
      final key = _arrivalKeyOf(a);
      if (a.arrivalTime.isBefore(threshold) && !_departureBlinks.containsKey(key)) {
        _departureBlinks[key] = 6;
      }
    }
  }

  void _processDepartureBlinks() {
    if (_departureBlinks.isEmpty) return;
    final toRemove = <String>[];
    for (final key in _departureBlinks.keys) {
      final remaining = _departureBlinks[key]! - 1;
      if (remaining <= 0) {
        toRemove.add(key);
      } else {
        _departureBlinks[key] = remaining;
      }
    }
    for (final key in toRemove) {
      _departureBlinks.remove(key);
      _arrivals?.removeWhere((a) => _arrivalKeyOf(a) == key);
    }
    if (_arrivals != null && _arrivals!.isEmpty) {
      _tickTimer?.cancel();
    }
  }

  void _refresh() {
    _tickTimer?.cancel();
    _refreshTimer?.cancel();
    _departureBlinks.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.stationName?.trim().isNotEmpty == true
        ? widget.stationName!.trim()
        : _result?.stopName ?? widget.stopId;

    return CRTMonitor(
      height: widget.compact ? 220 : 340,
      phosphor: const Color(0xFF00FF41),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CRTText('NEXT TRAIN', fontSize: 11, dim: true),
              const Spacer(),
              if (!widget.compact)
                CRTText(
                  _formatTimestamp(DateTime.now()),
                  fontSize: 10,
                  dim: true,
                ),
            ],
          ),
          const SizedBox(height: 4),
          CRTText(
            title.toUpperCase(),
            fontSize: widget.compact ? 12 : 14,
            bold: true,
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 1),
            CRTText(
              widget.stopId.toUpperCase(),
              fontSize: 9,
              dim: true,
            ),
          ],
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF00FF41), height: 1, thickness: 0.5),
          const SizedBox(height: 8),
          if (_errorMessage != null && _arrivals == null)
            Expanded(
              child: GestureDetector(
                onTap: _refresh,
                child: const Center(child: CRTText('SIGNAL LOST — TAP TO RETRY', dim: true, fontSize: 11)),
              ),
            )
          else if (_arrivals == null || _arrivals!.isEmpty)
            const Expanded(
              child: Center(
                child: CRTText('NO SCHEDULED TRAINS', dim: true, fontSize: 11),
              ),
            )
          else
            Expanded(
              child: _buildGroupedArrivals(_arrivals!),
            ),
          const SizedBox(height: 4),
          if (_errorMessage != null)
            const CRTText('OFFLINE — STATIC SCHEDULE', fontSize: 8, dim: true)
          else
            const CRTText('GTFS STATIC SCHEDULE', fontSize: 8, dim: true),
        ],
      ),
    );
  }

  Widget _buildGroupedArrivals(List<ScheduledTrainArrival> arrivals) {
    final groups = _groupByDirection(arrivals);
    if (groups.isEmpty) {
      return const Center(
        child: CRTText('NO SCHEDULED TRAINS', dim: true, fontSize: 11),
      );
    }
    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final group = groups[index];
        return _CRTDirectionBlock(
          trains: group.take(2).toList(),
          blinks: _departureBlinks,
        );
      },
    );
  }

  List<List<ScheduledTrainArrival>> _groupByDirection(
    List<ScheduledTrainArrival> arrivals,
  ) {
    final map = <String, List<ScheduledTrainArrival>>{};
    final order = <String>[];
    for (final a in arrivals) {
      final key = _directionKey(a);
      if (!map.containsKey(key)) {
        map[key] = [];
        order.add(key);
      }
      map[key]!.add(a);
    }
    final groups = order.map((k) => map[k]!).toList();
    for (final g in groups) {
      g.sort((a, b) => a.arrivalTime.compareTo(b.arrivalTime));
    }
    groups.sort((a, b) => a.first.arrivalTime.compareTo(b.first.arrivalTime));
    return groups;
  }

  static String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class CRTText extends StatelessWidget {
  final String data;
  final double fontSize;
  final bool bold;
  final bool dim;

  const CRTText(
    this.data, {
    super.key,
    this.fontSize = 12,
    this.bold = false,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        color: dim
            ? const Color(0xFF00FF41).withValues(alpha: 0.5)
            : const Color(0xFF00FF41),
        height: 1.3,
      ),
    );
  }
}

String _arrivalKeyOf(ScheduledTrainArrival a) =>
    '${a.routeId}_${a.arrivalTime.millisecondsSinceEpoch}_${a.destination}';

String _directionKey(ScheduledTrainArrival a) {
  final dest = a.destination.trim();
  if (dest.isNotEmpty) return '${a.routeId}|$dest';
  if (a.directionId.isNotEmpty) return '${a.routeId}|${a.directionId}';
  return '${a.routeId}|${a.routeLongName}';
}

String _directionLabel(ScheduledTrainArrival a) {
  final dest = a.destination.trim();
  if (dest.isNotEmpty) return dest.toUpperCase();
  if (a.directionId.isNotEmpty) return a.directionId.toUpperCase();
  return a.routeLongName.toUpperCase();
}

class _CRTDirectionBlock extends StatelessWidget {
  final List<ScheduledTrainArrival> trains;
  final Map<String, int> blinks;

  const _CRTDirectionBlock({required this.trains, required this.blinks});

  @override
  Widget build(BuildContext context) {
    final first = trains.first;
    final routeColor = getRouteColor(first.routeId);
    final routeName = normalizeRouteId(first.routeShortName);
    final label = _directionLabel(first);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 4, height: 22, color: routeColor),
            const SizedBox(width: 8),
            SizedBox(
              width: 28,
              child: Text(
                routeName,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: routeColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'TO $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF00FF41),
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatClock(first.arrivalTime),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: const Color(0xFF00FF41).withValues(alpha: 0.6),
                height: 1.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Row(
            children: [
              for (var i = 0; i < trains.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 1,
                    height: 12,
                    color: const Color(0xFF00FF41).withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 10),
                ],
                _countdownChip(trains[i], highlight: i == 0),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _countdownChip(ScheduledTrainArrival a, {required bool highlight}) {
    final blink = blinks[_arrivalKeyOf(a)];
    final secondsPassed = a.arrivalTime.difference(DateTime.now()).inSeconds;
    final minutesLeft = a.arrivalTime.difference(DateTime.now()).inMinutes;
    final departed = secondsPassed < -60;
    final arriving = secondsPassed >= 0 && secondsPassed < 60;
    final text = arriving ? 'ARRIVING' : '$minutesLeft min';

    var opacity = 1.0;
    if (blink != null) opacity = blink % 2 == 1 ? 0.12 : 1.0;

    final color = departed
        ? const Color(0xFF00FF41).withValues(alpha: 0.35)
        : arriving
            ? const Color(0xFFFFEB3B)
            : highlight
                ? const Color(0xFF00FF41)
                : const Color(0xFF00FF41).withValues(alpha: 0.55);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: opacity,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          text,
          key: ValueKey(text),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: arriving ? 10 : 13,
            fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
            color: color,
            height: 1.2,
          ),
        ),
      ),
    );
  }

  static String _formatClock(DateTime value) {
    final local = value.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
