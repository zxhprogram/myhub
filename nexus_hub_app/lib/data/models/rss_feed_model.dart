/// RSS subscription feed stored locally (mirrors the former backend
/// `rss_feeds` table).
class RssFeedModel {
  const RssFeedModel({
    this.id,
    required this.title,
    required this.url,
    this.category = '',
    required this.createdAt,
  });

  final int? id;
  final String title;
  final String url;
  final String category;
  final DateTime createdAt;

  factory RssFeedModel.fromJson(Map<String, dynamic> json) {
    return RssFeedModel(
      id: json['id'] as int?,
      title: json['title'] as String,
      url: json['url'] as String,
      category: (json['category'] as String?) ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'category': category,
    'createdAt': createdAt.toIso8601String(),
  };

  RssFeedModel copyWith({
    int? id,
    String? title,
    String? url,
    String? category,
    DateTime? createdAt,
  }) {
    return RssFeedModel(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Single article fetched from an RSS/Atom feed (mirrors the former backend
/// `rss_items` table).
class RssArticleModel {
  const RssArticleModel({
    this.id,
    required this.feedId,
    required this.title,
    this.summary = '',
    required this.url,
    required this.publishedAt,
    this.isRead = false,
  });

  final int? id;
  final int feedId;
  final String title;
  final String summary;
  final String url;
  final DateTime publishedAt;
  final bool isRead;

  factory RssArticleModel.fromJson(Map<String, dynamic> json) {
    return RssArticleModel(
      id: json['id'] as int?,
      feedId: json['feedId'] as int,
      title: json['title'] as String,
      summary: (json['summary'] as String?) ?? '',
      url: json['url'] as String,
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      isRead: (json['isRead'] as bool?) ?? false,
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

  RssArticleModel copyWith({
    int? id,
    int? feedId,
    String? title,
    String? summary,
    String? url,
    DateTime? publishedAt,
    bool? isRead,
  }) {
    return RssArticleModel(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      url: url ?? this.url,
      publishedAt: publishedAt ?? this.publishedAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
