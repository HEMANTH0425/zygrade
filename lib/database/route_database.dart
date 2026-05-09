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
}
