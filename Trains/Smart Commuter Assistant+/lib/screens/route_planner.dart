import 'package:flutter/material.dart';

import '../constants/app_shadows.dart';
import '../constants/route_colors.dart';
import '../models/route_info.dart';
import '../services/backend_config_service.dart';
import '../services/commuter_ml_service.dart';
import '../services/transit_network_service.dart';
import '../services/transit_planner_service.dart';
import '../widgets/crowd_indicator.dart';
import '../widgets/data_source_badge.dart';

class RoutePlanner extends StatefulWidget {
  const RoutePlanner({super.key});

  @override
  State<RoutePlanner> createState() => _RoutePlannerState();
}

class _RoutePlannerState extends State<RoutePlanner> {
  final TextEditingController _originCtrl = TextEditingController();
  final TextEditingController _destCtrl = TextEditingController();
  final TransitNetworkService _networkService = TransitNetworkService();
  final BackendConfigService _backendConfig = BackendConfigService();

  TransitPlannerService? _planner;
  TransitPlanResult? _planResult;
  bool _isLoading = false;
  String? _error;
  List<_StationSuggestion> _allStations = [];
  List<_StationSuggestion> _originSuggestions = [];
  List<_StationSuggestion> _destSuggestions = [];
  String? _selectedOriginId;
  String? _selectedDestId;

  @override
  void initState() {
    super.initState();
    _initPlanner();
  }

  Future<void> _initPlanner() async {
    try {
      final graph = TransitGraph.klangValleyDemo();
      final localGateway = LocalTransitPlanningGateway(graph: graph);
      final baseUrl = _backendConfig.baseUrl.value;
      final apiGateway = ApiTransitPlanningGateway(
        graph: graph,
        baseUrl: baseUrl,
      );
      final gateway = ResilientTransitPlanningGateway(
        primary: apiGateway,
        fallback: localGateway,
      );
      _planner = TransitPlannerService(
        gateway: gateway,
        mlService: CommuterMlService(),
      );

      _allStations = graph.stationsById.entries
          .map((e) => _StationSuggestion(
                stopId: e.key,
                name: e.value.name,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load station data');
    }
  }

  void _onOriginChanged(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _selectedOriginId = null;
      _originSuggestions = query.isEmpty
          ? []
          : _allStations
              .where((s) => s.name.toLowerCase().contains(query) ||
                  s.stopId.toLowerCase().contains(query))
              .take(8)
              .toList();
    });
  }

  void _onDestChanged(String value) {
    final query = value.trim().toLowerCase();
    setState(() {
      _selectedDestId = null;
      _destSuggestions = query.isEmpty
          ? []
          : _allStations
              .where((s) => s.name.toLowerCase().contains(query) ||
                  s.stopId.toLowerCase().contains(query))
              .take(8)
              .toList();
    });
  }

  Future<void> _planTrip() async {
    if (_selectedOriginId == null || _selectedDestId == null) return;
    if (_planner == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _planResult = null;
    });

    try {
      final result = await _planner!.planTrip(
        TransitPlanRequest(
          originId: _selectedOriginId!,
          destinationId: _selectedDestId!,
          departureTime: DateTime.now(),
        ),
      );
      if (mounted) setState(() => _planResult = result);
    } catch (e) {
      if (mounted) setState(() => _error = 'Route planning failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _originCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Route Planner')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSearchField(
            controller: _originCtrl,
            label: 'Origin',
            hint: 'Search station...',
            suggestions: _originSuggestions,
            onChanged: _onOriginChanged,
            onSelect: (s) {
              _originCtrl.text = s.name;
              _selectedOriginId = s.stopId;
              setState(() => _originSuggestions = []);
            },
          ),
          const SizedBox(height: 8),
          _buildSearchField(
            controller: _destCtrl,
            label: 'Destination',
            hint: 'Search station...',
            suggestions: _destSuggestions,
            onChanged: _onDestChanged,
            onSelect: (s) {
              _destCtrl.text = s.name;
              _selectedDestId = s.stopId;
              setState(() => _destSuggestions = []);
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: (_selectedOriginId != null &&
                    _selectedDestId != null &&
                    !_isLoading)
                ? _planTrip
                : null,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.route_rounded),
            label: Text(_isLoading ? 'Planning...' : 'Find Routes'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.secondary)),
          ],
          if (_planResult != null) ...[
            const SizedBox(height: 20),
            ..._planResult!.ranked.map((rec) => _RouteCard(rec: rec)),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required List<_StationSuggestion> suggestions,
    required ValueChanged<String> onChanged,
    required ValueChanged<_StationSuggestion> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF667085))),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint, suffixIcon: const Icon(Icons.search)),
          onChanged: onChanged,
        ),
        if (suggestions.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCE4F3)),
              boxShadow: appCardShadows(context),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                dense: true,
                title: Text(suggestions[i].name),
                subtitle: Text(suggestions[i].stopId,
                    style: const TextStyle(fontSize: 11)),
                onTap: () => onSelect(suggestions[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  final RouteRecommendation rec;

  const _RouteCard({required this.rec});

  @override
  Widget build(BuildContext context) {
    final route = rec.route;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: appCardShadows(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${route.origin} → ${route.destination}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              CrowdIndicator(level: route.crowdLevel),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MetaChip(
                  icon: Icons.schedule_rounded,
                  text: route.formattedDuration),
              const SizedBox(width: 8),
              _MetaChip(
                  icon: Icons.attach_money_rounded, text: route.formattedFare),
              const SizedBox(width: 8),
              _MetaChip(
                  icon: Icons.straighten_rounded,
                  text: '${route.totalDistance.toStringAsFixed(1)} km'),
            ],
          ),
          const SizedBox(height: 10),
          ...route.steps.map((step) => _StepRow(step: step)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF475467)),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475467))),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final RouteStep step;

  const _StepRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final color = getRouteColor(step.line);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            child: Icon(
              step.type == RouteStepType.transfer
                  ? Icons.transfer_within_a_station_rounded
                  : Icons.train_rounded,
              size: 14,
              color: getRouteOnColor(step.line),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              step.instruction,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            step.formattedDuration,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF667085)),
          ),
        ],
      ),
    );
  }
}

class _StationSuggestion {
  final String stopId;
  final String name;

  const _StationSuggestion({required this.stopId, required this.name});
}
