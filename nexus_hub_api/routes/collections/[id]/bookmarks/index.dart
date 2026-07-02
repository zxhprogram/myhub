import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../../lib/database.dart';
import '../../../../lib/models/bookmark.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final db = DatabaseProvider.instance;
  final collectionId = int.tryParse(id);
  if (collectionId == null) {
    return Response(statusCode: HttpStatus.badRequest);
  }

  final collectionExists = db.select(
    'SELECT 1 FROM collections WHERE id = ?',
    [collectionId],
  );
  if (collectionExists.isEmpty) {
    return Response(statusCode: HttpStatus.notFound);
  }

  switch (context.request.method) {
    case HttpMethod.get:
      final rows = db.select(
        '''
        SELECT b.* FROM bookmarks b
        INNER JOIN bookmark_collections bc ON bc.bookmark_id = b.id
        WHERE bc.collection_id = ?
        ORDER BY b.sort_order ASC, b.updated_at DESC
      ''',
        [collectionId],
      ).cast<Row>();
      final bookmarks = rows.map(Bookmark.fromRow).toList();
      final json = _attachCollectionIds(db, bookmarks);
      return Response.json(body: json);

    case HttpMethod.post:
      final body = await context.request.json() as Map<String, dynamic>;
      final bookmarkIds = (body['bookmarkIds'] as List<dynamic>?)
              ?.cast<int>() ??
          <int>[];
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final bookmarkId in bookmarkIds) {
        try {
          db.execute(
            '''
            INSERT INTO bookmark_collections
              (bookmark_id, collection_id, created_at)
            VALUES (?, ?, ?)
          ''',
            [bookmarkId, collectionId, now],
          );
        } on SqliteException {
          // Ignore duplicate entries.
        }
      }

      return Response.json(
        body: {'added': bookmarkIds.length},
        statusCode: HttpStatus.created,
      );

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

List<Map<String, dynamic>> _attachCollectionIds(
  Database db,
  List<Bookmark> bookmarks,
) {
  if (bookmarks.isEmpty) return [];

  final ids = bookmarks.map((b) => b.id).whereType<int>().toList();
  final placeholders = List.filled(ids.length, '?').join(',');
  final rows = db.select(
    '''
    SELECT bookmark_id, collection_id FROM bookmark_collections
    WHERE bookmark_id IN ($placeholders)
  ''',
    ids,
  );

  final mapping = <int, List<int>>{};
  for (final row in rows) {
    final bookmarkId = row['bookmark_id'] as int;
    final collectionId = row['collection_id'] as int;
    mapping.putIfAbsent(bookmarkId, () => []).add(collectionId);
  }

  return bookmarks
      .map(
        (b) => b.toJson(
          collectionIds: mapping[b.id] ?? [],
        ),
      )
      .toList();
}
