import 'package:sqflite/sqflite.dart';

import '../models/bookmark_model.dart';
import '../models/collection_model.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// Repository for collection CRUD and bookmark associations with offline fallback.
class CollectionRepository {
  CollectionRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<CollectionModel>> fetchCollections({String? sort}) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/collections',
        queryParameters: sort != null ? {'sort': sort} : null,
      );
      final data = response.data ?? [];
      final collections = data
          .cast<Map<String, dynamic>>()
          .map(CollectionModel.fromJson)
          .toList();
      await _cacheCollections(collections);
      return collections;
    } catch (_) {
      return _loadCachedCollections(sort: sort);
    }
  }

  Future<CollectionModel> createCollection(String name) async {
    final now = DateTime.now();
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/collections',
        data: {'name': name},
      );
      final created = CollectionModel.fromJson(response.data!);
      await _insertLocalCollection(created);
      return created;
    } catch (_) {
      final local = CollectionModel(name: name, createdAt: now, updatedAt: now);
      await _insertLocalCollection(local);
      final cached = await _loadCachedCollections();
      final match = cached.where((c) => c.name == name).toList();
      return match.isNotEmpty ? match.first : local;
    }
  }

  Future<CollectionModel> updateCollection(int id, String name) async {
    final now = DateTime.now();
    try {
      final response = await _client.put<Map<String, dynamic>>(
        '/collections/$id',
        data: {'name': name},
      );
      final updated = CollectionModel.fromJson(response.data!);
      await _insertLocalCollection(updated);
      return updated;
    } catch (_) {
      final db = await LocalDatabase.instance;
      await db.update(
        'collections',
        {'name': name, 'updated_at': now.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );
      final cached = await _loadCachedCollections();
      return cached.firstWhere((c) => c.id == id);
    }
  }

  Future<void> deleteCollection(int id) async {
    try {
      await _client.delete<dynamic>('/collections/$id');
    } catch (_) {
      // Still clean local data even if API fails.
    }
    final db = await LocalDatabase.instance;
    await db.delete(
      'bookmark_collections',
      where: 'collection_id = ?',
      whereArgs: [id],
    );
    await db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<BookmarkModel>> getBookmarksInCollection(int collectionId) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/collections/$collectionId/bookmarks',
      );
      final data = response.data ?? [];
      final bookmarks = data
          .cast<Map<String, dynamic>>()
          .map(BookmarkModel.fromJson)
          .toList();
      return bookmarks;
    } catch (_) {
      return _loadCachedBookmarksInCollection(collectionId);
    }
  }

  Future<void> addBookmarksToCollection(
    int collectionId,
    List<int> bookmarkIds,
  ) async {
    if (bookmarkIds.isEmpty) return;
    try {
      await _client.post<dynamic>(
        '/collections/$collectionId/bookmarks',
        data: {'bookmarkIds': bookmarkIds},
      );
    } catch (_) {
      // Continue to update local cache.
    }
    final db = await LocalDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final bookmarkId in bookmarkIds) {
      try {
        await db.insert('bookmark_collections', {
          'bookmark_id': bookmarkId,
          'collection_id': collectionId,
          'created_at': now,
        });
      } catch (_) {
        // Ignore duplicate entries.
      }
    }
  }

  Future<void> removeBookmarksFromCollection(
    int collectionId,
    List<int> bookmarkIds,
  ) async {
    if (bookmarkIds.isEmpty) return;
    for (final bookmarkId in bookmarkIds) {
      try {
        await _client.delete<dynamic>(
          '/collections/$collectionId/bookmarks/$bookmarkId',
        );
      } catch (_) {
        // Continue to clean local cache.
      }
    }
    final db = await LocalDatabase.instance;
    for (final bookmarkId in bookmarkIds) {
      await db.delete(
        'bookmark_collections',
        where: 'collection_id = ? AND bookmark_id = ?',
        whereArgs: [collectionId, bookmarkId],
      );
    }
  }

  Future<int> countBookmarks(int collectionId) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count FROM bookmark_collections
      WHERE collection_id = ?
    ''',
      [collectionId],
    );
    return (rows.firstOrNull?['count'] as int?) ?? 0;
  }

  Future<void> _cacheCollections(List<CollectionModel> collections) async {
    final db = await LocalDatabase.instance;
    await db.delete('collections');
    for (final c in collections) {
      await _insertLocalCollection(c);
    }
  }

  Future<void> _insertLocalCollection(CollectionModel collection) async {
    final db = await LocalDatabase.instance;
    await db.insert('collections', {
      'id': collection.id,
      'name': collection.name,
      'sort_order': collection.sortOrder,
      'created_at': collection.createdAt.millisecondsSinceEpoch,
      'updated_at': collection.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<CollectionModel>> _loadCachedCollections({String? sort}) async {
    final db = await LocalDatabase.instance;
    final orderBy = _orderByClause(sort);
    final rows = await db.query('collections', orderBy: orderBy);
    return rows.map(_rowToCollection).toList();
  }

  CollectionModel _rowToCollection(Map<String, dynamic> row) {
    return CollectionModel(
      id: row['id'] as int?,
      name: row['name'] as String,
      sortOrder: (row['sort_order'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  String _orderByClause(String? sort) {
    switch (sort) {
      case 'name_asc':
        return 'name ASC';
      case 'name_desc':
        return 'name DESC';
      case 'created_asc':
        return 'created_at ASC';
      case 'created_desc':
        return 'created_at DESC';
      default:
        return 'sort_order ASC, name ASC';
    }
  }

  Future<List<BookmarkModel>> _loadCachedBookmarksInCollection(
    int collectionId,
  ) async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery(
      '''
      SELECT b.* FROM bookmarks b
      INNER JOIN bookmark_collections bc ON bc.bookmark_id = b.id
      WHERE bc.collection_id = ?
      ORDER BY b.sort_order ASC, b.updated_at DESC
    ''',
      [collectionId],
    );
    return rows
        .map(_rowToBookmark)
        .map((b) => b.copyWith(collectionIds: [collectionId]))
        .toList();
  }

  BookmarkModel _rowToBookmark(Map<String, dynamic> row) {
    return BookmarkModel(
      id: row['id'] as int,
      title: row['title'] as String,
      url: row['url'] as String,
      tags: (row['tags'] as String)
          .split(',')
          .where((t) => t.isNotEmpty)
          .toList(),
      category: row['category'] as String,
      image: (row['image'] as String?) ?? '',
      sortOrder: (row['sort_order'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}
