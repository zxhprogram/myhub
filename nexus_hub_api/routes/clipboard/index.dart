import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/clipboard_item.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = DatabaseProvider.instance;

  switch (context.request.method) {
    case HttpMethod.get:
      final query = context.request.uri.queryParameters['q'];
      final rows = db
          .select(
            '''
        SELECT * FROM clipboard
        WHERE (?1 IS NULL OR content LIKE '%' || ?1 || '%')
        ORDER BY created_at DESC
        LIMIT 100
      ''',
            [query],
          )
          .cast<Row>();
      final items = rows
          .map(ClipboardItem.fromRow)
          .map((i) => i.toJson())
          .toList();
      return Response.json(body: items);

    case HttpMethod.post:
      final body = await context.request.json() as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      final content = body['content'] as String? ?? '';
      final type = body['type'] as String? ?? 'text';

      db.execute(
        '''
        INSERT INTO clipboard (content, type, created_at)
        VALUES (?, ?, ?)
      ''',
        [content, type, now],
      );

      final id = db.lastInsertRowId;
      return Response.json(
        statusCode: HttpStatus.created,
        body: ClipboardItem(
          id: id,
          content: content,
          type: type,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
        ).toJson(),
      );

    case HttpMethod.delete:
      db.execute('DELETE FROM clipboard');
      return Response(statusCode: HttpStatus.noContent);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}
