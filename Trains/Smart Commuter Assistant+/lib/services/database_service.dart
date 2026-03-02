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
      version: 1,
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
      },
    );
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

  Future<void> upsertDefaultPreferences(int userId) async {
    final db = await database;
    await db.insert(
      'user_preferences',
      {'user_id': userId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }
}
