import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import 'backend_config_service.dart';
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

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();

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

    if (response.session != null) {
      await _syncCurrentUserFromSession(response.session);
      return false;
    }

    return true;
  }

  Future<void> resendEmailVerification(String email) async {
    await Supabase.instance.client.auth.resend(
      type: OtpType.signup,
      email: email.trim().toLowerCase(),
    );
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

  Future<void> signInWithOtp(String phone) async {
    await Supabase.instance.client.auth.signInWithOtp(phone: phone.trim());
  }

  Future<void> verifyOtp({
    required String phone,
    required String token,
  }) async {
    final response = await Supabase.instance.client.auth.verifyOTP(
      phone: phone.trim(),
      token: token.trim(),
      type: OtpType.sms,
    );
    await _syncCurrentUserFromSession(response.session);
  }

  Future<void> signInWithGoogle() async {
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.nawfal.smartcommuter://login-callback',
    );
  }

  Future<void> logout() async {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('Logout fallback: $error');
    }
    _isGuestMode = false;
    currentUser.value = null;
  }

  Future<bool> deleteAccount() async {
    final baseUrl =
        BackendConfigService().baseUrl.value.replaceAll(RegExp(r'/+$'), '');
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/account/delete'),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
              if (uid != null) 'x-user-id': uid,
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await logout();
        return true;
      }
    } catch (error) {
      debugPrint('Delete account fallback: $error');
    }
    return false;
  }

  Future<void> enterGuestMode() async {
    await _activateGuestMode();
  }

  Future<void> _syncCurrentUserFromSession(Session? session) async {
    final authUser = session?.user;
    if (authUser == null) {
      _isGuestMode = false;
      currentUser.value = null;
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
