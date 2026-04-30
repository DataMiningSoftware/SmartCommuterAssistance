import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_user.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<void> initialize() async {
    await database;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'smart_commuter.db');

    return openDatabase(
      path,
      version: 3,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE user_preferences(
            user_id INTEGER PRIMARY KEY,
            notifications_enabled INTEGER NOT NULL DEFAULT 1,
            offline_mode_enabled INTEGER NOT NULL DEFAULT 0,
            accessibility_enabled INTEGER NOT NULL DEFAULT 0,
            preferred_language TEXT NOT NULL DEFAULT 'en',
            notification_minutes_before INTEGER NOT NULL DEFAULT 5,
            theme TEXT NOT NULL DEFAULT 'system',
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE favorite_routes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            route_id TEXT NOT NULL,
            route_json TEXT NOT NULL,
            UNIQUE(user_id, route_id),
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE recent_searches(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            origin TEXT NOT NULL,
            destination TEXT NOT NULL,
            searched_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE travel_history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            origin TEXT NOT NULL,
            destination TEXT NOT NULL,
            travel_date TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            fare REAL NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE offline_cache(
            user_id INTEGER PRIMARY KEY,
            cache_json TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        ''');

        await _createRouteCacheTables(db);
        await _createIndexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createRouteCacheTables(db);
        }
        if (oldVersion < 3) {
          await _createIndexes(db);
        }
      },
    );
  }

  Future<void> _createRouteCacheTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_train_stops(
        stop_id TEXT PRIMARY KEY,
        stop_name TEXT NOT NULL,
        stop_lat REAL,
        stop_lon REAL,
        route_id TEXT,
        category TEXT,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS cached_route_connections(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        from_stop_id TEXT NOT NULL,
        to_stop_id TEXT NOT NULL,
        route_id TEXT NOT NULL,
        connection_type TEXT NOT NULL DEFAULT 'standard_stop',
        travel_time_minutes INTEGER NOT NULL DEFAULT 2,
        UNIQUE(from_stop_id, to_stop_id, route_id, connection_type)
      )
    ''');
  }

  Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_recent_searches_user_searched_at
      ON recent_searches(user_id, searched_at DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_travel_history_user_travel_date
      ON travel_history(user_id, travel_date DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_favorite_routes_user_id
      ON favorite_routes(user_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_cached_route_connections_from_stop
      ON cached_route_connections(from_stop_id)
    ''');
  }

  Future<int> createUser({
    required String name,
    required String email,
    required String passwordHash,
  }) async {
    final db = await database;
    return db.insert('users', {
      'name': name,
      'email': email,
      'password_hash': passwordHash,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getUserWithHashByEmail(String email) async {
    final db = await database;
    final rows = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['id', 'name', 'email', 'created_at'],
      where: 'email = ?',
      whereArgs: [email],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<AppUser?> getUserById(int id) async {
    final db = await database;
    final rows = await db.query(
      'users',
      columns: ['id', 'name', 'email', 'created_at'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUser.fromMap(rows.first);
  }

  Future<bool> emailExists(String email) async {
    final row = await getUserWithHashByEmail(email);
    return row != null;
  }

  Future<AppUser> upsertUserProfile({
    required String name,
    required String email,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanName =
        name.trim().isEmpty ? cleanEmail.split('@').first : name.trim();
    final existing = await getUserByEmail(cleanEmail);
    if (existing != null) {
      final db = await database;
      await db.update(
        'users',
        {'name': cleanName},
        where: 'id = ?',
        whereArgs: [existing['id']],
      );
      final updated = await getUserById(existing['id'] as int);
      if (updated == null) {
        throw StateError('Failed to load updated user profile for $cleanEmail');
      }
      return updated;
    }

    final id = await createUser(
      name: cleanName,
      email: cleanEmail,
      passwordHash: 'supabase_auth',
    );
    await upsertDefaultPreferences(id);
    final created = await getUserById(id);
    if (created == null) {
      throw StateError('Failed to create local user profile for $cleanEmail');
    }
    return created;
  }

  Future<void> upsertDefaultPreferences(int userId) async {
    final db = await database;
    await db.insert(
      'user_preferences',
      {'user_id': userId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> cacheTrainStops(List<Map<String, dynamic>> stops) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('cached_train_stops');
      final now = DateTime.now().toIso8601String();
      for (final stop in stops) {
        final stopId = stop['stop_id']?.toString();
        final stopName = stop['stop_name']?.toString();
        if (stopId == null ||
            stopId.isEmpty ||
            stopName == null ||
            stopName.isEmpty) {
          continue;
        }
        await txn.insert(
          'cached_train_stops',
          {
            'stop_id': stopId,
            'stop_name': stopName,
            'stop_lat': _toDouble(stop['stop_lat']),
            'stop_lon': _toDouble(stop['stop_lon']),
            'route_id': stop['route_id']?.toString(),
            'category': stop['category']?.toString(),
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedTrainStops() async {
    final db = await database;
    return db.query('cached_train_stops');
  }

  Future<void> cacheRouteConnections(
      List<Map<String, dynamic>> connections) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('cached_route_connections');
      for (final edge in connections) {
        final from = edge['from_stop_id']?.toString();
        final to = edge['to_stop_id']?.toString();
        final route = edge['route_id']?.toString();
        if (from == null ||
            from.isEmpty ||
            to == null ||
            to.isEmpty ||
            route == null ||
            route.isEmpty) {
          continue;
        }
        await txn.insert(
          'cached_route_connections',
          {
            'from_stop_id': from,
            'to_stop_id': to,
            'route_id': route,
            'connection_type':
                edge['connection_type']?.toString() ?? 'standard_stop',
            'travel_time_minutes': _toInt(edge['travel_time_minutes']) ?? 2,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getCachedRouteConnections() async {
    final db = await database;
    return db.query('cached_route_connections');
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}
