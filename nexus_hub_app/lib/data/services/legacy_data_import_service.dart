import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../data/models/bookmark_model.dart';
import '../../data/models/clipboard_item_model.dart';
import '../../data/models/collection_model.dart';
import '../../data/models/task_model.dart';
import 'clipboard_file_store.dart';
import 'local_database.dart';

/// One-time import of the legacy nexus_hub_api SQLite database into the app's
/// Hive store. The server no longer exists, so its data lives on here.
///
/// Only runs once (guarded by a shared_preferences flag) and only imports
/// tables whose Hive box is still empty, so freshly created local data is
/// never overwritten. Clipboard files referenced by relative `temp\...` paths
/// are copied into the [ClipboardFileStore] when they can be located.
class LegacyDataImportService {
  LegacyDataImportService._();

  static final LegacyDataImportService instance = LegacyDataImportService._();

  static const _flagKey = 'legacy_server_import_done';

  /// Overrides the automatic DB discovery (used by tests).
  String? dbPathOverride;

  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_flagKey) ?? false) return;

    try {
      final dbPath = _locateDatabase();
      if (dbPath == null) return;
      await _importFrom(dbPath);
    } catch (_) {
      // Best-effort: leave the flag unset so a transient failure retries on
      // the next launch.
      return;
    }
    await prefs.setBool(_flagKey, true);
  }

  String? _locateDatabase() {
    if (dbPathOverride != null) {
      return File(dbPathOverride!).existsSync() ? dbPathOverride : null;
    }
    final env = Platform.environment['NEXUS_HUB_DB'];
    if (env != null && File(env).existsSync()) return env;

    final cwd = Directory.current.path;
    final candidates = [
      p.join(cwd, 'nexus_hub_api', 'nexus_hub.db'),
      p.join(cwd, '..', 'nexus_hub_api', 'nexus_hub.db'),
      p.join(p.dirname(Directory.current.path), 'nexus_hub_api', 'nexus_hub.db'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  Future<void> _importFrom(String dbPath) async {
    final db = sqlite3.open(dbPath, mode: OpenMode.readOnly);
    try {
      final tasksBox = await LocalDatabase.box('tasks');
      if (tasksBox.isEmpty) {
        for (final row in db.select('SELECT * FROM tasks')) {
          final task = _taskFromRow(row);
          tasksBox.put(task.id!, task.toJson());
        }
      }

      final bookmarksBox = await LocalDatabase.box('bookmarks');
      final bookmarkCollectionsBox =
          await LocalDatabase.box('bookmark_collections');
      final collectionsBox = await LocalDatabase.box('collections');

      if (collectionsBox.isEmpty) {
        for (final row in db.select('SELECT * FROM collections')) {
          final collection = _collectionFromRow(row);
          collectionsBox.put(collection.id!, collection.toJson());
        }
      }

      if (bookmarksBox.isEmpty) {
        final collectionsByBookmark = <int, List<int>>{};
        for (final row in db.select('SELECT * FROM bookmark_collections')) {
          final bookmarkId = row['bookmark_id'] as int;
          final collectionId = row['collection_id'] as int;
          collectionsByBookmark
              .putIfAbsent(bookmarkId, () => [])
              .add(collectionId);
          await bookmarkCollectionsBox.put('$bookmarkId:$collectionId', {
            'bookmark_id': bookmarkId,
            'collection_id': collectionId,
            'created_at': row['created_at'] as int,
          });
        }
        for (final row in db.select('SELECT * FROM bookmarks')) {
          final bookmark = _bookmarkFromRow(
            row,
            collectionsByBookmark[row['id'] as int] ?? const [],
          );
          bookmarksBox.put(bookmark.id!, bookmark.toJson());
        }
      }

      final clipboardBox = await LocalDatabase.box('clipboard');
      if (clipboardBox.isEmpty) {
        final fileStore = ClipboardFileStore();
        for (final row in db.select('SELECT * FROM clipboard')) {
          final item = await _clipboardItemFromRow(row, fileStore);
          clipboardBox.put(item.id!, item.toJson());
        }
      }
    } finally {
      db.dispose();
    }
  }

  TaskModel _taskFromRow(Map<String, Object?> row) {
    return TaskModel(
      id: row['id'] as int,
      title: row['title'] as String,
      description: (row['description'] as String?) ?? '',
      tag: (row['tag'] as String?) ?? '',
      priority: (row['priority'] as String?) ?? 'medium',
      status: (row['status'] as String?) ?? 'todo',
      dueDate: row['due_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['due_date'] as int)
          : null,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  CollectionModel _collectionFromRow(Map<String, Object?> row) {
    return CollectionModel(
      id: row['id'] as int,
      name: row['name'] as String,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  BookmarkModel _bookmarkFromRow(
    Map<String, Object?> row,
    List<int> collectionIds,
  ) {
    return BookmarkModel(
      id: row['id'] as int,
      title: row['title'] as String,
      url: row['url'] as String,
      tags: ((row['tags'] as String?) ?? '')
          .split(',')
          .where((t) => t.isNotEmpty)
          .toList(),
      category: (row['category'] as String?) ?? '',
      image: (row['image'] as String?) ?? '',
      sortOrder: (row['sort_order'] as int?) ?? 0,
      collectionIds: collectionIds,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Future<ClipboardItemModel> _clipboardItemFromRow(
    Map<String, Object?> row,
    ClipboardFileStore fileStore,
  ) async {
    var filePath = row['file_path'] as String?;
    if (filePath != null && filePath.isNotEmpty) {
      filePath = await _resolveClipboardFile(filePath, fileStore);
    }
    return ClipboardItemModel(
      id: row['id'] as int,
      content: (row['content'] as String?) ?? '',
      type: (row['type'] as String?) ?? 'text',
      filePath: filePath,
      mimeType: row['mime_type'] as String?,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  /// The server stored paths relative to its upload dir (`temp\<name>`).
  /// Locates the file by basename in known temp directories and copies it
  /// into the local file store; unresolved paths are kept as-is.
  Future<String> _resolveClipboardFile(
    String storedPath,
    ClipboardFileStore fileStore,
  ) async {
    if (!storedPath.startsWith('temp')) return storedPath;

    final basename = p.basename(storedPath);
    for (final dir in _candidateTempDirs()) {
      if (!dir.existsSync()) continue;
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path) == basename) {
          return fileStore.importFile(entity.path);
        }
      }
    }
    return storedPath;
  }

  List<Directory> _candidateTempDirs() {
    final cwd = Directory.current.path;
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final dbDirCandidates = [
      p.join(cwd, 'nexus_hub_api'),
      p.join(cwd, '..', 'nexus_hub_api'),
    ];
    return [
      Directory(p.join(exeDir, 'temp')),
      Directory(p.join(cwd, 'build', 'windows', 'x64', 'runner', 'Debug', 'temp')),
      Directory(
          p.join(cwd, 'build', 'windows', 'x64', 'runner', 'Release', 'temp')),
      for (final base in dbDirCandidates) ...[
        Directory(p.join(base, 'temp')),
        Directory(p.join(base, '.dart_frog', 'temp')),
        Directory(p.join(base, 'build', 'temp')),
      ],
    ];
  }
}
