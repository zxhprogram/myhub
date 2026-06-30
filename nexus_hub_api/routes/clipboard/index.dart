import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../lib/clipboard_files.dart';
import '../../lib/database.dart';
import '../../lib/models/clipboard_item.dart';

Future<Response> onRequest(RequestContext context) async {
  final db = DatabaseProvider.instance;

  switch (context.request.method) {
    case HttpMethod.get:
      return _get(db, context.request.uri.queryParameters['q']);

    case HttpMethod.post:
      final contentType = context.request.headers['Content-Type'] ?? '';
      if (contentType.startsWith('multipart/form-data')) {
        return _upload(db, await context.request.formData());
      }
      return _create(db, await context.request.json() as Map<String, dynamic>);

    case HttpMethod.delete:
      _clearFiles(db);
      db.execute('DELETE FROM clipboard');
      return Response(statusCode: HttpStatus.noContent);

    default:
      return Response(statusCode: HttpStatus.methodNotAllowed);
  }
}

Response _get(Database db, String? query) {
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
  final items = rows.map(ClipboardItem.fromRow).map((i) => i.toJson()).toList();
  return Response.json(body: items);
}

Response _create(Database db, Map<String, dynamic> body) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final content = body['content'] as String? ?? '';
  final type = body['type'] as String? ?? 'text';
  final filePath = body['filePath'] as String?;
  final mimeType = body['mimeType'] as String?;

  db.execute(
    '''
    INSERT INTO clipboard (content, type, file_path, mime_type, created_at)
    VALUES (?, ?, ?, ?, ?)
  ''',
    [content, type, filePath, mimeType, now],
  );

  final id = db.lastInsertRowId;
  return Response.json(
    statusCode: HttpStatus.created,
    body: ClipboardItem(
      id: id,
      content: content,
      type: type,
      filePath: filePath,
      mimeType: mimeType,
      createdAt: DateTime.fromMillisecondsSinceEpoch(now),
    ).toJson(),
  );
}

Future<Response> _upload(Database db, FormData formData) async {
  final file = formData.files['file'];
  if (file == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Missing "file"'},
    );
  }

  final bytes = await file.readAsBytes();
  final originalName = file.name;
  final safeName = _safeFileName(originalName);
  final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
  final tempDir = ensureClipboardTempDir();
  final filePath = p.join(tempDir.path, uniqueName);
  await File(filePath).writeAsBytes(bytes);

  final relativePath = p.relative(filePath, from: tempDir.parent.path);
  final type = formData.fields['type'] ?? 'file';
  final mimeType =
      formData.fields['mimeType'] ??
      (file.contentType.value.isNotEmpty
          ? file.contentType.value
          : 'application/octet-stream');
  final content = formData.fields['content'] ?? originalName;

  return _create(db, {
    'content': content,
    'type': type,
    'filePath': relativePath,
    'mimeType': mimeType,
  });
}

/// Removes path separators and unsafe characters from uploaded file names.
String _safeFileName(String name) {
  final base = p.basename(name);
  return base.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');
}

/// Deletes all files referenced by clipboard rows before clearing the table.
void _clearFiles(Database db) {
  final rows = db.select('SELECT file_path FROM clipboard');
  for (final row in rows) {
    final path = row['file_path'] as String?;
    if (path != null && path.isNotEmpty) {
      try {
        File(resolveClipboardFilePath(path)).deleteSync();
      } on FileSystemException {
        // Ignore files that are already missing.
      }
    }
  }
}
