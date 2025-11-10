import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseHelper {
  // Singleton pattern
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    // FFI initialization for Windows
    if (Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'local_database.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE usuarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE productos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL,
        precio REAL NOT NULL
      )
    ''');
  }

  // --- Funciones de autenticación ---

  Future<int> crearUsuario(String email, String password) async {
    final db = await instance.database;
    // Un ejemplo simple de hashing - considera usar una librería más robusta para producción
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);

    return await db.insert('usuarios', {
      'email': email,
      'password': digest.toString(),
    });
  }

  Future<Map<String, dynamic>?> loginUsuario(String email, String password) async {
    final db = await instance.database;
    // Un ejemplo simple de hashing - considera usar una librería más robusta para producción
    var bytes = utf8.encode(password);
    var digest = sha256.convert(bytes);

    var res = await db.query(
      'usuarios',
      where: 'email = ? AND password = ?',
      whereArgs: [email, digest.toString()],
    );

    if (res.isNotEmpty) {
      return res.first;
    }
    return null;
  }

  // --- Funciones de productos ---

  Future<List<Map<String, dynamic>>> getProductos() async {
    final db = await instance.database;
    return await db.query('productos');
  }
}
