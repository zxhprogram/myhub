/// A single 7x24 flash-news entry scraped from the fx678 live feed
/// (https://www.fx678.com/kx).
class Fx678NewsItem {
  Fx678NewsItem({
    required this.id,
    required this.timeText,
    required this.title,
    required this.content,
    required this.url,
    this.isImportant = false,
  });

  factory Fx678NewsItem.fromJson(Map<String, dynamic> json) {
    return Fx678NewsItem(
      id: json['id'] as String,
      timeText: json['timeText'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      url: json['url'] as String,
      isImportant: (json['isImportant'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timeText': timeText,
      'title': title,
      'content': content,
      'url': url,
      'isImportant': isImportant,
    };
  }

  /// Source-side id, e.g. `202608162257011129` (yyyyMMddHHmmss + sequence).
  final String id;

  /// Publish clock time as shown on the site, e.g. `22:57:01`.
  final String timeText;

  /// Short headline: the 【...】 lead when present, otherwise the first
  /// sentence of the body.
  final String title;

  /// Full plain-text body.
  final String content;

  /// Detail page on fx678.
  final String url;

  /// Whether the source highlights this entry as important (重要快讯).
  final bool isImportant;

  /// The id encodes the publish moment as yyyyMMddHHmmss.
  DateTime? get publishTime {
    if (id.length < 14) return null;
    final iso = '${id.substring(0, 8)}T${id.substring(8, 10)}:'
        '${id.substring(10, 12)}:${id.substring(12, 14)}';
    return DateTime.tryParse(iso);
  }

  /// Derives the display title from a plain-text body.
  static String extractTitle(String content) {
    final bracketMatch = RegExp(r'^\s*【(.+?)】').firstMatch(content);
    if (bracketMatch != null) return bracketMatch.group(1)!;

    final sentenceEnd = RegExp(r'[。！？!?]').firstMatch(content);
    final candidate = sentenceEnd == null || sentenceEnd.start > 60
        ? (content.length > 40 ? content.substring(0, 40) : content)
        : content.substring(0, sentenceEnd.start);
    return candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
