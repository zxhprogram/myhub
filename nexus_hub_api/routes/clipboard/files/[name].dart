import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mime/mime.dart';

import '../../../lib/clipboard_files.dart';

Future<Response> onRequest(RequestContext context, String name) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final file = File(resolveClipboardFilePath('temp/$name'));
  if (!file.existsSync()) {
    return Response(statusCode: HttpStatus.notFound);
  }

  final bytes = await file.readAsBytes();
  final contentType = lookupMimeType(name) ?? 'application/octet-stream';
  return Response.bytes(
    body: bytes,
    headers: {'Content-Type': contentType},
  );
}
