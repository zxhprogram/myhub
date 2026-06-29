import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:dio/dio.dart' hide Response;

/// GET /bookmarks/preview?url=...
///
/// Fetches the page at the given URL and extracts metadata:
/// title, og:image, and favicon.
Future<Response> onRequest(RequestContext context) async {
  final url = context.request.uri.queryParameters['url'];
  if (url == null || url.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Missing "url" query parameter'},
    );
  }

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: true,
      maxRedirects: 5,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; NexusHub/1.0; +https://nexus-hub.app)',
        'Accept': 'text/html,application/xhtml+xml',
      },
      responseType: ResponseType.plain,
    ),
  );

  try {
    final response = await dio.get<String>(url);
    final html = response.data ?? '';
    final baseUri = response.redirects.isNotEmpty
        ? response.realUri
        : Uri.parse(url);

    final title = _extractTitle(html);
    final image = _resolveUrl(
      _extractMetaContent(html, 'og:image') ??
          _extractMetaContent(html, 'twitter:image'),
      baseUri,
    );
    final favicon = _resolveUrl(
      _extractFavicon(html) ?? '/favicon.ico',
      baseUri,
    );

    return Response.json(
      body: {
        'title': title,
        'image': image ?? '',
        'favicon': favicon ?? '',
      },
    );
  } on DioException catch (e) {
    return Response.json(
      statusCode: HttpStatus.badGateway,
      body: {'error': 'Failed to fetch URL: ${e.message}'},
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Unexpected error: $e'},
    );
  }
}

String _extractTitle(String html) {
  final titleMatch = RegExp(
    '''<title[^>]*>(.*?)</title>''',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(html);
  if (titleMatch != null) {
    return _decodeEntities(titleMatch.group(1)!.trim());
  }
  final ogTitle = _extractMetaContent(html, 'og:title');
  return ogTitle ?? '';
}

String? _extractMetaContent(String html, String property) {
  final escaped = RegExp.escape(property);
  final patternA = RegExp(
    '<meta[^>]+(?:property|name)=["\']$escaped["\'][^>]*content=["\'](.*?)["\']',
    caseSensitive: false,
    dotAll: true,
  );
  final matchA = patternA.firstMatch(html);
  if (matchA != null) return _decodeEntities(matchA.group(1)!.trim());

  final patternB = RegExp(
    '<meta[^>]+content=["\'](.*?)["\'][^>]*(?:property|name)=["\']$escaped["\']',
    caseSensitive: false,
    dotAll: true,
  );
  final matchB = patternB.firstMatch(html);
  if (matchB != null) return _decodeEntities(matchB.group(1)!.trim());

  return null;
}

String? _extractFavicon(String html) {
  final patternA = RegExp(
    '''<link[^>]+rel=["'](?:shortcut )?icon["'][^>]*href=["'](.*?)["']''',
    caseSensitive: false,
    dotAll: true,
  );
  final matchA = patternA.firstMatch(html);
  if (matchA != null) return matchA.group(1)!.trim();

  final patternB = RegExp(
    '''<link[^>]+href=["'](.*?)["'][^>]*rel=["'](?:shortcut )?icon["']''',
    caseSensitive: false,
    dotAll: true,
  );
  final matchB = patternB.firstMatch(html);
  if (matchB != null) return matchB.group(1)!.trim();

  return null;
}

String? _resolveUrl(String? href, Uri base) {
  if (href == null || href.isEmpty) return null;
  try {
    return base.resolve(href).toString();
  } catch (_) {
    return null;
  }
}

String _decodeEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');
}
