import 'package:dio/dio.dart';

/// Result of scraping metadata (title, og:image, favicon) from a URL.
class BookmarkPreview {
  const BookmarkPreview({this.title = '', this.image = '', this.favicon = ''});

  final String title;
  final String image;
  final String favicon;

  factory BookmarkPreview.fromJson(Map<String, dynamic> json) {
    return BookmarkPreview(
      title: (json['title'] as String?) ?? '',
      image: (json['image'] as String?) ?? '',
      favicon: (json['favicon'] as String?) ?? '',
    );
  }
}

/// Scrapes page metadata for the bookmark preview dialog.
///
/// Ported from the former backend endpoint `GET /bookmarks/preview`.
class UrlPreviewService {
  final Dio _dio = Dio(
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

  Future<BookmarkPreview> fetch(String url) async {
    final response = await _dio.get<String>(url);
    final html = response.data ?? '';
    final baseUri = response.redirects.isNotEmpty
        ? response.realUri
        : Uri.parse(url);

    return BookmarkPreview(
      title: _extractTitle(html),
      image: _resolveUrl(
            _extractMetaContent(html, 'og:image') ??
                _extractMetaContent(html, 'twitter:image'),
            baseUri,
          ) ??
          '',
      favicon: _resolveUrl(
            _extractFavicon(html) ?? '/favicon.ico',
            baseUri,
          ) ??
          '',
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
