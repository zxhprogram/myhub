import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/bookmark.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = DatabaseProvider.instance;

  switch (context.request.method) {
    case HttpMethod.get:
      final query = context.request.uri.queryParameters['q'];
      final rows = db
          .select(
            '''
        SELECT * FROM bookmarks
        WHERE (?1 IS NULL OR title LIKE '%' || ?1 || '%')
        ORDER BY sort_order ASC, updated_at DESC
      ''',
            [query],
          )
          .cast<Row>();
      final bookmarks = rows
          .map(Bookmark.fromRow)
          .map((b) => b.toJson())
          .toList();
      return Response.json(body: bookmarks);

    case HttpMethod.post:
      final body = await context.request.json() as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      final title = body['title'] as String? ?? '';
      final url = body['url'] as String? ?? '';
      final tags =
          (body['tags'] as List<dynamic>?)?.cast<String>() ?? <String>[];
      final category = body['category'] as String? ?? '';
      final image = body['image'] as String? ?? '';
      final sortOrder = body['sortOrder'] as int? ?? now;

      db.execute(
        '''
        INSERT INTO bookmarks
          (title, url, tags, category, image, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
        [title, url, tags.join(','), category, image, sortOrder, now, now],
      );

      final id = db.lastInsertRowId;
      return Response.json(
        statusCode: HttpStatus.created,
        body: Bookmark(
          id: id,
          title: title,
          url: url,
          tags: tags,
          category: category,
          image: image,
          sortOrder: sortOrder,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        ).toJson(),
      );

    case HttpMethod.put:
      return _reorder(db, await context.request.json() as Map<String, dynamic>);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Response _reorder(Database db, Map<String, dynamic> body) {
  final order = body['order'] as List<dynamic>?;
  if (order == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Missing "order" array'},
    );
  }

  for (var i = 0; i < order.length; i++) {
    final id = order[i] as int?;
    if (id == null) continue;
    db.execute(
      'UPDATE bookmarks SET sort_order = ? WHERE id = ?',
      [i, id],
    );
  }

  final rows = db.select('SELECT * FROM bookmarks ORDER BY sort_order ASC');
  return Response.json(
    body: rows.map(Bookmark.fromRow).map((b) => b.toJson()).toList(),
  );
}
