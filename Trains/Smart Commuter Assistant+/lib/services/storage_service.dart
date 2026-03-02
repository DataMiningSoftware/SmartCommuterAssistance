import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../models/route_info.dart';
import 'auth_service.dart';
import 'database_service.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();

  Future<void> initialize() async {
    await _databaseService.initialize();
  }

  Future<int> _requireUserId() async {
    final user = _authService.currentUser.value;
    if (user == null) {
      throw Exception('No authenticated user. Please login first.');
    }
    return user.id;
  }

  Future<void> saveFavoriteRoute(RouteInfo route) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.insert(
      'favorite_routes',
      {
        'user_id': userId,
        'route_id': route.routeId,
        'route_json': jsonEncode(route.copyWith(isFavorite: true).toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavoriteRoute(String routeId) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.delete(
      'favorite_routes',
      where: 'user_id = ? AND route_id = ?',
      whereArgs: [userId, routeId],
    );
  }

  Future<List<RouteInfo>> getFavoriteRoutes() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    final rows = await db.query(
      'favorite_routes',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
    );
    return rows
        .map((row) => RouteInfo.fromJson(jsonDecode(row['route_json'] as String) as Map<String, dynamic>))
        .toList();
  }

  Future<void> addRecentSearch(String origin, String destination) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.insert('recent_searches', {
      'user_id': userId,
      'origin': origin,
      'destination': destination,
      'searched_at': DateTime.now().toIso8601String(),
    });

    final allRows = await db.query(
      'recent_searches',
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC',
    );
    if (allRows.length > 10) {
      final idsToDelete = allRows.skip(10).map((row) => row['id']).toList();
      if (idsToDelete.isNotEmpty) {
        final placeholders = List.filled(idsToDelete.length, '?').join(',');
        await db.delete(
          'recent_searches',
          where: 'id IN ($placeholders)',
          whereArgs: idsToDelete,
        );
      }
    }
  }

  Future<List<Map<String, String>>> getRecentSearches() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    final rows = await db.query(
      'recent_searches',
      columns: ['origin', 'destination'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'searched_at DESC',
      limit: 10,
    );
    return rows
        .map((row) => {
              'origin': row['origin'] as String,
              'destination': row['destination'] as String,
            })
        .toList();
  }

  Future<void> clearRecentSearches() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.delete('recent_searches', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<void> saveUserPreferences(UserPreferences preferences) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.insert(
      'user_preferences',
      {
        'user_id': userId,
        'notifications_enabled': preferences.notificationsEnabled ? 1 : 0,
        'offline_mode_enabled': preferences.offlineModeEnabled ? 1 : 0,
        'accessibility_enabled': preferences.accessibilityEnabled ? 1 : 0,
        'preferred_language': preferences.preferredLanguage,
        'notification_minutes_before': preferences.notificationMinutesBefore,
        'theme': preferences.theme,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserPreferences> getUserPreferences() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    final rows = await db.query(
      'user_preferences',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      await _databaseService.upsertDefaultPreferences(userId);
      return UserPreferences();
    }
    final row = rows.first;
    return UserPreferences(
      notificationsEnabled: (row['notifications_enabled'] as int) == 1,
      offlineModeEnabled: (row['offline_mode_enabled'] as int) == 1,
      accessibilityEnabled: (row['accessibility_enabled'] as int) == 1,
      preferredLanguage: row['preferred_language'] as String,
      notificationMinutesBefore: row['notification_minutes_before'] as int,
      theme: row['theme'] as String,
    );
  }

  Future<void> addTravelHistory(TravelHistoryEntry entry) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.insert('travel_history', {
      'user_id': userId,
      'origin': entry.origin,
      'destination': entry.destination,
      'travel_date': entry.travelDate.toIso8601String(),
      'duration_minutes': entry.durationMinutes,
      'fare': entry.fare,
    });

    final allRows = await db.query(
      'travel_history',
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'travel_date DESC',
    );
    if (allRows.length > 50) {
      final idsToDelete = allRows.skip(50).map((row) => row['id']).toList();
      if (idsToDelete.isNotEmpty) {
        final placeholders = List.filled(idsToDelete.length, '?').join(',');
        await db.delete(
          'travel_history',
          where: 'id IN ($placeholders)',
          whereArgs: idsToDelete,
        );
      }
    }
  }

  Future<List<TravelHistoryEntry>> getTravelHistory() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    final rows = await db.query(
      'travel_history',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'travel_date DESC',
      limit: 50,
    );
    return rows
        .map((row) => TravelHistoryEntry(
              origin: row['origin'] as String,
              destination: row['destination'] as String,
              travelDate: DateTime.parse(row['travel_date'] as String),
              durationMinutes: row['duration_minutes'] as int,
              fare: (row['fare'] as num).toDouble(),
            ))
        .toList();
  }

  Future<void> cacheOfflineData(Map<String, dynamic> data) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.insert(
      'offline_cache',
      {
        'user_id': userId,
        'cache_json': jsonEncode(data),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCachedOfflineData() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    final rows = await db.query(
      'offline_cache',
      columns: ['cache_json'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['cache_json'] as String) as Map<String, dynamic>;
  }

  Future<void> clearAllData() async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();
    await db.delete('favorite_routes', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('recent_searches', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('travel_history', where: 'user_id = ?', whereArgs: [userId]);
    await db.delete('offline_cache', where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<bool> hasData(String key) async {
    final db = await _databaseService.database;
    final userId = await _requireUserId();

    final tableMap = <String, String>{
      'favorite_routes': 'favorite_routes',
      'recent_searches': 'recent_searches',
      'travel_history': 'travel_history',
      'offline_data': 'offline_cache',
    };

    final table = tableMap[key];
    if (table == null) return false;
    final result = await db.rawQuery(
      'SELECT 1 FROM $table WHERE user_id = ? LIMIT 1',
      [userId],
    );
    return result.isNotEmpty;
  }
}

class UserPreferences {
  final bool notificationsEnabled;
  final bool offlineModeEnabled;
  final bool accessibilityEnabled;
  final String preferredLanguage;
  final int notificationMinutesBefore;
  final String theme;

  UserPreferences({
    this.notificationsEnabled = true,
    this.offlineModeEnabled = false,
    this.accessibilityEnabled = false,
    this.preferredLanguage = 'en',
    this.notificationMinutesBefore = 5,
    this.theme = 'system',
  });

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      notificationsEnabled: json['notificationsEnabled'] ?? true,
      offlineModeEnabled: json['offlineModeEnabled'] ?? false,
      accessibilityEnabled: json['accessibilityEnabled'] ?? false,
      preferredLanguage: json['preferredLanguage'] ?? 'en',
      notificationMinutesBefore: json['notificationMinutesBefore'] ?? 5,
      theme: json['theme'] ?? 'system',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notificationsEnabled': notificationsEnabled,
      'offlineModeEnabled': offlineModeEnabled,
      'accessibilityEnabled': accessibilityEnabled,
      'preferredLanguage': preferredLanguage,
      'notificationMinutesBefore': notificationMinutesBefore,
      'theme': theme,
    };
  }
}

class TravelHistoryEntry {
  final String origin;
  final String destination;
  final DateTime travelDate;
  final int durationMinutes;
  final double fare;

  TravelHistoryEntry({
    required this.origin,
    required this.destination,
    required this.travelDate,
    required this.durationMinutes,
    required this.fare,
  });

  factory TravelHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TravelHistoryEntry(
      origin: json['origin'] ?? '',
      destination: json['destination'] ?? '',
      travelDate: DateTime.parse(json['travelDate']),
      durationMinutes: json['durationMinutes'] ?? 0,
      fare: (json['fare'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'origin': origin,
      'destination': destination,
      'travelDate': travelDate.toIso8601String(),
      'durationMinutes': durationMinutes,
      'fare': fare,
    };
  }
}
