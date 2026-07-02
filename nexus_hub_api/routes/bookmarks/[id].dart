import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/bookmark.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final db = DatabaseProvider.instance;
  final bookmarkId = int.tryParse(id);
  if (bookmarkId == null) {
    return Response(statusCode: HttpStatus.badRequest);
  }

  final existing = db.select(
    'SELECT * FROM bookmarks WHERE id = ?',
    [bookmarkId],
  );
  if (existing.isEmpty) {
    return Response(statusCode: HttpStatus.notFound);
  }

  switch (context.request.method) {
    case HttpMethod.get:
      final bookmark = Bookmark.fromRow(existing.first);
      final collectionIds = _collectionIdsFor(db, bookmarkId);
      return Response.json(
        body: bookmark.toJson(collectionIds: collectionIds),
      );

    case HttpMethod.put:
      final body = await context.request.json() as Map<String, dynamic>;
      final bookmark = Bookmark.fromRow(existing.first);
      final now = DateTime.now().millisecondsSinceEpoch;
      final title = body['title'] as String? ?? bookmark.title;
      final url = body['url'] as String? ?? bookmark.url;
      final tags =
          (body['tags'] as List<dynamic>?)?.cast<String>() ?? bookmark.tags;
      final category = body['category'] as String? ?? bookmark.category;
      final image = body['image'] as String? ?? bookmark.image;
      final sortOrder = body['sortOrder'] as int? ?? bookmark.sortOrder;

      db.execute(
        '''
        UPDATE bookmarks
        SET title = ?, url = ?, tags = ?, category = ?,
            image = ?, sort_order = ?, updated_at = ?
        WHERE id = ?
      ''',
        [
          title,
          url,
          tags.join(','),
          category,
          image,
          sortOrder,
          now,
          bookmarkId,
        ],
      );

      final collectionIds = _collectionIdsFor(db, bookmarkId);
      return Response.json(
        body: bookmark
            .copyWith(
              title: title,
              url: url,
              tags: tags,
              category: category,
              image: image,
              sortOrder: sortOrder,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
            )
            .toJson(collectionIds: collectionIds),
      );

    case HttpMethod.delete:
      db.execute('DELETE FROM bookmarks WHERE id = ?', [bookmarkId]);
      return Response(statusCode: HttpStatus.noContent);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

List<int> _collectionIdsFor(Database db, int bookmarkId) {
  final rows = db.select(
    '''
    SELECT collection_id FROM bookmark_collections
    WHERE bookmark_id = ?
  ''',
    [bookmarkId],
  );
  return rows.map((r) => r['collection_id'] as int).toList();
}
