import '../models/bookmark_model.dart';
import '../services/api_client.dart';
import '../services/local_database.dart';

/// Repository for bookmark CRUD operations with offline fallback.
class BookmarkRepository {
  BookmarkRepository({ApiClient? client})
      : _client = client ?? ApiClient();

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

  Future<void> _cacheBookmarks(List<BookmarkModel> bookmarks) async {
    final db = await LocalDatabase.instance;
    await db.delete('bookmarks');
    for (final b in bookmarks) {
      await _insertLocal(b);
    }
  }

  Future<void> _insertLocal(BookmarkModel bookmark) async {
    final db = await LocalDatabase.instance;
    await db.insert('bookmarks', {
      'title': bookmark.title,
      'url': bookmark.url,
      'tags': bookmark.tags.join(','),
      'category': bookmark.category,
      'created_at': bookmark.createdAt.millisecondsSinceEpoch,
      'updated_at': bookmark.updatedAt.millisecondsSinceEpoch,
    });
  }

  Future<List<BookmarkModel>> _loadCachedBookmarks({String? query}) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'bookmarks',
      where: query != null ? 'title LIKE ?' : null,
      whereArgs: query != null ? ['%$query%'] : null,
      orderBy: 'updated_at DESC',
    );
    return rows.map(_rowToModel).toList();
  }

  BookmarkModel _rowToModel(Map<String, dynamic> row) {
    return BookmarkModel(
      id: row['id'] as int,
      title: row['title'] as String,
      url: row['url'] as String,
      tags: (row['tags'] as String).split(',').where((t) => t.isNotEmpty).toList(),
      category: row['category'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }
}

extension on BookmarkModel {
  BookmarkModel copyWith({int? id}) => BookmarkModel(
        id: id ?? this.id,
        title: title,
        url: url,
        tags: tags,
        category: category,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
