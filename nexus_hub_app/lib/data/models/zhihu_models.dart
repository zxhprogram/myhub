/// Data models for the Zhihu (知乎) sub-app.
///
/// All models parse defensively: the anonymous Zhihu endpoints come in
/// several shapes (mobile `api.zhihu.com` vs web `www.zhihu.com/api/v4`
/// and `/api/v3`), so ids arrive as int or String, titles may be a plain
/// string or a `{text: ...}` object, and timestamps may be seconds or
/// milliseconds depending on the responding host.
library;

/// A single entry of the Zhihu hot list (热榜).
class ZhihuHotItem {
  const ZhihuHotItem({
    required this.id,
    required this.targetType,
    required this.title,
    required this.excerpt,
    required this.detailText,
    required this.cardLabel,
    required this.thumbnail,
    required this.answerCount,
    required this.followerCount,
    required this.commentCount,
    required this.rank,
  });

  factory ZhihuHotItem.fromJson(
    Map<String, dynamic> json, {
    int rank = 0,
  }) {
    final target = _asMap(json['target']);
    return ZhihuHotItem(
      id: _asString(target['id']),
      targetType: _asString(target['type']),
      title: _titleText(target['title']),
      excerpt: _asString(target['excerpt']),
      detailText: _asString(json['detail_text']),
      cardLabel: _asString(_asMap(json['card_label'])['name']),
      thumbnail: _asString(target['thumbnail']),
      answerCount: _asInt(target['answer_count']),
      followerCount: _asInt(target['follower_count']),
      commentCount: _asInt(target['comment_count']),
      rank: rank,
    );
  }

  final String id;

  /// Discriminator of the linked target: `question` or `article`.
  final String targetType;

  final String title;

  /// Short preview text; may be empty or a placeholder like `[视频]`.
  final String excerpt;

  /// Heat metric as pre-formatted by the API, e.g. `1204 万热度`.
  final String detailText;

  /// Editorial label such as `置顶` / `新` / `热`; empty when absent.
  final String cardLabel;

  /// Optional card cover image.
  final String thumbnail;

  final int answerCount;
  final int followerCount;
  final int commentCount;

  /// 1-based position on the board, assigned while parsing.
  final int rank;

  bool get isArticle => targetType == 'article';

  String get webUrl => isArticle
      ? 'https://zhuanlan.zhihu.com/p/$id'
      : 'https://www.zhihu.com/question/$id';
}

/// One page of answers below a Zhihu question.
class ZhihuAnswerPage {
  const ZhihuAnswerPage({required this.answers, required this.hasMore});

  final List<ZhihuAnswer> answers;

  /// Whether another page can be requested after this one.
  final bool hasMore;
}

/// An answer under a Zhihu question.
class ZhihuAnswer {
  const ZhihuAnswer({
    required this.id,
    required this.questionId,
    required this.authorName,
    required this.authorHeadline,
    required this.authorAvatarUrl,
    required this.voteupCount,
    required this.commentCount,
    required this.contentHtml,
    required this.updatedAtMs,
  });

  /// Accepts both feed shapes: the mobile API wraps the answer in a
  /// `target` node, while the web v4 endpoint inlines it directly.
  factory ZhihuAnswer.fromJson(
    Map<String, dynamic> json, {
    required String questionId,
  }) {
    final author = _asMap(json['author']);
    var updated = _asInt(json['updated_time']);
    if (updated == 0) updated = _asInt(json['created_time']);
    return ZhihuAnswer(
      id: _asString(json['id']),
      questionId: questionId,
      authorName: _asString(author['name']),
      authorHeadline: _asString(author['headline']),
      authorAvatarUrl: _asString(author['avatar_url']),
      voteupCount: _asInt(json['voteup_count']),
      commentCount: _asInt(json['comment_count']),
      contentHtml: _asString(json['content']),
      updatedAtMs: _asMs(updated),
    );
  }

  final String id;
  final String questionId;
  final String authorName;
  final String authorHeadline;
  final String authorAvatarUrl;
  final int voteupCount;
  final int commentCount;

  /// Rich-text body of the answer, rendered natively (no WebView).
  final String contentHtml;

  /// Update time in milliseconds since epoch; 0 when unknown.
  final int updatedAtMs;

  String get webUrl => 'https://www.zhihu.com/question/$questionId/answer/$id';
}

/// A standalone Zhihu article (专栏文章) linked from the hot list.
class ZhihuArticle {
  const ZhihuArticle({
    required this.id,
    required this.title,
    required this.authorName,
    required this.authorHeadline,
    required this.authorAvatarUrl,
    required this.voteupCount,
    required this.commentCount,
    required this.contentHtml,
    required this.updatedAtMs,
  });

  factory ZhihuArticle.fromJson(Map<String, dynamic> json) {
    final author = _asMap(json['author']);
    return ZhihuArticle(
      id: _asString(json['id']),
      title: _asString(json['title']),
      authorName: _asString(author['name']),
      authorHeadline: _asString(author['headline']),
      authorAvatarUrl: _asString(author['avatar_url']),
      voteupCount: _asInt(json['voteupCount']),
      commentCount: _asInt(json['commentCount']),
      contentHtml: _asString(json['content']),
      updatedAtMs: _asMs(_asInt(json['updated'])),
    );
  }

  final String id;
  final String title;
  final String authorName;
  final String authorHeadline;
  final String authorAvatarUrl;
  final int voteupCount;
  final int commentCount;
  final String contentHtml;
  final int updatedAtMs;

  String get webUrl => 'https://zhuanlan.zhihu.com/p/$id';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

String _asString(dynamic value) {
  if (value is String) return value;
  if (value is num) return value.toInt().toString();
  return '';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Zhihu serves question titles either as a plain string (mobile API) or
/// as a `{text: ...}` object (web v3 hot-list variant).
String _titleText(dynamic value) {
  if (value is String) return value;
  if (value is Map) return _asString(value['text']);
  return '';
}

/// Normalises seconds- vs milliseconds-based timestamps.
int _asMs(int value) {
  if (value <= 0) return 0;
  return value > 100000000000 ? value : value * 1000;
}
