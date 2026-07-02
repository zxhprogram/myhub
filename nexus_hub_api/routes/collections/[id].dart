import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/collection.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final db = DatabaseProvider.instance;
  final collectionId = int.tryParse(id);
  if (collectionId == null) {
    return Response(statusCode: HttpStatus.badRequest);
  }

  final existing = db.select(
    'SELECT * FROM collections WHERE id = ?',
    [collectionId],
  );
  if (existing.isEmpty) {
    return Response(statusCode: HttpStatus.notFound);
  }

  final collection = Collection.fromRow(existing.first);

  switch (context.request.method) {
    case HttpMethod.get:
      return Response.json(body: collection.toJson());

    case HttpMethod.put:
      final body = await context.request.json() as Map<String, dynamic>;
      final name = (body['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) {
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {'error': 'Collection name is required'},
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      try {
        db.execute(
          '''
          UPDATE collections
          SET name = ?, updated_at = ?
          WHERE id = ?
        ''',
          [name, now, collectionId],
        );
      } on SqliteException {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'Collection name already exists'},
        );
      }

      return Response.json(
        body: collection
            .copyWith(
              name: name,
              updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
            )
            .toJson(),
      );

    case HttpMethod.delete:
      db.execute(
        'DELETE FROM bookmark_collections WHERE collection_id = ?',
        [collectionId],
      );
      db.execute('DELETE FROM collections WHERE id = ?', [collectionId]);
      return Response(statusCode: HttpStatus.noContent);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}
