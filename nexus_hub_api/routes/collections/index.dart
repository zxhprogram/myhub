import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../lib/database.dart';
import '../../lib/models/collection.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = DatabaseProvider.instance;

  switch (context.request.method) {
    case HttpMethod.get:
      final sort = context.request.uri.queryParameters['sort']?.toLowerCase();

      final String orderBy;
      switch (sort) {
        case 'name_asc':
          orderBy = 'name ASC';
        case 'name_desc':
          orderBy = 'name DESC';
        case 'created_asc':
          orderBy = 'created_at ASC';
        case 'created_desc':
          orderBy = 'created_at DESC';
        default:
          orderBy = 'sort_order ASC, name ASC';
      }

      final rows = db.select('SELECT * FROM collections ORDER BY $orderBy');
      final collections = rows
          .cast<Row>()
          .map(Collection.fromRow)
          .map((c) => c.toJson())
          .toList();
      return Response.json(body: collections);

    case HttpMethod.post:
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
          INSERT INTO collections (name, sort_order, created_at, updated_at)
          VALUES (?, ?, ?, ?)
        ''',
          [name, 0, now, now],
        );
      } on SqliteException {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'Collection name already exists'},
        );
      }

      final id = db.lastInsertRowId;
      return Response.json(
        statusCode: HttpStatus.created,
        body: Collection(
          id: id,
          name: name,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        ).toJson(),
      );

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}
