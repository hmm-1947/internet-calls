import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class HomeCache {
  static final HomeCache _instance = HomeCache._internal();
  factory HomeCache() => _instance;
  HomeCache._internal();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'home_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)',
        );
      },
    );
    return _db!;
  }

  Future<void> setJson(String key, dynamic value) async {
    final db = await _database;
    await db.insert(
      'kv',
      {
        'key': key,
        'value': jsonEncode(value),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getJson(String key) async {
    final db = await _database;
    final rows = await db.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    try {
      return jsonDecode(rows.first['value'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear(String key) async {
    final db = await _database;
    await db.delete('kv', where: 'key = ?', whereArgs: [key]);
  }
}
