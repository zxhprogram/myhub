/// A single Google News headline parsed from the Google News RSS feed.
class GoogleNewsItem {
  const GoogleNewsItem({
    required this.title,
    required this.link,
    this.source = '',
    this.snippet = '',
    this.imageUrl = '',
    this.publishedAt,
  });

  factory GoogleNewsItem.fromJson(Map<String, dynamic> json) {
    final publishedAt = json['publishedAt'] as String?;
    return GoogleNewsItem(
      title: json['title'] as String? ?? '',
      link: json['link'] as String? ?? '',
      source: json['source'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      publishedAt: publishedAt != null ? DateTime.tryParse(publishedAt) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'link': link,
      'source': source,
      'snippet': snippet,
      'imageUrl': imageUrl,
      'publishedAt': publishedAt?.toIso8601String(),
    };
  }

  final String title;
  final String link;
  final String source;
  final String snippet;
  final String imageUrl;
  final DateTime? publishedAt;

  bool get hasImage => imageUrl.isNotEmpty;

  bool get hasSnippet => snippet.isNotEmpty;

  /// Compact relative timestamp, e.g. "Just now", "5m ago", "3h ago",
  /// "2d ago", falling back to a date for older articles.
  String get timeAgo {
    final at = publishedAt;
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final month = at.month.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    return '${at.year}-$month-$day';
  }
}
