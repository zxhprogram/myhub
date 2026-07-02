import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Local SQLite database for offline persistence and caching.
class LocalDatabase {
  LocalDatabase._();

  static Database? _db;
  static bool _useInMemory = false;

  /// Use an in-memory database for unit testing.
  ///
  /// Must be called before [instance] in tests to avoid platform
  /// channel dependencies such as path_provider.
  static void useInMemoryDatabaseForTesting() {
    _useInMemory = true;
    _db?.close();
    _db = null;
  }

  static Future<Database> get instance async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final String path;
    if (_useInMemory) {
      path = inMemoryDatabasePath;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = join(dir.path, 'nexus_hub.db');
    }
    return openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        tags TEXT NOT NULL,
        category TEXT NOT NULL,
        image TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        tag TEXT NOT NULL,
        priority TEXT NOT NULL,
        status TEXT NOT NULL,
        due_date INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE clipboard (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        type TEXT NOT NULL,
        file_path TEXT,
        mime_type TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE collections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmark_collections (
        bookmark_id INTEGER NOT NULL,
        collection_id INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (bookmark_id, collection_id)
      )
    ''');
  }

  static Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE bookmarks ADD COLUMN image TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE bookmarks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        'UPDATE bookmarks SET sort_order = id WHERE sort_order = 0',
      );
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE clipboard ADD COLUMN file_path TEXT');
      await db.execute('ALTER TABLE clipboard ADD COLUMN mime_type TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS collections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          sort_order INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS bookmark_collections (
          bookmark_id INTEGER NOT NULL,
          collection_id INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (bookmark_id, collection_id)
        )
      ''');
    }
  }
}
