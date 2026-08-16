import 'package:dio/dio.dart';

import '../models/fx678_news_model.dart';
import 'local_database.dart';

/// Service for the fx678 7x24 flash-news feed (https://www.fx678.com/kx).
///
/// The page server-renders ~200 entries per request, each shaped like:
/// ```html
/// <li class="body_zb_li" id="newsid202608162257011129">
///   <div class="zb_time"><a>22:57:01</a></div>
///   <div class="zb_word">
///     <div class="list_font_pic">        <!-- "_t red_color_f" when important -->
///       <a id="aid202608162257011129" href="https://www.fx678.com/C/...html">
///         <span>【标题】正文...</span>
///       </a>
///       ...
/// ```
/// Entries are parsed with regular expressions, following the convention of
/// the other fx678 scrapers (no HTML package dependency).
class Fx678NewsService {
  Fx678NewsService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _cacheKey = 'flash_news';
  static const _cacheTtl = Duration(minutes: 2);

  /// Returns cached news if fresh, otherwise fetches from the web.
  Future<List<Fx678NewsItem>> fetchNews() async {
    final cached = await _loadCached(ignoreTtl: false);
    if (cached != null) return cached;
    return _fetchAndCache();
  }

  /// Force-refresh from the web; falls back to stale cache on failure.
  Future<List<Fx678NewsItem>> refreshNews() async {
    try {
      return await _fetchAndCache();
    } catch (_) {
      final stale = await _loadCached(ignoreTtl: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  Future<List<Fx678NewsItem>> _fetchAndCache() async {
    final news = await _fetchFromWeb();
    await _cacheNews(news);
    return news;
  }

  Future<List<Fx678NewsItem>> _fetchFromWeb() async {
    final response = await _dio.get<String>(
      'https://www.fx678.com/kx',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/125.0.0.0 Safari/537.36',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ),
    );

    final items = _parseHtml(response.data ?? '');
    if (items.isEmpty) {
      throw StateError('No flash news entries found on the page.');
    }
    return items;
  }

  List<Fx678NewsItem> _parseHtml(String html) {
    final items = <Fx678NewsItem>[];

    // Each entry opens with `<li class="body_zb_li...`. Splitting on that
    // marker keeps nested <li> elements (comment buttons etc.) inside the
    // owning chunk instead of terminating a lazy `</li>` match early.
    final chunks = html.split('<li class="body_zb_li');

    final idPattern = RegExp(r'newsid(\d+)');
    final timePattern = RegExp(
      r'class="zb_time">\s*<a>([^<]+)</a>',
      caseSensitive: false,
    );
    final anchorPattern = RegExp(
      r'<a\s+id="aid\d+"[^>]*href="([^"]+)"[^>]*>\s*<span>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final chunk in chunks.skip(1)) {
      final idMatch = idPattern.firstMatch(chunk);
      final anchorMatch = anchorPattern.firstMatch(chunk);
      if (idMatch == null || anchorMatch == null) continue;

      final id = idMatch.group(1)!;
      final url = anchorMatch.group(1)!;
      final content = _stripHtml(anchorMatch.group(2)!);
      if (content.isEmpty) continue;

      final timeMatch = timePattern.firstMatch(chunk);
      var timeText = timeMatch?.group(1)?.trim() ?? '';
      if (timeText.isEmpty && id.length >= 14) {
        // The id encodes yyyyMMddHHmmss; derive the clock time from it.
        final clock = id.substring(8, 14);
        timeText = '${clock.substring(0, 2)}:'
            '${clock.substring(2, 4)}:${clock.substring(4, 6)}';
      }

      items.add(Fx678NewsItem(
        id: id,
        timeText: timeText,
        title: Fx678NewsItem.extractTitle(content),
        content: content,
        url: url,
        isImportant: chunk.contains('red_color_f'),
      ));
    }

    return items;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&ldquo;', '“')
        .replaceAll('&rdquo;', '”')
        .replaceAll('&lsquo;', '‘')
        .replaceAll('&rsquo;', '’')
        .replaceAll('&mdash;', '—')
        .replaceAll('&middot;', '·')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<List<Fx678NewsItem>?> _loadCached({required bool ignoreTtl}) async {
    try {
      final box = await LocalDatabase.box('fx678_news');
      final raw = box.get(_cacheKey);
      if (raw == null) return null;

      final data = Map<String, dynamic>.from(raw as Map);
      if (!ignoreTtl) {
        final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - cachedAt > _cacheTtl.inMilliseconds) return null;
      }

      final list = data['items'] as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(Fx678NewsItem.fromJson)
          .toList();
    } catch (_) {
      // Cache is an optimization only; fall through to the network.
      return null;
    }
  }

  Future<void> _cacheNews(List<Fx678NewsItem> items) async {
    try {
      final box = await LocalDatabase.box('fx678_news');
      await box.put(_cacheKey, {
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((i) => i.toJson()).toList(),
      });
    } catch (_) {
      // Cache is an optimization only; ignore write failures.
    }
  }
}
