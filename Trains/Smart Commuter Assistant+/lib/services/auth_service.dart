import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';
import 'database_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  static const String _sessionUserIdKey = 'session_user_id';
  final ValueNotifier<AppUser?> currentUser = ValueNotifier<AppUser?>(null);
  final DatabaseService _databaseService = DatabaseService();

  Future<void> initialize() async {
    await _ensureAdminAccount();
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_sessionUserIdKey);
    if (userId == null) return;
    final user = await _databaseService.getUserById(userId);
    currentUser.value = user;
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final exists = await _databaseService.emailExists(cleanEmail);
    if (exists) {
      throw Exception('An account with this email already exists.');
    }

    final userId = await _databaseService.createUser(
      name: name.trim(),
      email: cleanEmail,
      passwordHash: _hashPassword(password),
    );
    await _databaseService.upsertDefaultPreferences(userId);
    await _setSession(userId);
    currentUser.value = await _databaseService.getUserById(userId);
  }

  Future<void> login({
    required String email,
    required String password,
  }) async {
    final identifier = email.trim().toLowerCase();
    Map<String, dynamic>? row;

    // Allow quick local admin login using username: admin / password: admin
    if (identifier == 'admin') {
      await _ensureAdminAccount();
      row = await _databaseService.getUserWithHashByEmail('admin@smart.local');
    } else {
      row = await _databaseService.getUserWithHashByEmail(identifier);
    }
    if (row == null) {
      throw Exception('Account not found.');
    }

    final storedHash = row['password_hash'] as String;
    final providedHash = _hashPassword(password);
    if (storedHash != providedHash) {
      throw Exception('Invalid email or password.');
    }

    final userId = row['id'] as int;
    await _setSession(userId);
    currentUser.value = await _databaseService.getUserById(userId);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionUserIdKey);
    currentUser.value = null;
  }

  Future<void> _setSession(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sessionUserIdKey, userId);
  }

  String _hashPassword(String password) {
    // Note: secure for demo/local app usage. For production, use server-side auth.
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  Future<void> _ensureAdminAccount() async {
    const adminEmail = 'admin@smart.local';
    final exists = await _databaseService.emailExists(adminEmail);
    if (exists) return;
    final adminId = await _databaseService.createUser(
      name: 'admin',
      email: adminEmail,
      passwordHash: _hashPassword('admin'),
    );
    await _databaseService.upsertDefaultPreferences(adminId);
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
}

String formatDatabaseException(Object error) {
  if (error is DatabaseException) {
    return 'Database error: ${error.toString()}';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
