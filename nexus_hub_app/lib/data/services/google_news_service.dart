import 'package:dio/dio.dart';

import '../models/google_news_item.dart';
import 'local_database.dart';

/// Google News RSS topic feeds.
///
/// Headlines are served in Simplified Chinese (hl=zh-CN). Each topic maps to
/// a Google News RSS section feed that requires no API key.
enum GoogleNewsTopic {
  topStories(
    'Top Stories',
    'top',
    'https://news.google.com/rss?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  world(
    'World',
    'world',
    'https://news.google.com/rss/headlines/section/topic/WORLD?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  business(
    'Business',
    'business',
    'https://news.google.com/rss/headlines/section/topic/BUSINESS?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  technology(
    'Technology',
    'technology',
    'https://news.google.com/rss/headlines/section/topic/TECHNOLOGY?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  science(
    'Science',
    'science',
    'https://news.google.com/rss/headlines/section/topic/SCIENCE?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  sports(
    'Sports',
    'sports',
    'https://news.google.com/rss/headlines/section/topic/SPORTS?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  health(
    'Health',
    'health',
    'https://news.google.com/rss/headlines/section/topic/HEALTH?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  ),
  entertainment(
    'Entertainment',
    'entertainment',
    'https://news.google.com/rss/headlines/section/topic/ENTERTAINMENT?hl=zh-CN&gl=CN&ceid=CN:zh-Hans',
  );

  const GoogleNewsTopic(this.label, this.id, this.rssUrl);

  final String label;
  final String id;
  final String rssUrl;
}

/// Fetches and parses Google News RSS feeds.
///
/// Results are cached in a Hive box per topic for 5 minutes and gracefully
/// fall back to the stale cache when the network is down, so the page keeps
/// rendering even without a connection.
class GoogleNewsService {
  GoogleNewsService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _boxName = 'google_news';
  static const _cacheTtl = Duration(minutes: 5);

  /// Returns cached headlines if fresh, otherwise fetches from Google News.
  Future<List<GoogleNewsItem>> fetchTopic(GoogleNewsTopic topic) async {
    final cached = await _loadCached(topic);
    if (cached != null) return cached;
    return _fetchAndCache(topic);
  }

  /// Force-refreshes from Google News, falling back to stale cache on error.
  Future<List<GoogleNewsItem>> refreshTopic(GoogleNewsTopic topic) async {
    try {
      return await _fetchAndCache(topic);
    } catch (_) {
      final stale = await _loadCached(topic, ignoreTtl: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  Future<List<GoogleNewsItem>> _fetchAndCache(GoogleNewsTopic topic) async {
    final items = await _fetchFromWeb(topic);
    await _cache(topic, items);
    return items;
  }

  Future<List<GoogleNewsItem>> _fetchFromWeb(GoogleNewsTopic topic) async {
    final response = await _dio.get<String>(
      topic.rssUrl,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/125.0.0.0 Safari/537.36',
        },
      ),
    );
    return GoogleNewsRssParser.parse(response.data ?? '');
  }

  Future<List<GoogleNewsItem>?> _loadCached(
    GoogleNewsTopic topic, {
    bool ignoreTtl = false,
  }) async {
    try {
      final box = await LocalDatabase.box(_boxName);
      final raw = box.get('items_${topic.id}');
      if (raw == null) return null;

      final data = Map<String, dynamic>.from(raw as Map);
      final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
      final isStale =
          DateTime.now().millisecondsSinceEpoch - cachedAt >
          _cacheTtl.inMilliseconds;
      if (isStale && !ignoreTtl) return null;

      final list = data['items'] as List<dynamic>? ?? const [];
      return list
          .cast<Map<String, dynamic>>()
          .map(GoogleNewsItem.fromJson)
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> _cache(GoogleNewsTopic topic, List<GoogleNewsItem> items) async {
    try {
      final box = await LocalDatabase.box(_boxName);
      await box.put('items_${topic.id}', {
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((i) => i.toJson()).toList(),
      });
    } catch (_) {
      // Cache failures are non-fatal — the feed still renders.
    }
  }
}

/// Minimal RSS 2.0 parser tailored to Google News feeds.
///
/// Implemented with regular expressions so no XML package is required; Google
/// News emits well-formed feeds whose `<item>` elements never nest.
abstract final class GoogleNewsRssParser {
  static final RegExp _itemRe = RegExp(r'<item[^>]*>([\s\S]*?)</item>');
  static final RegExp _titleRe = RegExp(r'<title[^>]*>([\s\S]*?)</title>');
  static final RegExp _linkRe = RegExp(r'<link[^>]*>([\s\S]*?)</link>');
  static final RegExp _pubDateRe = RegExp(r'<pubDate[^>]*>([\s\S]*?)</pubDate>');
  static final RegExp _sourceRe = RegExp(r'<source[^>]*>([\s\S]*?)</source>');
  static final RegExp _descriptionRe = RegExp(
    r'<description[^>]*>([\s\S]*?)</description>',
  );
  static final RegExp _mediaContentRe = RegExp(
    r'<media:content[^>]*url="([^"]+)"',
  );
  static final RegExp _mediaThumbnailRe = RegExp(
    r'<media:thumbnail[^>]*url="([^"]+)"',
  );
  static final RegExp _htmlTagRe = RegExp(r'<[^>]+>');
  static final RegExp _whitespaceRe = RegExp(r'\s+');
  static final RegExp _hexEntityRe = RegExp(r'&#x([0-9a-fA-F]+);');
  static final RegExp _decEntityRe = RegExp(r'&#(\d+);');

  static List<GoogleNewsItem> parse(String xml) {
    final items = <GoogleNewsItem>[];
    for (final match in _itemRe.allMatches(xml)) {
      final item = match.group(1) ?? '';
      final title = _decodeEntities(_first(_titleRe, item) ?? '').trim();
      final link = (_first(_linkRe, item) ?? '').trim();
      if (title.isEmpty || link.isEmpty) continue;

      final image =
          _first(_mediaContentRe, item) ??
          _first(_mediaThumbnailRe, item) ??
          '';

      items.add(
        GoogleNewsItem(
          title: title,
          link: link,
          source: _decodeEntities(_first(_sourceRe, item) ?? '').trim(),
          snippet: _snippetFrom(_first(_descriptionRe, item)),
          imageUrl: image.trim(),
          publishedAt: _parseRfc822Date(_first(_pubDateRe, item)),
        ),
      );
    }
    return items;
  }

  static String? _first(RegExp re, String input) {
    final match = re.firstMatch(input);
    return match?.group(1);
  }

  /// Strips HTML tags from the feed description and collapses whitespace.
  ///
  /// Google News escapes description markup as entities (`&lt;ol&gt;`), so
  /// entities are decoded first and tags stripped afterwards.
  static String _snippetFrom(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final text = _decodeEntities(raw)
        .replaceAll(_htmlTagRe, ' ')
        .replaceAll(_whitespaceRe, ' ')
        .trim();
    if (text.length <= 240) return text;
    return '${text.substring(0, 237)}...';
  }

  static String _decodeEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(
          _hexEntityRe,
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAllMapped(
          _decEntityRe,
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        );
  }

  static const Map<String, int> _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  /// Parses RFC 822 dates such as "Thu, 14 Aug 2026 12:34:56 GMT".
  static DateTime? _parseRfc822Date(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(raw);
    if (match == null) return null;
    final month = _months[match.group(2)];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      match.group(6) != null ? int.parse(match.group(6)!) : 0,
    );
  }
}
