import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Singleton database provider for the Nexus Hub API.
class DatabaseProvider {
  DatabaseProvider._();

  static Database? _db;

  static Database get instance {
    _db ??= _open();
    return _db!;
  }

  static Database _open() {
    final dbPath = Platform.environment['NEXUS_HUB_DB'] ?? 'nexus_hub.db';
    final db = sqlite3.open(dbPath);
    _migrate(db);
    return db;
  }

  static void _migrate(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '',
        category TEXT NOT NULL DEFAULT '',
        image TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    // Backfill the image column for databases created before it existed.
    try {
      db.execute(
        'ALTER TABLE bookmarks ADD COLUMN image TEXT NOT NULL DEFAULT ""',
      );
    } on SqliteException {
      // Column already exists — safe to ignore.
    }

    // Backfill the sort_order column for databases created before it existed.
    try {
      db.execute(
        'ALTER TABLE bookmarks ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
      );
      db.execute('''
        UPDATE bookmarks SET sort_order = id WHERE sort_order = 0
      ''');
    } on SqliteException {
      // Column already exists — safe to ignore.
    }

    db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        tag TEXT NOT NULL DEFAULT '',
        priority TEXT NOT NULL DEFAULT 'medium',
        status TEXT NOT NULL DEFAULT 'todo',
        due_date INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS clipboard (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'text',
        file_path TEXT,
        mime_type TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    // Backfill file_path and mime_type columns for databases created before
    // they existed.
    try {
      db.execute('ALTER TABLE clipboard ADD COLUMN file_path TEXT');
      db.execute('ALTER TABLE clipboard ADD COLUMN mime_type TEXT');
    } on SqliteException {
      // Columns already exist — safe to ignore.
    }

    db.execute('''
      CREATE TABLE IF NOT EXISTS rss_feeds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        category TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS rss_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        feed_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        url TEXT NOT NULL,
        published_at INTEGER NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (feed_id) REFERENCES rss_feeds (id)
      );
    ''');

    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_bookmarks_category ON bookmarks(category);
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
    ''');
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_clipboard_created ON clipboard(created_at);
    ''');
  }

  static void close() {
    _db?.dispose();
    _db = null;
  }
}
