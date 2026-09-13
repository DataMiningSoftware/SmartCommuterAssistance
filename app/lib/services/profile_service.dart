import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  final String id;
  final String handle;
  final String? displayName;
  final String? avatarUrl;
  final String? avatarColor;
  final String? bio;
  final String? homeStationId;
  final String? favoriteLine;
  final bool allowHandleSearch;

  const UserProfile({
    required this.id,
    required this.handle,
    this.displayName,
    this.avatarUrl,
    this.avatarColor,
    this.bio,
    this.homeStationId,
    this.favoriteLine,
    this.allowHandleSearch = true,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? '',
      handle: map['handle']?.toString() ?? '',
      displayName: map['display_name']?.toString(),
      avatarUrl: map['avatar_url']?.toString(),
      avatarColor: map['avatar_color']?.toString(),
      bio: map['bio']?.toString(),
      homeStationId: map['home_station_id']?.toString(),
      favoriteLine: map['favorite_line']?.toString(),
      allowHandleSearch: map['allow_handle_search'] == true,
    );
  }
}

class ProfileService {
  static final ProfileService instance = ProfileService._();
  ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<UserProfile?> currentProfile = ValueNotifier<UserProfile?>(null);

  String? get userId => _client.auth.currentUser?.id;

  Future<UserProfile?> fetchMyProfile() async {
    final uid = userId;
    if (uid == null) return null;
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .limit(1);
      if (rows.isEmpty) return null;
      final profile = UserProfile.fromMap(rows.first);
      currentProfile.value = profile;
      return profile;
    } catch (_) {
      return null;
    }
  }

  Future<bool> updateProfile(Map<String, dynamic> fields) async {
    final uid = userId;
    if (uid == null) return false;
    try {
      await _client.from('profiles').update(fields).eq('id', uid);
      await fetchMyProfile();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    try {
      final data = await _client.rpc('search_users', params: {'p_query': query});
      final list = data is List ? data : const [];
      return list
          .whereType<Map>()
          .map((e) => UserProfile.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
