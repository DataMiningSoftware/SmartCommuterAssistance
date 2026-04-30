import 'package:flutter/material.dart';

import '../constants/crowd_levels.dart';
import '../constants/route_colors.dart';
import '../services/crowd_reports_service.dart';

class StationCrowdBoardScreen extends StatefulWidget {
  const StationCrowdBoardScreen({super.key});

  @override
  State<StationCrowdBoardScreen> createState() =>
      _StationCrowdBoardScreenState();
}

class _StationCrowdBoardScreenState extends State<StationCrowdBoardScreen> {
  final CrowdReportsService _crowdReportsService = CrowdReportsService();
  final TextEditingController _searchController = TextEditingController();
  late Future<List<StationCrowdBoardItem>> _boardFuture;
  String _selectedRoute = 'All';

  @override
  void initState() {
    super.initState();
    _boardFuture = _crowdReportsService.fetchStationCrowdBoard();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _boardFuture = _crowdReportsService.fetchStationCrowdBoard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crowd Pulse'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search station name',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<StationCrowdBoardItem>>(
                future: _boardFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Failed to load crowd board: ${snapshot.error}',
                        style: const TextStyle(color: Color(0xFFB42318)),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final items =
                      snapshot.data ?? const <StationCrowdBoardItem>[];
                  if (items.isEmpty) {
                    return const Center(
                      child: Text(
                        'No station crowd data available yet.',
                        style: TextStyle(
                          color: Color(0xFF667085),
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final routeOptions = <String>{
                    'All',
                    for (final item in items) ...item.routeIds,
                  }.toList()
                    ..sort();
                  if (!routeOptions.contains(_selectedRoute)) {
                    _selectedRoute = 'All';
                  }

                  final query = _searchController.text.trim().toLowerCase();
                  final filtered = items.where((item) {
                    final matchesRoute = _selectedRoute == 'All' ||
                        item.routeIds.contains(_selectedRoute);
                    final matchesQuery = query.isEmpty ||
                        item.stationName.toLowerCase().contains(query) ||
                        item.stopIds.any(
                          (stopId) => stopId.toLowerCase().contains(query),
                        );
                    return matchesRoute && matchesQuery;
                  }).toList();

                  return Column(
                    children: [
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: routeOptions.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final routeId = routeOptions[index];
                            final selected = routeId == _selectedRoute;
                            return ChoiceChip(
                              label: Text(routeId),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _selectedRoute = routeId);
                              },
                              backgroundColor: Theme.of(context).cardColor,
                              selectedColor: routeId == 'All'
                                  ? const Color(0xFFDCE6F5)
                                  : getRouteColor(routeId)
                                      .withValues(alpha: 0.18),
                              labelStyle: TextStyle(
                                color: selected && routeId != 'All'
                                    ? getRouteColor(routeId)
                                    : const Color(0xFF344054),
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async => _refresh(),
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _CrowdBoardStationTile(
                                  item: filtered[index]);
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Refresh'),
      ),
    );
  }
}

class _CrowdBoardStationTile extends StatelessWidget {
  final StationCrowdBoardItem item;

  const _CrowdBoardStationTile({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final isClosed = item.isClosedHours;
    final ui = _crowdUi(item.occupancyLevel, isClosedHours: isClosed);
    final routeSummary =
        item.routeIds.isEmpty ? 'N/A' : item.routeIds.join(' | ');
    final stopSummary = item.stopIds.join(', ');
    final statusTags = CrowdReportsService.statusTagsFor(
      sourceType: item.sourceType,
      fromCache: item.fromCache,
    );
    const mutedText = Color(0xFF98A2B3);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isClosed ? const Color(0xFFF8FAFC) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isClosed
              ? const Color(0xFFD0D5DD)
              : Theme.of(context).dividerColor.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(top: 3),
            decoration: BoxDecoration(
              color: ui.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.stationName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: isClosed
                        ? const Color(0xFF667085)
                        : const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$routeSummary | $stopSummary',
                  style: TextStyle(
                    color: isClosed ? mutedText : const Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CrowdReportsService.displaySourceType(item.sourceType),
                  style: const TextStyle(
                    color: mutedText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (statusTags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: statusTags
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F7FC),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFDCE4F3),
                              ),
                            ),
                            child: Text(
                              tag,
                              style: const TextStyle(
                                color: Color(0xFF344054),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: ui.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              ui.label,
              style: TextStyle(
                color: ui.color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  _CrowdBadgeUi _crowdUi(int level, {bool isClosedHours = false}) {
    if (isClosedHours) {
      return const _CrowdBadgeUi('Closing hours', Color(0xFF98A2B3));
    }
    final crowd = crowdLevelStyleFromIndex(level);
    return _CrowdBadgeUi(crowd.label, crowd.color);
  }
}

class _CrowdBadgeUi {
  final String label;
  final Color color;

  const _CrowdBadgeUi(this.label, this.color);
}
