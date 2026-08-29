import '../models/bookmark_model.dart';
import '../services/local_database.dart';
import '../services/url_preview_service.dart';

/// Repository for bookmark CRUD operations backed by the local Hive store.
class BookmarkRepository {
  BookmarkRepository({UrlPreviewService? previewService})
      : _previewService = previewService ?? UrlPreviewService();

  final UrlPreviewService _previewService;

  Future<List<BookmarkModel>> fetchBookmarks({String? query}) async {
    final rows = (await LocalDatabase.box('bookmarks'))
        .values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) {
          if (query == null || query.isEmpty) return true;
          final title = (row['title'] as String?) ?? '';
          return title.toLowerCase().contains(query.toLowerCase());
        })
        .toList();
    rows.sort((a, b) {
      final aOrder = (a['sortOrder'] as int?) ?? 0;
      final bOrder = (b['sortOrder'] as int?) ?? 0;
      final cmp = aOrder.compareTo(bOrder);
      if (cmp != 0) return cmp;
      final aUpdated = DateTime.parse(a['updatedAt'] as String);
      final bUpdated = DateTime.parse(b['updatedAt'] as String);
      return bUpdated.compareTo(aUpdated);
    });
    final collectionIds = await _collectionIdsByBookmark();
    return rows
        .map((row) => BookmarkModel.fromJson(row))
        .map((b) => b.copyWith(collectionIds: collectionIds[b.id] ?? const []))
        .toList();
  }

  Future<BookmarkModel> createBookmark(BookmarkModel bookmark) async {
    final box = await LocalDatabase.box('bookmarks');
    final id = await box.add(bookmark.copyWith(id: null).toJson());
    final created = bookmark.copyWith(id: id);
    await box.put(id, created.toJson());
    return created;
  }

  Future<BookmarkModel> updateBookmark(BookmarkModel bookmark) async {
    final id = bookmark.id;
    if (id == null) throw ArgumentError('Bookmark must have an id');

    final updated = bookmark.copyWith(updatedAt: DateTime.now());
    final box = await LocalDatabase.box('bookmarks');
    await box.put(id, updated.toJson());
    return updated;
  }

  Future<void> deleteBookmark(int id) async {
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

  /// Fetches metadata (title, image, favicon) for a URL by scraping the page
  /// directly (previously handled by the backend preview endpoint).
  Future<BookmarkPreview> fetchPreview(String url) {
    return _previewService.fetch(url);
  }

  /// Reorders bookmarks according to the provided list of ids by writing
  /// positional sort orders.
  Future<List<BookmarkModel>> reorder(List<int> ids) async {
    final box = await LocalDatabase.box('bookmarks');
    for (var i = 0; i < ids.length; i++) {
      final existing = box.get(ids[i]);
      if (existing != null) {
        final record = Map<String, dynamic>.from(existing as Map);
        record['sortOrder'] = i;
        await box.put(ids[i], record);
      }
    }
    return fetchBookmarks();
  }

  Future<Map<int, List<int>>> _collectionIdsByBookmark() async {
    final bcBox = await LocalDatabase.box('bookmark_collections');
    final result = <int, List<int>>{};
    for (final value in bcBox.values) {
      final record = Map<String, dynamic>.from(value as Map);
      final bookmarkId = record['bookmark_id'] as int;
      final collectionId = record['collection_id'] as int;
      result.putIfAbsent(bookmarkId, () => []).add(collectionId);
    }
    return result;
  }
}
