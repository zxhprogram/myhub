import '../models/bookmark_model.dart';
import '../models/collection_model.dart';
import '../services/local_database.dart';

/// Repository for collection CRUD and bookmark associations backed by the
/// local Hive store.
class CollectionRepository {
  CollectionRepository();

  Future<List<CollectionModel>> fetchCollections({String? sort}) async {
    final rows = (await LocalDatabase.box('collections'))
        .values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    _sortCollections(rows, sort);
    return rows.map(CollectionModel.fromJson).toList();
  }

  Future<CollectionModel> createCollection(String name) async {
    // Mimic the former server-side UNIQUE(name) constraint.
    final existing = await _findByName(name);
    if (existing != null) {
      throw StateError('A collection named "$name" already exists');
    }
    final now = DateTime.now();
    final local = CollectionModel(name: name, createdAt: now, updatedAt: now);
    final box = await LocalDatabase.box('collections');
    final id = await box.add(local.toJson());
    final created = local.copyWith(id: id);
    await box.put(id, created.toJson());
    return created;
  }

  Future<CollectionModel> updateCollection(int id, String name) async {
    final duplicate = await _findByName(name);
    if (duplicate != null && duplicate.id != id) {
      throw StateError('A collection named "$name" already exists');
    }
    final box = await LocalDatabase.box('collections');
    final existing = box.get(id);
    if (existing == null) {
      throw StateError('Collection $id does not exist');
    }
    final record = Map<String, dynamic>.from(existing as Map);
    record['name'] = name;
    record['updatedAt'] = DateTime.now().toIso8601String();
    await box.put(id, record);
    return CollectionModel.fromJson(record);
  }

  Future<void> deleteCollection(int id) async {
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

  Future<List<BookmarkModel>> getBookmarksInCollection(
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

  Future<void> addBookmarksToCollection(
    int collectionId,
    List<int> bookmarkIds,
  ) async {
    if (bookmarkIds.isEmpty) return;
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

  Future<CollectionModel?> _findByName(String name) async {
    for (final value in (await LocalDatabase.box('collections')).values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['name'] == name) {
        return CollectionModel.fromJson(record);
      }
    }
    return null;
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
}
