import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_config_service.dart';

class RaceInfo {
  final String id;
  final String category;
  final String targetMode;
  final String? destinationStopId;
  final String status;

  const RaceInfo({
    required this.id,
    required this.category,
    required this.targetMode,
    this.destinationStopId,
    required this.status,
  });

  factory RaceInfo.fromMap(Map<String, dynamic> map) {
    return RaceInfo(
      id: map['id']?.toString() ?? '',
      category: map['category']?.toString() ?? 'fastest',
      targetMode: map['target_mode']?.toString() ?? 'shared_destination',
      destinationStopId: map['destination_stop_id']?.toString(),
      status: map['status']?.toString() ?? 'countdown',
    );
  }
}

class RaceParticipant {
  final String userId;
  final String? destinationStopId;
  final String routeSource;
  final String status;
  final double? resultValue;
  final int? rank;
  final int? agentPredictedMin;
  final String? handle;
  final String? displayName;

  const RaceParticipant({
    required this.userId,
    this.destinationStopId,
    this.routeSource = 'agent',
    this.status = 'ready',
    this.resultValue,
    this.rank,
    this.agentPredictedMin,
    this.handle,
    this.displayName,
  });

  String get label => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : (handle ?? 'Rider');

  factory RaceParticipant.fromMap(Map<String, dynamic> map) {
    return RaceParticipant(
      userId: map['user_id']?.toString() ?? '',
      destinationStopId: map['destination_stop_id']?.toString(),
      routeSource: map['route_source']?.toString() ?? 'agent',
      status: map['status']?.toString() ?? 'ready',
      resultValue: map['result_value'] is num
          ? (map['result_value'] as num).toDouble()
          : null,
      rank: map['rank'] is num ? (map['rank'] as num).toInt() : null,
      agentPredictedMin: map['agent_predicted_min'] is num
          ? (map['agent_predicted_min'] as num).toInt()
          : null,
    );
  }
}

class Checkpoint {
  final String userId;
  final String stationId;
  final int seq;
  final String plausibility;
  final int? crowdLevel;

  const Checkpoint({
    required this.userId,
    required this.stationId,
    required this.seq,
    this.plausibility = 'ok',
    this.crowdLevel,
  });

  bool get isDisputed => plausibility == 'disputed';

  factory Checkpoint.fromMap(Map<String, dynamic> map) {
    return Checkpoint(
      userId: map['user_id']?.toString() ?? '',
      stationId: map['station_id']?.toString() ?? '',
      seq: map['seq'] is num ? (map['seq'] as num).toInt() : 0,
      plausibility: map['plausibility']?.toString() ?? 'ok',
      crowdLevel: map['crowd_level'] is num
          ? (map['crowd_level'] as num).toInt()
          : null,
    );
  }
}

class RaceService {
  static final RaceService instance = RaceService._();
  RaceService._();

  SupabaseClient get _client => Supabase.instance.client;
  String get _baseUrl =>
      BackendConfigService().baseUrl.value.replaceAll(RegExp(r'/+$'), '');

  final ValueNotifier<RaceInfo?> currentRace = ValueNotifier<RaceInfo?>(null);
  final ValueNotifier<List<RaceParticipant>> participants =
      ValueNotifier<List<RaceParticipant>>(const []);
  final ValueNotifier<List<Checkpoint>> checkpoints =
      ValueNotifier<List<Checkpoint>>(const []);

  RealtimeChannel? _participantsChannel;
  RealtimeChannel? _checkpointsChannel;

  String? get userId => _client.auth.currentUser?.id;
  String? get _accessToken => _client.auth.currentSession?.accessToken;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
        if (userId != null) 'x-user-id': userId!,
      };

  Future<RaceInfo?> startRace({
    required String partyId,
    required String category,
    required String targetMode,
    String? destinationStopId,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/race/start'),
            headers: _headers,
            body: jsonEncode({
              'party_id': partyId,
              'category': category,
              'target_mode': targetMode,
              'destination_stop_id': destinationStopId,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return loadRace(body['race_id']?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<RaceInfo?> loadRace(String raceId) async {
    if (raceId.isEmpty) return null;
    try {
      final rows = await _client.from('races').select().eq('id', raceId).limit(1);
      if (rows.isEmpty) return null;
      final race = RaceInfo.fromMap(rows.first);
      currentRace.value = race;
      await _refreshParticipants(raceId);
      await _refreshCheckpoints(raceId);
      _subscribe(raceId);
      return race;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearRace() async {
    await _teardownSubscription();
    currentRace.value = null;
    participants.value = const [];
    checkpoints.value = const [];
  }

  Future<void> setPlan({
    required String raceId,
    String? destinationStopId,
    String? routeSource,
    String? chosenPath,
    String? agentPath,
    int? agentPredictedMin,
  }) async {
    try {
      await _client.rpc('set_race_plan', params: {
        'p_race_id': raceId,
        'p_destination_stop_id': destinationStopId,
        'p_route_source': routeSource,
        'p_chosen_path': chosenPath,
        'p_agent_path': agentPath,
        'p_agent_predicted_min': agentPredictedMin,
      });
    } catch (_) {}
  }

  Future<String?> submitCheckpoint({
    required String raceId,
    required String stationId,
    required int seq,
    int? crowdLevel,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$_baseUrl/race/checkpoint'),
            headers: _headers,
            body: jsonEncode({
              'race_id': raceId,
              'station_id': stationId,
              'seq': seq,
              'crowd_level': crowdLevel,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return body['plausibility']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> finalize(String raceId) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/race/finalize'),
            headers: _headers,
            body: jsonEncode({'race_id': raceId}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  Future<void> _refreshParticipants(String raceId) async {
    try {
      final rows = await _client
          .from('race_participants')
          .select()
          .eq('race_id', raceId);
      final ids = rows
          .whereType<Map>()
          .map((e) => (e as Map<String, dynamic>)['user_id']?.toString())
          .whereType<String>()
          .toList();
      final profileById = await _fetchProfiles(ids);
      final result = rows.whereType<Map>().map((e) {
        final map = Map<String, dynamic>.from(e);
        final uid = map['user_id']?.toString() ?? '';
        final p = profileById[uid];
        final part = RaceParticipant.fromMap(map);
        return RaceParticipant(
          userId: part.userId,
          destinationStopId: part.destinationStopId,
          routeSource: part.routeSource,
          status: part.status,
          resultValue: part.resultValue,
          rank: part.rank,
          agentPredictedMin: part.agentPredictedMin,
          handle: p?['handle']?.toString(),
          displayName: p?['display_name']?.toString(),
        );
      }).toList();
      participants.value = result;
    } catch (_) {}
  }

  Future<void> _refreshCheckpoints(String raceId) async {
    try {
      final rows = await _client
          .from('race_checkpoints')
          .select()
          .eq('race_id', raceId)
          .order('seq');
      checkpoints.value = rows
          .whereType<Map>()
          .map((e) => Checkpoint.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {}
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfiles(
      List<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      final rows = await _client.from('profiles').select().inFilter('id', ids);
      final result = <String, Map<String, dynamic>>{};
      for (final row in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        final id = map['id']?.toString();
        if (id != null) result[id] = map;
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  void _subscribe(String raceId) {
    _teardownSubscription();
    _participantsChannel = _client
        .channel('race_participants_$raceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'race_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'race_id',
            value: raceId,
          ),
          callback: (_) => _refreshParticipants(raceId),
        )
        .subscribe();
    _checkpointsChannel = _client
        .channel('race_checkpoints_$raceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'race_checkpoints',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'race_id',
            value: raceId,
          ),
          callback: (_) => _refreshCheckpoints(raceId),
        )
        .subscribe();
  }

  Future<void> _teardownSubscription() async {
    await _participantsChannel?.unsubscribe();
    await _checkpointsChannel?.unsubscribe();
    _participantsChannel = null;
    _checkpointsChannel = null;
  }
}
