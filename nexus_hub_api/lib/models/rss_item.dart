import 'package:sqlite3/sqlite3.dart';

/// RSS feed domain model.
class RssFeed {
  const RssFeed({
    this.id,
    required this.title,
    required this.url,
    required this.category,
    required this.createdAt,
  });

  final int? id;
  final String title;
  final String url;
  final String category;
  final DateTime createdAt;

  factory RssFeed.fromRow(Row row) {
    return RssFeed(
      id: row['id'] as int,
      title: row['title'] as String,
      url: row['url'] as String,
      category: row['category'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'category': category,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// RSS article domain model.
class RssArticle {
  const RssArticle({
    this.id,
    required this.feedId,
    required this.title,
    required this.summary,
    required this.url,
    required this.publishedAt,
    required this.isRead,
  });

  final int? id;
  final int feedId;
  final String title;
  final String summary;
  final String url;
  final DateTime publishedAt;
  final bool isRead;

  factory RssArticle.fromRow(Row row) {
    return RssArticle(
      id: row['id'] as int,
      feedId: row['feed_id'] as int,
      title: row['title'] as String,
      summary: row['summary'] as String,
      url: row['url'] as String,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
        row['published_at'] as int,
      ),
      isRead: (row['is_read'] as int) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'feedId': feedId,
    'title': title,
    'summary': summary,
    'url': url,
    'publishedAt': publishedAt.toIso8601String(),
    'isRead': isRead,
  };
}
