import '../models/rss_feed_model.dart';
import '../services/local_database.dart';
import '../services/rss_feed_service.dart';

/// Repository for RSS feeds and articles backed by the local Hive store.
/// (Previously the backend exposed `/rss` storage endpoints, but nothing
/// fetched or parsed feeds — that logic lives here now.)
class RssRepository {
  RssRepository({RssFeedService? service})
      : _service = service ?? RssFeedService();

  final RssFeedService _service;

  static const _maxStoredArticlesPerFeed = 200;
  static const _maxReturnedArticles = 100;

  Future<List<RssFeedModel>> fetchFeeds() async {
    final rows = (await LocalDatabase.box('rss_feeds'))
        .values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    rows.sort((a, b) {
      final aDate = DateTime.parse(a['createdAt'] as String);
      final bDate = DateTime.parse(b['createdAt'] as String);
      return aDate.compareTo(bDate);
    });
    return rows.map(RssFeedModel.fromJson).toList();
  }

  /// Latest articles across all feeds, newest first.
  Future<List<RssArticleModel>> fetchArticles({int? feedId}) async {
    final rows = (await LocalDatabase.box('rss_articles'))
        .values
        .map((row) => Map<String, dynamic>.from(row as Map))
        .where((row) => feedId == null || row['feedId'] == feedId)
        .toList();
    rows.sort((a, b) {
      final aDate = DateTime.parse(a['publishedAt'] as String);
      final bDate = DateTime.parse(b['publishedAt'] as String);
      return bDate.compareTo(aDate);
    });
    return rows
        .take(_maxReturnedArticles)
        .map(RssArticleModel.fromJson)
        .toList();
  }

  /// Adds a feed and immediately fetches its articles. Throws [StateError]
  /// when the URL is already subscribed or the feed cannot be parsed.
  Future<RssFeedModel> addFeed({
    String? title,
    required String url,
    String category = '',
  }) async {
    final existing = await _findByUrl(url);
    if (existing != null) {
      throw StateError('Already subscribed to $url');
    }

    final parsed = await _service.fetch(url);
    final now = DateTime.now();
    final feed = RssFeedModel(
      title: (title == null || title.isEmpty) ? parsed.title : title,
      url: url,
      category: category,
      createdAt: now,
    );

    final box = await LocalDatabase.box('rss_feeds');
    final id = await box.add(feed.toJson());
    final created = feed.copyWith(id: id);
    await box.put(id, created.toJson());
    await _storeArticles(created, parsed.articles);
    return created;
  }

  Future<void> deleteFeed(int feedId) async {
    final articlesBox = await LocalDatabase.box('rss_articles');
    final keysToDelete = <dynamic>[];
    for (final key in articlesBox.keys) {
      final record = Map<String, dynamic>.from(articlesBox.get(key) as Map);
      if (record['feedId'] == feedId) {
        keysToDelete.add(key);
      }
    }
    for (final key in keysToDelete) {
      await articlesBox.delete(key);
    }
    final box = await LocalDatabase.box('rss_feeds');
    await box.delete(feedId);
  }

  /// Re-fetches every feed and stores any new articles. Returns the number of
  /// new articles added. Feeds that fail to fetch are skipped.
  Future<int> refreshAll() async {
    final feeds = await fetchFeeds();
    var added = 0;
    for (final feed in feeds) {
      try {
        final parsed = await _service.fetch(feed.url);
        added += await _storeArticles(feed, parsed.articles);
      } catch (_) {
        // Skip unreachable feeds during refresh.
      }
    }
    return added;
  }

  Future<void> markRead(int articleId, {bool isRead = true}) async {
    final box = await LocalDatabase.box('rss_articles');
    final existing = box.get(articleId);
    if (existing == null) return;
    final record = Map<String, dynamic>.from(existing as Map);
    record['isRead'] = isRead;
    await box.put(articleId, record);
  }

  Future<RssFeedModel?> _findByUrl(String url) async {
    for (final value in (await LocalDatabase.box('rss_feeds')).values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['url'] == url) {
        return RssFeedModel.fromJson(record);
      }
    }
    return null;
  }

  Future<int> _storeArticles(
    RssFeedModel feed,
    List<ParsedRssArticle> articles,
  ) async {
    final box = await LocalDatabase.box('rss_articles');
    final knownUrls = <String>{};
    for (final value in box.values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['feedId'] == feed.id) {
        knownUrls.add(record['url'] as String);
      }
    }

    var added = 0;
    for (final article in articles) {
      if (knownUrls.contains(article.url)) continue;
      final model = RssArticleModel(
        feedId: feed.id!,
        title: article.title,
        summary: article.summary,
        url: article.url,
        publishedAt: article.publishedAt,
      );
      final id = await box.add(model.toJson());
      await box.put(id, model.copyWith(id: id).toJson());
      knownUrls.add(article.url);
      added++;
      if (added >= _maxStoredArticlesPerFeed) break;
    }
    return added;
  }
}
