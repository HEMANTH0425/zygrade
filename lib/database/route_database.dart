import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class RouteDatabase {
  static final RouteDatabase instance = RouteDatabase._init();
  static Database? _database;

  RouteDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('routes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
CREATE TABLE hex_routes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  pointCount INTEGER NOT NULL,
  rawData TEXT NOT NULL,
  createdAt TEXT NOT NULL
)
''');
    await db.execute('''
CREATE TABLE catch_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  timestamp INTEGER NOT NULL
)
''');
  }

  Future<int> insertRoute(String name, int pointCount, List<Map<String, dynamic>> points) async {
    final db = await instance.database;
    final jsonPoints = jsonEncode(points);
    return await db.insert('hex_routes', {
      'name': name,
      'pointCount': pointCount,
      'rawData': jsonPoints,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAllRoutes() async {
    final db = await instance.database;
    return await db.query('hex_routes', orderBy: 'createdAt DESC');
  }

  Future<int> deleteRoute(int id) async {
    final db = await instance.database;
    return await db.delete('hex_routes', where: 'id = ?', whereArgs: [id]);
  }

  // ── Catch Ledger (Phase 5) ──────────────────────────────────────────────────
  Future<void> insertCatch(String username, int timestamp) async {
    final db = await instance.database;
    await db.insert('catch_logs', {
      'username': username,
      'timestamp': timestamp,
    });
    // Auto-cleanup logs older than 7 days
    final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await db.delete('catch_logs', where: 'timestamp < ?', whereArgs: [sevenDaysAgo]);
  }

  Future<int> getDailyCatches(String username) async {
    final db = await instance.database;
    final oneDayAgo = DateTime.now().millisecondsSinceEpoch - 86400000;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM catch_logs WHERE username = ? AND timestamp > ?',
      [username, oneDayAgo],
    );
    
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
