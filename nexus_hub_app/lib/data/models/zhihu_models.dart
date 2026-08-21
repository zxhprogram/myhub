/// Data models for the Zhihu (知乎) sub-app.
///
/// All models parse defensively: the anonymous Zhihu endpoints come in
/// several shapes (mobile `api.zhihu.com` vs web `www.zhihu.com/api/v4`
/// and `/api/v3`), so ids arrive as int or String, titles may be a plain
/// string or a `{text: ...}` object, and timestamps may be seconds or
/// milliseconds depending on the responding host.
library;

/// Cleans Zhihu rich-text HTML (answer / article / feed bodies) so images
/// actually render natively.
///
/// Zhihu ships every content image twice:
///
/// * once inside `<noscript>` as a no-JS fallback. HTML parsers treat
///   `noscript` content as plain text, so the body would render a literal
///   `<img src="…">` tag — with a perfectly correct URL — as text;
/// * once as a lazy-loaded `<img>` whose `src` is an inline
///   `data:image/svg+xml` placeholder while the loadable URL sits in the
///   `data-actualsrc` (720w preview) or `data-original` (full size)
///   attributes.
///
/// The sanitizer therefore strips the `noscript` copies and promotes the
/// lazy placeholder to a real image URL. Applied in [ZhihuAnswer.fromJson],
/// [ZhihuArticle.fromJson] and the service's feed parsing.
String zhihuSanitizeContentHtml(String html) {
  if (html.isEmpty) return html;
  var result = html.replaceAll(
    RegExp(r'<noscript[^>]*>[\s\S]*?</noscript>', caseSensitive: false),
    '',
  );
  result = result.replaceAllMapped(
    RegExp(r'<img\b[^>]*>', caseSensitive: false),
    (match) => _unlazyImage(match.group(0)!),
  );
  return result;
}

/// Returns the value of attribute [name] from a single-tag [tag] string,
/// honoring double or single quotes; null when absent.
String? _imageAttr(String tag, String name) {
  final match = RegExp("$name=(?:\"([^\"]*)\"|'([^']*)')").firstMatch(tag);
  if (match == null) return null;
  return match.group(1) ?? match.group(2);
}

/// Swaps an `<img>`'s inline-SVG lazy placeholder `src` for the URL in
/// `data-actualsrc` / `data-original`; other tags pass through untouched.
String _unlazyImage(String tag) {
  if (!tag.contains('data:image/svg')) return tag;
  final url =
      _imageAttr(tag, 'data-actualsrc') ?? _imageAttr(tag, 'data-original');
  if (url == null || url.isEmpty) return tag;
  return tag.replaceFirst(
    RegExp('src=("[^"]*"|\'[^\']*\')'),
    'src="$url"',
  );
}

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

/// One page of comments (or replies) below an answer.
class ZhihuCommentPage {
  const ZhihuCommentPage({
    required this.comments,
    required this.hasMore,
    this.total = 0,
  });

  final List<ZhihuComment> comments;

  /// Whether another page can be requested after this one.
  final bool hasMore;

  /// Server-reported total count of the thread, 0 when unknown.
  final int total;
}

/// A comment below an answer, or a reply nested under a comment.
///
/// The comments endpoints come in two shapes: the web client's
/// `root_comments` wraps the author in a `member` node and embeds the first
/// page of replies in `child_comments`, while the legacy `comments`
/// endpoint inlines the author and carries no replies. Both are accepted.
class ZhihuComment {
  const ZhihuComment({
    required this.id,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.contentHtml,
    required this.voteCount,
    required this.replyCount,
    required this.createdAtMs,
    required this.isContentAuthor,
    required this.replyTo,
    required this.replies,
  });

  factory ZhihuComment.fromJson(Map<String, dynamic> json) {
    var author = _asMap(json['author']);
    final member = _asMap(author['member']);
    if (member.isNotEmpty) author = member;
    final replyToRaw = json['reply_to'];
    return ZhihuComment(
      id: _asString(json['id']),
      authorName: _asString(author['name']),
      authorAvatarUrl: _asString(author['avatar_url']),
      // Comment bodies are plain text most of the time, but image stickers
      // and pasted rich text arrive as HTML — sanitize like answer bodies
      // so `<img>` / `<p>` render natively instead of as literal tags.
      contentHtml: zhihuSanitizeContentHtml(_asString(json['content'])),
      voteCount: _asInt(json['vote_count'] ?? json['likes_count']),
      replyCount: _asInt(json['reply_count']),
      createdAtMs: _asMs(_asInt(json['created_time'])),
      isContentAuthor: json['is_author'] == true,
      replyTo: replyToRaw is Map && replyToRaw['id'] != null
          ? ZhihuComment.fromJson(Map<String, dynamic>.from(replyToRaw))
          : null,
      replies: _parseReplies(json['child_comments']),
    );
  }

  /// Lifts the embedded first page of replies out of a `root_comments`
  /// payload's `child_comments` node; empty for the legacy shape.
  static List<ZhihuComment> _parseReplies(dynamic childComments) {
    if (childComments is! Map) return const [];
    final data = childComments['data'];
    if (data is! List) return const [];
    return [
      for (final entry in data)
        if (entry is Map && entry['id'] != null)
          ZhihuComment.fromJson(Map<String, dynamic>.from(entry)),
    ];
  }

  final String id;
  final String authorName;
  final String authorAvatarUrl;

  /// Body of the comment / reply: plain text most of the time, but image
  /// stickers and pasted rich text arrive as HTML — sanitized via
  /// [zhihuSanitizeContentHtml] and rendered natively (no WebView).
  final String contentHtml;

  final int voteCount;

  /// Total number of replies below this comment (top-level nodes only).
  final int replyCount;

  /// Creation time in milliseconds since epoch; 0 when unknown.
  final int createdAtMs;

  /// Whether the commenter is the answer's author (知乎「作者」标记).
  final bool isContentAuthor;

  /// For replies: the comment / reply this one answers; null for
  /// top-level comments. Only [authorName] is rendered.
  final ZhihuComment? replyTo;

  /// First page of replies when the payload embedded them; empty otherwise.
  final List<ZhihuComment> replies;
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
      contentHtml: zhihuSanitizeContentHtml(_asString(json['content'])),
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
      contentHtml: zhihuSanitizeContentHtml(_asString(json['content'])),
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

/// The signed-in Zhihu user profile (from `www.zhihu.com/api/v4/me`).
class ZhihuUser {
  const ZhihuUser({
    required this.id,
    required this.name,
    required this.headline,
    required this.avatarUrl,
    required this.urlToken,
  });

  factory ZhihuUser.fromJson(Map<String, dynamic> json) {
    return ZhihuUser(
      id: _asString(json['id']),
      name: _asString(json['name']),
      headline: _asString(json['headline']),
      avatarUrl: _asString(json['avatar_url']),
      urlToken: _asString(json['url_token']),
    );
  }

  final String id;
  final String name;
  final String headline;
  final String avatarUrl;
  final String urlToken;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'headline': headline,
      'avatar_url': avatarUrl,
      'url_token': urlToken,
    };
  }

  factory ZhihuUser.fromMap(Map<String, dynamic> map) {
    return ZhihuUser.fromJson(map);
  }
}

/// One entry of the personal recommend feed (登录后的首页推荐流).
class ZhihuFeedItem {
  const ZhihuFeedItem({
    required this.id,
    required this.type,
    required this.title,
    required this.excerpt,
    required this.contentHtml,
    required this.authorName,
    required this.authorHeadline,
    required this.authorAvatarUrl,
    required this.voteupCount,
    required this.commentCount,
    required this.questionId,
    required this.thumbnail,
  });

  final String id;

  /// Discriminator of the linked target: `answer`, `article`, `pin`, ...
  final String type;

  /// Question title for answers, article title otherwise; may be empty.
  final String title;

  final String excerpt;

  /// Rich-text body when the feed payload carried it (answers, articles,
  /// flattened pin nodes); empty otherwise.
  final String contentHtml;

  final String authorName;
  final String authorHeadline;
  final String authorAvatarUrl;
  final int voteupCount;
  final int commentCount;

  /// Question id for answer entries; empty for other types.
  final String questionId;

  final String thumbnail;

  bool get isArticle => type == 'article';

  bool get hasContent => contentHtml.isNotEmpty;

  String get webUrl {
    switch (type) {
      case 'article':
        return 'https://zhuanlan.zhihu.com/p/$id';
      case 'pin':
        return 'https://www.zhihu.com/pin/$id';
      default:
        if (questionId.isNotEmpty && id.isNotEmpty) {
          return 'https://www.zhihu.com/question/$questionId/answer/$id';
        }
        if (questionId.isNotEmpty) {
          return 'https://www.zhihu.com/question/$questionId';
        }
        return 'https://www.zhihu.com';
    }
  }
}

/// One page of the personal recommend feed.
class ZhihuFeedPage {
  const ZhihuFeedPage({
    required this.items,
    required this.hasMore,
    this.nextAfterId,
  });

  final List<ZhihuFeedItem> items;

  /// Whether another page can be requested after this one.
  final bool hasMore;

  /// Cursor for the next page (`after_id`), when the source provides one.
  final String? nextAfterId;
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
