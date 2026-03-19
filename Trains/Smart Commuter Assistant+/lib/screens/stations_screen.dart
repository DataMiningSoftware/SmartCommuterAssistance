import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StationsScreen extends StatefulWidget {
  const StationsScreen({super.key});

  @override
  State<StationsScreen> createState() => _StationsScreenState();
}

class _StationsScreenState extends State<StationsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final List<Map<String, dynamic>> _allStations = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _filteredStations = <Map<String, dynamic>>[];
  bool _isLoading = true;
  bool _isFindingNearest = false;
  String? _errorMessage;
  Position? _userPosition;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _loadStations();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rows = await Supabase.instance.client.from('train_stops_kl').select();
      final stations = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      stations.sort((a, b) {
        final aName = _stationName(a).toLowerCase();
        final bName = _stationName(b).toLowerCase();
        return aName.compareTo(bName);
      });

      if (!mounted) return;
      setState(() {
        _allStations
          ..clear()
          ..addAll(stations);
        _filteredStations = List<Map<String, dynamic>>.from(_allStations);
      });
      if (_userPosition != null) {
        _sortByDistance(_userPosition!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredStations = List<Map<String, dynamic>>.from(_allStations));
      return;
    }

    final filtered = _allStations.where((station) {
      final name = _stationName(station).toLowerCase();
      final line = _stationLine(station).toLowerCase();
      final code = _stationCode(station).toLowerCase();
      return name.contains(query) || line.contains(query) || code.contains(query);
    }).toList();

    setState(() => _filteredStations = filtered);
    if (_userPosition != null) {
      _sortByDistance(_userPosition!);
    }
  }

  Future<void> _findNearestStations() async {
    setState(() => _isFindingNearest = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMessage('Location services are disabled.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showMessage('Location permission denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage('Location permission denied forever. Enable it in settings.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() => _userPosition = position);
      final nearest = _sortByDistance(position);
      if (nearest == null) {
        _showMessage('No valid stop_lat/stop_lon found to calculate distance.');
        return;
      }
      final nearestName = _stationName(nearest);
      final nearestDistance = _distanceMeters(nearest, position)!;
      _showMessage(
        'Nearest: $nearestName (${_StationCard._formatDistance(nearestDistance)}) '
        'at ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
      );
    } catch (e) {
      _showMessage('Failed to get location: $e');
    } finally {
      if (mounted) setState(() => _isFindingNearest = false);
    }
  }

  Map<String, dynamic>? _sortByDistance(Position position) {
    final sorted = List<Map<String, dynamic>>.from(_filteredStations);
    sorted.sort((a, b) {
      final aDistance = _distanceMeters(a, position) ?? double.infinity;
      final bDistance = _distanceMeters(b, position) ?? double.infinity;
      return aDistance.compareTo(bDistance);
    });
    Map<String, dynamic>? nearest;
    for (final station in sorted) {
      if (_distanceMeters(station, position) != null) {
        nearest = station;
        break;
      }
    }
    if (!mounted) return nearest;
    setState(() => _filteredStations = sorted);
    return nearest;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _distanceMeters(Map<String, dynamic> station, Position position) {
    final lat = _toDouble(station['stop_lat']);
    final lon = _toDouble(station['stop_lon']);
    if (lat == null || lon == null) return null;
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lon,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Train Stations'),
        actions: [
          IconButton(
            onPressed: _isFindingNearest ? null : _findNearestStations,
            icon: _isFindingNearest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            tooltip: 'Nearest',
          ),
          IconButton(
            onPressed: _loadStations,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by station, line, or code',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          FocusScope.of(context).unfocus();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFD7263D), size: 30),
              const SizedBox(height: 10),
              const Text(
                'Failed to load stations from Supabase',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF667085)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loadStations,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_allStations.isEmpty) {
      return const Center(
        child: Text('Connected, but table train_stops_kl has 0 rows.'),
      );
    }

    if (_filteredStations.isEmpty) {
      return const Center(child: Text('No stations match your search.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: _filteredStations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final station = _filteredStations[index];
        return _StationCard(
          name: _stationName(station),
          line: _stationLine(station),
          code: _stationCode(station),
          distanceMeters:
              _userPosition == null ? null : _distanceMeters(station, _userPosition!),
        );
      },
    );
  }

  static String _pickValue(Map<String, dynamic> row, List<String> keys, {String fallback = 'N/A'}) {
    for (final key in keys) {
      final value = row[key];
      if (value != null) {
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return fallback;
  }

  static String _stationName(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['stop_name', 'station_name', 'name', 'station'],
        fallback: 'Unnamed Station',
      );

  static String _stationLine(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['category', 'line', 'line_name', 'route', 'route_name'],
      );

  static String _stationCode(Map<String, dynamic> row) => _pickValue(
        row,
        const <String>['stop_id', 'station_code', 'code', 'stop_code', 'route_id', 'id'],
      );
}

class _StationCard extends StatelessWidget {
  final String name;
  final String line;
  final String code;
  final double? distanceMeters;

  const _StationCard({
    required this.name,
    required this.line,
    required this.code,
    required this.distanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.train_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  line,
                  style: const TextStyle(color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7FC),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: const Color(0xFFDDE6F5)),
                ),
                child: Text(
                  code,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (distanceMeters != null) ...[
                const SizedBox(height: 5),
                Text(
                  _formatDistance(distanceMeters!),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF667085)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} m';
    return '${(meters / 1000).toStringAsFixed(2)} km';
  }
}
