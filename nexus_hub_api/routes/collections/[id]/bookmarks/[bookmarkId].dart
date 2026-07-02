import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../../../../lib/database.dart';

Future<Response> onRequest(
  RequestContext context,
  String id,
  String bookmarkId,
) async {
  final db = DatabaseProvider.instance;
  final collectionId = int.tryParse(id);
  final bkmId = int.tryParse(bookmarkId);
  if (collectionId == null || bkmId == null) {
    return Response(statusCode: HttpStatus.badRequest);
  }

  if (context.request.method != HttpMethod.delete) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  db.execute(
    '''
    DELETE FROM bookmark_collections
    WHERE collection_id = ? AND bookmark_id = ?
  ''',
    [collectionId, bkmId],
  );

  return Response(statusCode: HttpStatus.noContent);
}
