import 'package:flutter/material.dart';

import '../models/transit_graph.dart';
import '../services/route_choice_service.dart';
import '../services/transit_data_service.dart';
import '../widgets/app_page_title.dart';

class RouteBuilderScreen extends StatefulWidget {
  const RouteBuilderScreen({super.key});

  @override
  State<RouteBuilderScreen> createState() => _RouteBuilderScreenState();
}

class _RouteBuilderScreenState extends State<RouteBuilderScreen> {
  final RouteChoiceService _routeChoice = RouteChoiceService.instance;

  TransitGraph? _graph;
  bool _loading = true;
  String _mode = 'assisted';

  String? _originId;
  String? _destinationId;
  final List<String> _waypoints = <String>[];

  int? _agentMinutes;
  int? _agentTransfers;
  int? _manualMinutes;
  int? _manualTransfers;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final graph = await TransitDataService.instance.load();
    if (mounted) {
      setState(() {
        _graph = graph;
        _loading = false;
      });
    }
  }

  TransitStation? _station(String id) => _graph?.stations[id];

  String _name(String? id) => id == null ? '' : (_station(id)?.name ?? id);

  List<({String id, String name})> get _stationOptions {
    final graph = _graph;
    if (graph == null) return const [];
    final seen = <String>{};
    final result = <({String id, String name})>[];
    for (final s in graph.stations.values) {
      if (s.name.isEmpty) continue;
      if (!seen.add(s.name.toUpperCase())) continue;
      result.add((id: s.id, name: s.name));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  Future<void> _pickStation(String title, ValueChanged<String> onPicked) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StationPicker(options: _stationOptions, title: title),
    );
    if (id != null) onPicked(id);
  }

  void _addWaypoint() {
    _pickStation('Add waypoint', (id) {
      setState(() => _waypoints.add(id));
    });
  }

  Future<void> _compute() async {
    final graph = _graph;
    if (graph == null || _originId == null || _destinationId == null) return;

    setState(() {
      _error = null;
      _agentMinutes = null;
      _agentTransfers = null;
      _manualMinutes = null;
      _manualTransfers = null;
    });

    final agent = graph.findShortestPath(_originId!, _destinationId!);

    final ordered = <String>[_originId!, ..._waypoints, _destinationId!];
    var manualTotal = 0;
    var manualTransfers = 0;
    String? invalid;
    for (var i = 0; i < ordered.length - 1; i++) {
      final seg = graph.findShortestPath(ordered[i], ordered[i + 1]);
      if (seg == null) {
        invalid = 'No route between ${_name(ordered[i])} and ${_name(ordered[i + 1])}.';
        break;
      }
      manualTotal += seg.totalMinutes;
      manualTransfers += seg.transferCount;
    }

    setState(() {
      if (agent != null) {
        _agentMinutes = agent.totalMinutes;
        _agentTransfers = agent.transferCount;
      }
      if (invalid == null) {
        _manualMinutes = manualTotal;
        _manualTransfers = manualTransfers;
      } else {
        _error = invalid;
      }
    });
  }

  Future<void> _logComparison() async {
    final agentPath = _graph?.findShortestPath(_originId!, _destinationId!)?.stationIds;
    final chosenPath = <String>[_originId!, ..._waypoints, _destinationId!];
    final choice = RouteChoice(
      originId: _originId!,
      originName: _name(_originId),
      destId: _destinationId!,
      destName: _name(_destinationId),
      mode: _mode,
      chosenPath: chosenPath,
      agentPath: agentPath,
      agentPredictedMin: _agentMinutes,
      chosenMinutes: _manualMinutes,
    );
    final ok = await _routeChoice.submitFeedback(choice);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Comparison logged for retraining.' : 'Log in to save comparisons.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: const AppPageTitle(
          icon: Icons.alt_route_rounded,
          leadingText: 'Route',
          accentText: 'Builder',
          badgeText: 'PLAN',
          subtitle: 'Assisted vs manual',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'assisted', label: Text('Assisted'), icon: Icon(Icons.auto_awesome)),
              ButtonSegment(value: 'manual', label: Text('Manual'), icon: Icon(Icons.draw_outlined)),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          _stationField(
            label: 'Origin',
            value: _originId == null ? null : _name(_originId),
            onTap: () => _pickStation('Choose origin', (id) => setState(() => _originId = id)),
          ),
          const SizedBox(height: 10),
          _stationField(
            label: 'Destination',
            value: _destinationId == null ? null : _name(_destinationId),
            onTap: () => _pickStation('Choose destination', (id) => setState(() => _destinationId = id)),
          ),
          if (_mode == 'manual') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text('Waypoints (your own path)', style: Theme.of(context).textTheme.titleMedium)),
                IconButton(onPressed: _addWaypoint, icon: const Icon(Icons.add_circle_outline)),
              ],
            ),
            if (_waypoints.isEmpty)
              const Text('Add stations in the order you want to travel.', style: TextStyle(fontSize: 13))
            else
              ...List.generate(_waypoints.length, (i) {
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(_name(_waypoints[i])),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _waypoints.removeAt(i)),
                  ),
                );
              }),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_originId != null && _destinationId != null) ? _compute : null,
            icon: const Icon(Icons.calculate_outlined),
            label: const Text('Compare routes'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_agentMinutes != null || _manualMinutes != null) ...[
            const SizedBox(height: 20),
            _comparisonCard(),
          ],
        ],
      ),
    );
  }

  Widget _stationField({required String label, String? value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.search),
        ),
        child: Text(value ?? 'Tap to select'),
      ),
    );
  }

  Widget _comparisonCard() {
    final agent = _agentMinutes;
    final manual = _manualMinutes;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comparison', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _row('Agent route', agent == null ? '—' : '$agent min · ${_agentTransfers ?? 0} transfers'),
          _row('Your route', manual == null ? '—' : '$manual min · ${_manualTransfers ?? 0} transfers'),
          if (agent != null && manual != null && manual < agent) ...[
            const SizedBox(height: 12),
            Text(
              'You beat the agent by ${agent - manual} min!',
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _logComparison,
            child: const Text('Log this comparison'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _StationPicker extends StatefulWidget {
  final List<({String id, String name})> options;
  final String title;

  const _StationPicker({required this.options, required this.title});

  @override
  State<_StationPicker> createState() => _StationPickerState();
}

class _StationPickerState extends State<_StationPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.options
        .where((o) => o.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(labelText: widget.title, hintText: 'Search station'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('No stations found.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => ListTile(
                        dense: true,
                        title: Text(filtered[i].name),
                        subtitle: Text(filtered[i].id),
                        onTap: () => Navigator.pop(context, filtered[i].id),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
