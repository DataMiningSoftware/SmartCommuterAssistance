import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'database_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final ValueNotifier<AppUser?> currentUser = ValueNotifier<AppUser?>(null);
  final DatabaseService _databaseService = DatabaseService();

  StreamSubscription<AuthState>? _authSubscription;
  bool _isInitialized = false;
  bool _isGuestMode = false;

  @visibleForTesting
  bool get hasAuthSubscription => _authSubscription != null;

  bool get isGuestMode => _isGuestMode;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _databaseService.initialize();

    try {
      await _syncCurrentUserFromSession(
        Supabase.instance.client.auth.currentSession,
      );
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) {
          unawaited(_syncCurrentUserFromSession(data.session));
        },
      );
    } catch (error) {
      debugPrint('Supabase auth unavailable, using guest mode: $error');
      await _activateGuestMode();
    }

    _isInitialized = true;
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: cleanEmail,
        password: password,
        data: <String, dynamic>{
          'name': cleanName,
        },
      );

      if (response.user != null) {
        await _databaseService.upsertUserProfile(
          name: cleanName,
          email: cleanEmail,
        );
      }

      await _syncCurrentUserFromSession(response.session);
    } catch (error) {
      debugPrint('Sign-up unavailable, falling back to guest mode: $error');
      await _activateGuestMode();
    }
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: cleanEmail,
        password: password,
      );
      await _syncCurrentUserFromSession(response.session);
    } catch (error) {
      debugPrint('Login unavailable, falling back to guest mode: $error');
      await _activateGuestMode();
    }
  }

  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('Logout fallback: $error');
    }
    await _activateGuestMode();
  }

  Future<void> _syncCurrentUserFromSession(Session? session) async {
    final authUser = session?.user;
    if (authUser == null) {
      await _activateGuestMode();
      return;
    }

    final email = authUser.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      currentUser.value = null;
      return;
    }

    _isGuestMode = false;
    final metadata = authUser.userMetadata ?? const <String, dynamic>{};
    final name = _extractDisplayName(metadata, email);
    final localUser = await _databaseService.upsertUserProfile(
      name: name,
      email: email,
    );
    currentUser.value = localUser;
  }

  Future<void> _activateGuestMode() async {
    _isGuestMode = true;
    final guestUser = await _databaseService.upsertUserProfile(
      name: 'Guest',
      email: 'guest@local',
    );
    currentUser.value = guestUser;
  }

  String _extractDisplayName(Map<String, dynamic> metadata, String email) {
    const candidates = <String>[
      'name',
      'full_name',
      'display_name',
      'username',
    ];
    for (final key in candidates) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return email.split('@').first;
  }
}

String formatDatabaseException(Object error) {
  if (error is AuthException) {
    return error.message;
  }
  if (error is AuthApiException) {
    return error.message;
  }
  if (error is DatabaseException) {
    return 'Database error: ${error.toString()}';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
