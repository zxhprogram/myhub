import 'package:sqflite/sqflite.dart';

import '../models/bookmark_model.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// Repository for bookmark CRUD operations with offline fallback.
class BookmarkRepository {
  BookmarkRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<BookmarkModel>> fetchBookmarks({String? query}) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/bookmarks',
        queryParameters: query != null ? {'q': query} : null,
      );
      final data = response.data ?? [];
      final bookmarks = data
          .cast<Map<String, dynamic>>()
          .map(BookmarkModel.fromJson)
          .toList();
      await _cacheBookmarks(bookmarks);
      await _cacheBookmarkCollections(bookmarks);
      return bookmarks;
    } catch (_) {
      return _loadCachedBookmarks(query: query);
    }
  }

  Future<BookmarkModel> createBookmark(BookmarkModel bookmark) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/bookmarks',
        data: bookmark.toJson(),
      );
      final created = BookmarkModel.fromJson(response.data!);
      await _insertLocal(created);
      return created;
    } catch (_) {
      final local = bookmark.copyWith(id: null);
      await _insertLocal(local);
      return local;
    }
  }

  Future<BookmarkModel> updateBookmark(BookmarkModel bookmark) async {
    final id = bookmark.id;
    if (id == null) throw ArgumentError('Bookmark must have an id');

    try {
      final response = await _client.put<Map<String, dynamic>>(
        '/bookmarks/$id',
        data: bookmark.toJson(),
      );
      final updated = BookmarkModel.fromJson(response.data!);
      await _insertLocal(updated);
      await _cacheBookmarkCollections([updated]);
      return updated;
    } catch (_) {
      final db = await LocalDatabase.instance;
      await db.update(
        'bookmarks',
        {
          'title': bookmark.title,
          'url': bookmark.url,
          'tags': bookmark.tags.join(','),
          'category': bookmark.category,
          'image': bookmark.image,
          'sort_order': bookmark.sortOrder,
          'updated_at': bookmark.updatedAt.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await _cacheBookmarkCollections([bookmark]);
      return bookmark;
    }
  }

  Future<void> deleteBookmark(int id) async {
    try {
      await _client.delete<dynamic>('/bookmarks/$id');
    } catch (_) {
      // Continue to clean local data even if API fails.
    }
    final db = await LocalDatabase.instance;
    await db.delete(
      'bookmark_collections',
      where: 'bookmark_id = ?',
      whereArgs: [id],
    );
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  /// Fetches metadata (title, image, favicon) for a URL via the preview API.
  Future<BookmarkPreview> fetchPreview(String url) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/bookmarks/preview',
      queryParameters: {'url': url},
    );
    return BookmarkPreview.fromJson(response.data!);
  }

  Future<void> _cacheBookmarks(List<BookmarkModel> bookmarks) async {
    final db = await LocalDatabase.instance;
    await db.delete('bookmarks');
    for (final b in bookmarks) {
      await _insertLocal(b);
    }
  }

  Future<void> _cacheBookmarkCollections(List<BookmarkModel> bookmarks) async {
    final db = await LocalDatabase.instance;
    final bookmarkIds = bookmarks.map((b) => b.id).whereType<int>().toList();
    if (bookmarkIds.isEmpty) return;

    final placeholders = List.filled(bookmarkIds.length, '?').join(',');
    await db.rawDelete('''
      DELETE FROM bookmark_collections
      WHERE bookmark_id IN ($placeholders)
    ''', bookmarkIds);

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final bookmark in bookmarks) {
      for (final collectionId in bookmark.collectionIds) {
        try {
          await db.insert('bookmark_collections', {
            'bookmark_id': bookmark.id,
            'collection_id': collectionId,
            'created_at': now,
          });
        } catch (_) {
          // Ignore duplicate entries.
        }
      }
    }
  }

  Future<void> _insertLocal(BookmarkModel bookmark) async {
    final db = await LocalDatabase.instance;
    await db.insert('bookmarks', {
      'id': bookmark.id,
      'title': bookmark.title,
      'url': bookmark.url,
      'tags': bookmark.tags.join(','),
      'category': bookmark.category,
      'image': bookmark.image,
      'sort_order': bookmark.sortOrder,
      'created_at': bookmark.createdAt.millisecondsSinceEpoch,
      'updated_at': bookmark.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<BookmarkModel>> _loadCachedBookmarks({String? query}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'bookmarks',
      where: query != null ? 'title LIKE ?' : null,
      whereArgs: query != null ? ['%$query%'] : null,
      orderBy: 'sort_order ASC',
    );
    return rows.map(_rowToModel).toList();
  }

  BookmarkModel _rowToModel(Map<String, dynamic> row) {
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

  /// Reorders bookmarks according to the provided list of ids.
  /// Optimistically updates local storage and falls back to it on API errors.
  Future<List<BookmarkModel>> reorder(List<int> ids) async {
    try {
      final response = await _client.put<Map<String, dynamic>>(
        '/bookmarks',
        data: {'order': ids},
      );
      final data =
          response.data!['order'] as List<dynamic>? ??
          response.data! as List<dynamic>;
      final bookmarks = data
          .cast<Map<String, dynamic>>()
          .map(BookmarkModel.fromJson)
          .toList();
      await _cacheBookmarks(bookmarks);
      return bookmarks;
    } catch (_) {
      final db = await LocalDatabase.instance;
      for (var i = 0; i < ids.length; i++) {
        await db.update(
          'bookmarks',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [ids[i]],
        );
      }
      return _loadCachedBookmarks();
    }
  }
}

/// Preview metadata returned by the `/bookmarks/preview` endpoint.
class BookmarkPreview {
  const BookmarkPreview({this.title = '', this.image = '', this.favicon = ''});

  final String title;
  final String image;
  final String favicon;

  factory BookmarkPreview.fromJson(Map<String, dynamic> json) {
    return BookmarkPreview(
      title: (json['title'] as String?) ?? '',
      image: (json['image'] as String?) ?? '',
      favicon: (json['favicon'] as String?) ?? '',
    );
  }
}
