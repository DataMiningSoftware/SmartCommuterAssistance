import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Friend {
  final String userId;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final String? avatarColor;
  final String? homeStationId;
  final String? favoriteLine;

  const Friend({
    required this.userId,
    required this.handle,
    this.displayName,
    this.avatarUrl,
    this.avatarColor,
    this.homeStationId,
    this.favoriteLine,
  });

  String get label => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : handle;

  factory Friend.fromMap(Map<String, dynamic> map) {
    return Friend(
      userId: map['user_id']?.toString() ?? map['id']?.toString() ?? '',
      handle: map['handle']?.toString() ?? '',
      displayName: map['display_name']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      avatarColor: map['avatar_color']?.toString(),
      homeStationId: map['home_station_id']?.toString(),
      favoriteLine: map['favorite_line']?.toString(),
    );
  }
}

class FriendRequest {
  final int id;
  final String requesterId;
  final String status;

  const FriendRequest({
    required this.id,
    required this.requesterId,
    required this.status,
  });

  factory FriendRequest.fromMap(Map<String, dynamic> map) {
    return FriendRequest(
      id: (map['id'] as num).toInt(),
      requesterId: map['requester_id']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
    );
  }
}

class Party {
  final String id;
  final String joinCode;
  final String ownerId;
  final String state;

  const Party({
    required this.id,
    required this.joinCode,
    required this.ownerId,
    required this.state,
  });

  bool get isOpen => state == 'open';
  bool get isActive => state == 'active';

  factory Party.fromMap(Map<String, dynamic> map) {
    return Party(
      id: map['id']?.toString() ?? '',
      joinCode: map['join_code']?.toString() ?? '',
      ownerId: map['owner_id']?.toString() ?? '',
      state: map['state']?.toString() ?? 'open',
    );
  }
}

class PartyMember {
  final String userId;
  final String? currentStationId;
  final String? handle;
  final String? displayName;

  const PartyMember({
    required this.userId,
    this.currentStationId,
    this.handle,
    this.displayName,
  });

  String get label => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : (handle ?? 'Rider');

  factory PartyMember.fromMap(Map<String, dynamic> map) {
    return PartyMember(
      userId: map['user_id']?.toString() ?? '',
      currentStationId: map['current_station_id']?.toString(),
      handle: map['handle']?.toString(),
      displayName: map['display_name']?.toString(),
    );
  }
}

class SocialService {
  static final SocialService instance = SocialService._();
  SocialService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<Party?> currentParty = ValueNotifier<Party?>(null);
  final ValueNotifier<List<PartyMember>> partyMembers =
      ValueNotifier<List<PartyMember>>(const []);

  RealtimeChannel? _partyChannel;
  RealtimeChannel? _memberChannel;

  String? get userId => _client.auth.currentUser?.id;

  // ---- Friends ----------------------------------------------------

  Future<List<Friend>> getFriends() async {
    try {
      final data = await _client.rpc('get_friends');
      final list = data is List ? data : const [];
      return list
          .whereType<Map>()
          .map((e) => Friend.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<FriendRequest>> incomingRequests() async {
    final uid = userId;
    if (uid == null) return const [];
    try {
      final rows = await _client
          .from('friendships')
          .select('id,requester_id,status')
          .eq('addressee_id', uid)
          .eq('status', 'pending');
      return rows
          .whereType<Map>()
          .map((e) => FriendRequest.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> sendRequestToHandle(String handle) async {
    final uid = userId;
    if (uid == null) return;
    final rows = await _client
        .from('profiles')
        .select('id')
        .eq('handle', handle.trim())
        .limit(1);
    if (rows.isEmpty) return;
    final targetId = rows.first['id']?.toString();
    if (targetId == null || targetId == uid) return;
    await _client.from('friendships').insert({
      'requester_id': uid,
      'addressee_id': targetId,
      'status': 'pending',
    });
  }

  Future<void> respondToRequest(int requestId, bool accept) async {
    await _client.from('friendships').update({
      'status': accept ? 'accepted' : 'declined',
    }).eq('id', requestId);
  }

  Future<void> removeFriend(String otherUserId) async {
    final uid = userId;
    if (uid == null) return;
    await _client.from('friendships').delete().or(
          'requester_id.eq.$uid,addressee_id.eq.$otherUserId',
        );
  }

  // ---- Party ------------------------------------------------------

  String _generateJoinCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<Party?> createParty() async {
    try {
      final code = _generateJoinCode();
      final data = await _client.rpc('create_party', params: {'p_join_code': code});
      final list = data is List ? data : const [];
      if (list.isEmpty) return null;
      final partyId = (list.first as Map<String, dynamic>)['party_id']?.toString();
      if (partyId == null) return null;
      return _loadParty(partyId);
    } catch (_) {
      return null;
    }
  }

  Future<Party?> joinParty(String code) async {
    try {
      final data = await _client.rpc('join_party', params: {'p_join_code': code});
      final list = data is List ? data : const [];
      if (list.isEmpty) return null;
      final partyId = (list.first as Map<String, dynamic>)['party_id']?.toString();
      if (partyId == null) return null;
      return _loadParty(partyId);
    } catch (_) {
      return null;
    }
  }

  Future<void> leaveParty(String partyId) async {
    try {
      await _client.rpc('leave_party', params: {'p_party_id': partyId});
    } catch (_) {}
    await _teardownSubscription();
    currentParty.value = null;
    partyMembers.value = const [];
  }

  Future<void> closeParty(String partyId) async {
    try {
      await _client.rpc('close_party', params: {'p_party_id': partyId});
    } catch (_) {}
    await _teardownSubscription();
    currentParty.value = null;
    partyMembers.value = const [];
  }

  Future<void> setLocation(String partyId, String stationId) async {
    try {
      await _client.rpc('set_party_location',
          params: {'p_party_id': partyId, 'p_station_id': stationId});
    } catch (_) {}
  }

  Future<Party?> _loadParty(String partyId) async {
    final rows = await _client.from('parties').select().eq('id', partyId).limit(1);
    if (rows.isEmpty) return null;
    final party = Party.fromMap(rows.first);
    currentParty.value = party;
    await _refreshMembers(partyId);
    _subscribe(partyId);
    return party;
  }

  Future<void> _refreshMembers(String partyId) async {
    try {
      final rows = await _client
          .from('party_members')
          .select('user_id,current_station_id')
          .eq('party_id', partyId);
      final ids = rows
          .whereType<Map>()
          .map((e) => (e as Map<String, dynamic>)['user_id']?.toString())
          .whereType<String>()
          .toList();
      final profileById = await _fetchProfiles(ids);
      final members = <PartyMember>[];
      for (final row in rows.whereType<Map>()) {
        final map = Map<String, dynamic>.from(row);
        final uid = map['user_id']?.toString() ?? '';
        final p = profileById[uid];
        members.add(PartyMember(
          userId: uid,
          currentStationId: map['current_station_id']?.toString(),
          handle: p?['handle']?.toString(),
          displayName: p?['display_name']?.toString(),
        ));
      }
      partyMembers.value = members;
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

  void _subscribe(String partyId) {
    _teardownSubscription();
    _memberChannel = _client
        .channel('party_members_$partyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'party_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'party_id',
            value: partyId,
          ),
          callback: (_) => _refreshMembers(partyId),
        )
        .subscribe();
    _partyChannel = _client
        .channel('party_$partyId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'parties',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: partyId,
          ),
          callback: (_) => _loadParty(partyId),
        )
        .subscribe();
  }

  Future<void> _teardownSubscription() async {
    await _partyChannel?.unsubscribe();
    await _memberChannel?.unsubscribe();
    _partyChannel = null;
    _memberChannel = null;
  }
}
