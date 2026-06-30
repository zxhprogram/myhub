import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

import '../../lib/clipboard_files.dart';
import '../../lib/database.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final db = DatabaseProvider.instance;
  final itemId = int.tryParse(id);
  if (itemId == null) {
    return Response(statusCode: HttpStatus.badRequest);
  }

  final existing = db.select(
    'SELECT file_path FROM clipboard WHERE id = ?',
    [itemId],
  );
  if (existing.isEmpty) {
    return Response(statusCode: HttpStatus.notFound);
  }

  switch (context.request.method) {
    case HttpMethod.delete:
      final filePath = existing.first['file_path'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        try {
          File(resolveClipboardFilePath(filePath)).deleteSync();
        } on FileSystemException {
          // Ignore files that are already missing.
        }
      }
      db.execute('DELETE FROM clipboard WHERE id = ?', [itemId]);
      return Response(statusCode: HttpStatus.noContent);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}
