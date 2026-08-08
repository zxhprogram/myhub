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
      final box = await LocalDatabase.box('bookmarks');
      final existing = box.get(id);
      if (existing != null) {
        final record = Map<String, dynamic>.from(existing as Map);
        record
          ..['title'] = bookmark.title
          ..['url'] = bookmark.url
          ..['tags'] = bookmark.tags
          ..['category'] = bookmark.category
          ..['image'] = bookmark.image
          ..['sortOrder'] = bookmark.sortOrder
          ..['updatedAt'] = bookmark.updatedAt.toIso8601String();
        await box.put(id, record);
      }
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
    final bcBox = await LocalDatabase.box('bookmark_collections');
    final keysToDelete = <dynamic>[];
    for (final key in bcBox.keys) {
      final record = Map<String, dynamic>.from(bcBox.get(key) as Map);
      if (record['bookmark_id'] == id) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await bcBox.delete(key);
    }

    final box = await LocalDatabase.box('bookmarks');
    await box.delete(id);
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
    final box = await LocalDatabase.box('bookmarks');
    await box.clear();
    for (final b in bookmarks) {
      await _insertLocal(b);
    }
  }

  Future<void> _cacheBookmarkCollections(List<BookmarkModel> bookmarks) async {
    final box = await LocalDatabase.box('bookmark_collections');
    final bookmarkIds = bookmarks.map((b) => b.id).whereType<int>().toList();
    if (bookmarkIds.isEmpty) return;

    // Delete existing associations for these bookmarks.
    final keysToDelete = <dynamic>[];
    for (final key in box.keys) {
      final record = Map<String, dynamic>.from(box.get(key) as Map);
      if (bookmarkIds.contains(record['bookmark_id'])) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await box.delete(key);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final bookmark in bookmarks) {
      for (final collectionId in bookmark.collectionIds) {
        final bcKey = '${bookmark.id}:$collectionId';
        await box.put(bcKey, {
          'bookmark_id': bookmark.id,
          'collection_id': collectionId,
          'created_at': now,
        });
      }
    }
  }

  Future<void> _insertLocal(BookmarkModel bookmark) async {
    final box = await LocalDatabase.box('bookmarks');
    final id = bookmark.id;
    if (id != null) {
      await box.put(id, bookmark.toJson());
    } else {
      await box.add(bookmark.toJson());
    }
  }

  Future<List<BookmarkModel>> _loadCachedBookmarks({String? query}) async {
    final box = await LocalDatabase.box('bookmarks');
    final rows = box.values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
          if (query == null) return true;
          final title = (row['title'] as String?) ?? '';
          return title.toLowerCase().contains(query.toLowerCase());
        })
        .toList();
    rows.sort((a, b) {
      final aOrder = (a['sortOrder'] as int?) ?? 0;
      final bOrder = (b['sortOrder'] as int?) ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return rows.map(BookmarkModel.fromJson).toList();
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
      final box = await LocalDatabase.box('bookmarks');
      for (var i = 0; i < ids.length; i++) {
        final existing = box.get(ids[i]);
        if (existing != null) {
          final record = Map<String, dynamic>.from(existing as Map);
          record['sortOrder'] = i;
          await box.put(ids[i], record);
        }
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
