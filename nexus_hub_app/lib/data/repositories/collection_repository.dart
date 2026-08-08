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
      final box = await LocalDatabase.box('collections');
      final existing = box.get(id);
      if (existing != null) {
        final record = Map<String, dynamic>.from(existing as Map);
        record['name'] = name;
        record['updatedAt'] = now.toIso8601String();
        await box.put(id, record);
      }
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
    // Remove all bookmark-collection associations for this collection.
    final bcBox = await LocalDatabase.box('bookmark_collections');
    final keysToDelete = <dynamic>[];
    for (final key in bcBox.keys) {
      final record = Map<String, dynamic>.from(bcBox.get(key) as Map);
      if (record['collection_id'] == id) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await bcBox.delete(key);
    }

    final box = await LocalDatabase.box('collections');
    await box.delete(id);
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
    final box = await LocalDatabase.box('bookmark_collections');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final bookmarkId in bookmarkIds) {
      final bcKey = '$bookmarkId:$collectionId';
      await box.put(bcKey, {
        'bookmark_id': bookmarkId,
        'collection_id': collectionId,
        'created_at': now,
      });
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
    final box = await LocalDatabase.box('bookmark_collections');
    for (final bookmarkId in bookmarkIds) {
      final bcKey = '$bookmarkId:$collectionId';
      await box.delete(bcKey);
    }
  }

  Future<int> countBookmarks(int collectionId) async {
    final box = await LocalDatabase.box('bookmark_collections');
    var count = 0;
    for (final value in box.values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['collection_id'] == collectionId) {
        count++;
      }
    }
    return count;
  }

  Future<void> _cacheCollections(List<CollectionModel> collections) async {
    final box = await LocalDatabase.box('collections');
    await box.clear();
    for (final c in collections) {
      await _insertLocalCollection(c);
    }
  }

  Future<void> _insertLocalCollection(CollectionModel collection) async {
    final box = await LocalDatabase.box('collections');
    final id = collection.id;
    if (id != null) {
      await box.put(id, collection.toJson());
    } else {
      await box.add(collection.toJson());
    }
  }

  Future<List<CollectionModel>> _loadCachedCollections({String? sort}) async {
    final box = await LocalDatabase.box('collections');
    final rows = box.values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    _sortCollections(rows, sort);
    return rows.map(CollectionModel.fromJson).toList();
  }

  void _sortCollections(List<Map<String, dynamic>> rows, String? sort) {
    switch (sort) {
      case 'name_asc':
        rows.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      case 'name_desc':
        rows.sort((a, b) => (b['name'] as String).compareTo(a['name'] as String));
      case 'created_asc':
        rows.sort((a, b) {
          final aDate = DateTime.parse(a['createdAt'] as String);
          final bDate = DateTime.parse(b['createdAt'] as String);
          return aDate.compareTo(bDate);
        });
      case 'created_desc':
        rows.sort((a, b) {
          final aDate = DateTime.parse(a['createdAt'] as String);
          final bDate = DateTime.parse(b['createdAt'] as String);
          return bDate.compareTo(aDate);
        });
      default:
        rows.sort((a, b) {
          final aOrder = (a['sortOrder'] as int?) ?? 0;
          final bOrder = (b['sortOrder'] as int?) ?? 0;
          final cmp = aOrder.compareTo(bOrder);
          if (cmp != 0) return cmp;
          return (a['name'] as String).compareTo(b['name'] as String);
        });
    }
  }

  Future<List<BookmarkModel>> _loadCachedBookmarksInCollection(
    int collectionId,
  ) async {
    final bcBox = await LocalDatabase.box('bookmark_collections');
    final bookmarkBox = await LocalDatabase.box('bookmarks');

    // Collect bookmark IDs associated with this collection.
    final bookmarkIds = <int>[];
    for (final value in bcBox.values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['collection_id'] == collectionId) {
        bookmarkIds.add(record['bookmark_id'] as int);
      }
    }

    // Fetch the bookmark records and sort by sortOrder ASC, updatedAt DESC.
    final bookmarks = <Map<String, dynamic>>[];
    for (final id in bookmarkIds) {
      final record = bookmarkBox.get(id);
      if (record != null) {
        bookmarks.add(Map<String, dynamic>.from(record as Map));
      }
    }
    bookmarks.sort((a, b) {
      final aOrder = (a['sortOrder'] as int?) ?? 0;
      final bOrder = (b['sortOrder'] as int?) ?? 0;
      final cmp = aOrder.compareTo(bOrder);
      if (cmp != 0) return cmp;
      final aDate = DateTime.parse(a['updatedAt'] as String);
      final bDate = DateTime.parse(b['updatedAt'] as String);
      return bDate.compareTo(aDate);
    });

    return bookmarks
        .map(BookmarkModel.fromJson)
        .map((b) => b.copyWith(collectionIds: [collectionId]))
        .toList();
  }
}
