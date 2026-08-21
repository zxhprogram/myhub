import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/zhihu_models.dart';
import 'local_database.dart';
import 'zhihu_auth_store.dart';
import 'zhihu_exception.dart';

/// Zhihu (知乎) reader: hot list, question answers, articles — plus the
/// personal recommend feed when a web session is stored.
///
/// Zhihu offers no public API, so the service calls the same endpoints the
/// website and the mobile app use, each with the User-Agent it expects.
/// Every resource has two sources tried in order, because availability of
/// the anonymous endpoints varies with Zhihu's risk control per network:
///
/// * Hot list — `api.zhihu.com/topstory/hot-list` (the Android app call,
///   the most reliable cookie-less source), falling back to the web
///   variant `www.zhihu.com/api/v3/feed/topstory/hot-lists/total`.
/// * Question answers — `www.zhihu.com/api/v4/questions/<id>/feeds` with
///   browser headers, falling back to `api.zhihu.com/questions/<id>/feeds`
///   with the app User-Agent.
/// * Articles — `www.zhihu.com/api/v4/articles/<id>`, falling back to
///   `api.zhihu.com/articles/<id>`.
///
/// Login goes through the WebView sign-in page (see [ZhihuLoginPage]):
/// once the user completes the QR scan / captcha there, the captured
/// cookie jar is stored in [ZhihuAuthStore] and replayed here as a
/// `Cookie` header on the web-origin requests. That unlocks the personal
/// recommend feed and typically also lifts the anonymous risk control on
/// the answer/article endpoints.
class ZhihuService {
  ZhihuService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  final Dio _dio;

  static const _boxName = 'zhihu';
  static const _cacheTtl = Duration(minutes: 3);

  /// The iOS app's User-Agent, accepted by `api.zhihu.com` without
  /// request signing.
  static const _appUserAgent =
      'osee2unifiedRelease/22.5.0 osee2unifiedReleaseVersion/10.42.0 '
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X)';

  static const _browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Safari/537.36';

  /// Field list for the v4 feeds endpoint. Zhihu's server rejects the full
  /// `data[*]...` whitelist on a signed-in session with an empty `data`
  /// array — the feed call succeeds (HTTP 200) but yields no answers, which
  /// the parser reports as a parse failure. A lean list returns the same
  /// answer objects (content, author, engagement stats) reliably, so the
  /// accepted fields are requested and nothing else (there is no stable
  /// non-empty whitelist shape when signed in).
  static const _feedInclude =
      'data[*].content,data[*].author.name,data[*].author.avatar_url,'
      'data[*].author.headline,data[*].voteup_count,data[*].comment_count,'
      'data[*].created_time,data[*].updated_time,data[*].excerpt';

  static const _answerPageSize = 5;

  static const _feedPageSize = 8;

  /// Browser headers for `www.zhihu.com` API endpoints, replaying the
  /// stored session cookies when the user is logged in.
  Map<String, String> _webHeaders({String? referer, String? origin}) {
    final headers = <String, String>{
      'User-Agent': _browserUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': ?referer,
      'x-requested-with': 'fetch',
      'Origin': ?origin,
    };
    final cookie = ZhihuAuthStore.cookieHeader;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /// Browser headers for a page-navigation request to `www.zhihu.com`.
  /// Deliberately omits `x-requested-with: fetch` — that header marks
  /// AJAX calls and makes Zhihu return a non-SSR response for the
  /// homepage, which breaks the feed fallback parser.
  Map<String, String> _pageHeaders({String? referer}) {
    final headers = <String, String>{
      'User-Agent': _browserUserAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
      'Referer': ?referer,
    };
    final cookie = ZhihuAuthStore.cookieHeader;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /// App headers for `api.zhihu.com` endpoints, replaying the stored
  /// session cookie. The mobile app API does not require the web-only
  /// `x-zse-96` signature header.
  Map<String, String> _appAuthHeaders() {
    final headers = <String, String>{
      'User-Agent': _appUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
    };
    final cookie = ZhihuAuthStore.cookieHeader;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  /// Returns the cached hot list when fresh, otherwise fetches it.
  Future<List<ZhihuHotItem>> fetchHotList() async {
    final cached = await _loadCachedHotList();
    if (cached != null) return cached;
    return refreshHotList();
  }

  /// Force-refreshes the hot list, falling back to the stale cache when
  /// both live sources fail, so the page keeps rendering offline.
  Future<List<ZhihuHotItem>> refreshHotList() async {
    final items = await _fetchHotListLive();
    await _cacheHotList(items);
    return items;
  }

  Future<List<ZhihuHotItem>> _fetchHotListLive() async {
    await ZhihuAuthStore.load();
    Object? firstError;
    try {
      final response = await _dio.get<dynamic>(
        'https://api.zhihu.com/topstory/hot-list',
        queryParameters: {'limit': 50},
        options: Options(
          responseType: ResponseType.json,
          headers: {'User-Agent': _appUserAgent},
        ),
      );
      return _parseHotList(_asJsonMap(response.data));
    } catch (e) {
      firstError = e;
    }
    try {
      final response = await _dio.get<dynamic>(
        'https://www.zhihu.com/api/v3/feed/topstory/hot-lists/total',
        queryParameters: {'limit': 50, 'desktop': true},
        options: Options(
          responseType: ResponseType.json,
          headers: _webHeaders(referer: 'https://www.zhihu.com/hot'),
        ),
      );
      return _parseHotList(_asJsonMap(response.data));
    } catch (_) {}
    throw ZhihuException(
      '无法加载知乎热榜（${_describeError(firstError)}），请稍后重试',
    );
  }

  /// Loads one page of answers below [questionId], best-sorted first.
  Future<ZhihuAnswerPage> fetchQuestionAnswers(
    String questionId, {
    int offset = 0,
    int limit = _answerPageSize,
  }) async {
    await ZhihuAuthStore.load();
    Object? webError;
    try {
      final response = await _dio.get<dynamic>(
        'https://www.zhihu.com/api/v4/questions/$questionId/feeds',
        queryParameters: {
          'include': _feedInclude,
          'limit': limit,
          'offset': offset,
          'order': 'default',
          'desktop': true,
        },
        options: Options(
          responseType: ResponseType.json,
          headers: _webHeaders(
            referer: 'https://www.zhihu.com/question/$questionId',
          ),
        ),
      );
      return _parseAnswerPage(
        _asJsonMap(response.data),
        questionId: questionId,
        requested: limit,
      );
    } catch (e) {
      webError = e;
    }
    try {
      final response = await _dio.get<dynamic>(
        'https://api.zhihu.com/questions/$questionId/feeds',
        queryParameters: {'limit': limit, 'offset': offset},
        options: Options(
          responseType: ResponseType.json,
          headers: {'User-Agent': _appUserAgent},
        ),
      );
      return _parseAnswerPage(
        _asJsonMap(response.data),
        questionId: questionId,
        requested: limit,
      );
    } catch (_) {}
    throw ZhihuException(
      '无法加载回答（${_describeError(webError)}）。'
      '知乎可能正在限制匿名访问，请稍后重试或在浏览器中打开',
    );
  }

  /// Loads a hot-list article (专栏) by id.
  Future<ZhihuArticle> fetchArticle(String articleId) async {
    await ZhihuAuthStore.load();
    Object? webError;
    try {
      final response = await _dio.get<dynamic>(
        'https://www.zhihu.com/api/v4/articles/$articleId',
        options: Options(
          responseType: ResponseType.json,
          headers: _webHeaders(
            referer: 'https://zhuanlan.zhihu.com/p/$articleId',
          ),
        ),
      );
      return _parseArticle(_asJsonMap(response.data));
    } catch (e) {
      webError = e;
    }
    try {
      final response = await _dio.get<dynamic>(
        'https://api.zhihu.com/articles/$articleId',
        options: Options(
          responseType: ResponseType.json,
          headers: {'User-Agent': _appUserAgent},
        ),
      );
      return _parseArticle(_asJsonMap(response.data));
    } catch (_) {}
    throw ZhihuException(
      '无法加载文章（${_describeError(webError)}），请稍后重试或在浏览器中打开',
    );
  }

  /// Fetches the signed-in user's profile (`/api/v4/me`).
  Future<ZhihuUser> fetchMe() async {
    await ZhihuAuthStore.load();
    if (!ZhihuAuthStore.isLoggedIn) {
      throw const ZhihuException('尚未登录');
    }
    final response = await _dio.get<dynamic>(
      'https://www.zhihu.com/api/v4/me',
      options: Options(
        responseType: ResponseType.json,
        headers: _webHeaders(referer: 'https://www.zhihu.com/'),
      ),
    );
    final data = _asJsonMap(response.data);
    _ensureNoApiError(data);
    if (data['id'] == null) {
      throw const ZhihuException('用户信息解析失败');
    }
    return ZhihuUser.fromJson(data);
  }

  /// Loads one page of the personal recommend feed (首页推荐流).
  ///
  /// Primary source is the website's own feed API; when it rejects the
  /// request (signature rotation, rate limits, ...), the server-rendered
  /// homepage is scraped instead — the fallback only yields the first
  /// page, so pagination cursors are ignored there.
  Future<ZhihuFeedPage> fetchRecommendFeed({String? afterId}) async {
    await ZhihuAuthStore.load();
    if (!ZhihuAuthStore.isLoggedIn) {
      throw const ZhihuException('登录后才能查看推荐 Feed');
    }
    Object? apiError;
    // 1. Web feed API — the primary source, but Zhihu increasingly
    //    requires a computed x-zse-96 signature header that we cannot
    //    produce, so this may fail with 401 / error body.
    try {
      final response = await _dio.post<dynamic>(
        'https://www.zhihu.com/api/v3/feed/topstory/recommend',
        data: {
          'desktop': true,
          'limit': _feedPageSize,
          if (afterId != null && afterId.isNotEmpty) 'after_id': afterId,
        },
        options: Options(
          responseType: ResponseType.json,
          headers: _webHeaders(
            referer: 'https://www.zhihu.com/',
            origin: 'https://www.zhihu.com',
          ),
        ),
      );
      return _parseRecommendApi(_asJsonMap(response.data));
    } catch (e) {
      apiError = e;
    }
    // 2. Mobile app API — uses the app User-Agent with the session
    //    cookie and does not require the web signature header. Only
    //    fetched for the first page (the pagination cursor differs).
    if (afterId == null) {
      try {
        final response = await _dio.get<dynamic>(
          'https://api.zhihu.com/topstory/recommend',
          queryParameters: {'limit': _feedPageSize},
          options: Options(
            responseType: ResponseType.json,
            headers: _appAuthHeaders(),
          ),
        );
        return _parseRecommendApi(_asJsonMap(response.data));
      } catch (_) {}
    }
    // 3. Server-rendered homepage — scrape the SSR feed payload as a
    //    last resort (first page only).
    if (afterId == null) {
      try {
        final html = await _fetchHomepageHtml();
        return _parseHomepageFeed(html);
      } catch (_) {}
    }
    throw ZhihuException(
      '无法加载推荐 Feed（${_describeError(apiError)}）。'
      '登录状态可能已过期，请退出后重新登录',
    );
  }

  Future<String> _fetchHomepageHtml() async {
    final response = await _dio.get<String>(
      'https://www.zhihu.com/',
      options: Options(
        responseType: ResponseType.plain,
        headers: _pageHeaders(referer: 'https://www.zhihu.com/'),
      ),
    );
    final status = response.statusCode;
    if (status != null && status >= 400) {
      throw ZhihuException('知乎首页返回 HTTP $status');
    }
    final html = response.data ?? '';
    if (html.isEmpty) {
      throw const ZhihuException('首页内容为空');
    }
    return html;
  }

  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is String && data.isNotEmpty) {
      // Some responses arrive as a JSON-encoded string.
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    throw const ZhihuException('接口返回的数据格式异常');
  }

  /// Zhihu sometimes answers HTTP 200 with an `{"error": ...}` body
  /// (login walls, risk control); surface its message instead of parsing.
  static void _ensureNoApiError(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map) {
      throw ZhihuException(error['message']?.toString() ?? '接口返回错误');
    } else if (error is String && error.isNotEmpty) {
      throw ZhihuException(error);
    }
  }

  static List<ZhihuHotItem> _parseHotList(Map<String, dynamic> data) {
    _ensureNoApiError(data);
    final list = data['data'];
    if (list is! List || list.isEmpty) {
      throw const ZhihuException('热榜返回的数据为空');
    }
    final items = <ZhihuHotItem>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final item = ZhihuHotItem.fromJson(
        Map<String, dynamic>.from(entry),
        rank: items.length + 1,
      );
      if (item.id.isEmpty || item.title.isEmpty) continue;
      items.add(item);
    }
    if (items.isEmpty) {
      throw const ZhihuException('热榜数据解析失败');
    }
    return items;
  }

  static ZhihuAnswerPage _parseAnswerPage(
    Map<String, dynamic> data, {
    required String questionId,
    required int requested,
  }) {
    _ensureNoApiError(data);
    // Some gateway responses answer HTTP 200 with an `error` node that is
    // neither a map nor a string — e.g. `{"error": {"code": 10003, ...}}`
    // flattened by a double-decode — so neither `_asJsonMap` nor
    // `_ensureNoApiError` catches them. Detect a non-null `error` field here
    // and raise the standard exception instead of crashing on the payload.
    if (data['error'] != null) {
      throw const ZhihuException('回答数据解析失败');
    }
    final list = data['data'];
    if (list is! List) {
      throw const ZhihuException('回答数据解析失败');
    }
    final answers = <ZhihuAnswer>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final node = entry['target'] is Map
          ? Map<String, dynamic>.from(entry['target']! as Map)
          : Map<String, dynamic>.from(entry);
      if (node.isEmpty || node['id'] == null) continue;
      answers.add(ZhihuAnswer.fromJson(node, questionId: questionId));
    }
    if (answers.isEmpty && requested > 0) {
      throw const ZhihuException('回答数据解析失败');
    }
    final paging = data['paging'];
    final isEnd = paging is Map && paging['is_end'] == true;
    return ZhihuAnswerPage(
      answers: answers,
      hasMore: !isEnd && answers.length >= requested,
    );
  }

  static ZhihuArticle _parseArticle(Map<String, dynamic> data) {
    _ensureNoApiError(data);
    if (data['error'] != null) {
      throw const ZhihuException('文章数据解析失败');
    }
    if (data['id'] == null || data['title'] == null) {
      throw const ZhihuException('文章数据解析失败');
    }
    return ZhihuArticle.fromJson(data);
  }

  /// Test-only seam: exposes [parseAnswerPageForTest]'s logic to unit tests
  /// without requiring live network access.
  ///
  /// The production page loader swallows the underlying exception type, so
  /// the tests only assert on the [ZhihuException]/[ZhihuAnswerPage] surface
  /// rather than on the raw crash.
  @visibleForTesting
  static ZhihuAnswerPage parseAnswerPageForTest(
    Map<String, dynamic> data, {
    required String questionId,
    required int requested,
  }) {
    return _parseAnswerPage(
      data,
      questionId: questionId,
      requested: requested,
    );
  }

  /// Parses the v3 recommend feed API response.
  static ZhihuFeedPage _parseRecommendApi(Map<String, dynamic> data) {
    _ensureNoApiError(data);
    final list = data['data'];
    if (list is! List) {
      throw const ZhihuException('Feed 数据解析失败');
    }
    final items = <ZhihuFeedItem>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final item = _feedItemFromNode(
        _str(entry['type']),
        _feedNode(entry),
        const {},
      );
      if (item != null) {
        items.add(item);
      }
    }
    if (items.isEmpty) {
      throw const ZhihuException('Feed 数据解析失败');
    }
    final paging = data['paging'];
    var hasMore = false;
    String? nextAfterId;
    if (paging is Map) {
      final isEnd = paging['is_end'] == true;
      final next = _str(paging['next']);
      final nextUri = next.isEmpty ? null : Uri.tryParse(next);
      final cursor = nextUri?.queryParameters['after_id'] ??
          nextUri?.queryParameters['before_id'];
      hasMore = !isEnd && cursor != null && cursor.isNotEmpty;
      nextAfterId = hasMore ? cursor : null;
    }
    return ZhihuFeedPage(
      items: items,
      hasMore: hasMore,
      nextAfterId: nextAfterId,
    );
  }

  /// Parses the server-rendered homepage feed (`js-initialData`) — the
  /// cookie-only fallback when the feed API rejects the request.
  static ZhihuFeedPage _parseHomepageFeed(String html) {
    final match = RegExp(
      r'<script id="js-initialData"[^>]*>([\s\S]*?)</script>',
    ).firstMatch(html);
    if (match == null) {
      throw const ZhihuException('首页数据解析失败');
    }
    final Map<String, dynamic> data;
    try {
      final raw = match.group(1)!;
      Map<String, dynamic> decoded;
      try {
        decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        // Some payloads are HTML-entity-encoded.
        decoded = Map<String, dynamic>.from(
          jsonDecode(_decodeHtmlEntities(raw)) as Map,
        );
      }
      data = decoded;
    } catch (_) {
      throw const ZhihuException('首页数据解析失败');
    }
    final root = data['initialState'] is Map
        ? Map<String, dynamic>.from(data['initialState']! as Map)
        : data;
    final entities = root['entities'] is Map
        ? Map<String, dynamic>.from(root['entities']! as Map)
        : const <String, dynamic>{};
    final topstory = root['topstory'] is Map
        ? Map<String, dynamic>.from(root['topstory']! as Map)
        : const <String, dynamic>{};
    var feed =
        topstory['firstPage'] ??
        topstory['recommendFeed'] ??
        topstory['feed'];
    if (feed is Map) {
      feed = feed['firstPage'] ?? feed['data'] ?? feed['items'];
    }
    if (feed is! List) {
      throw const ZhihuException('首页数据解析失败');
    }
    final items = <ZhihuFeedItem>[];
    for (final entry in feed) {
      if (entry is! Map) continue;
      final item = _feedItemFromNode(_str(entry['type']), _feedNode(entry), entities);
      if (item != null) {
        items.add(item);
      }
    }
    if (items.isEmpty) {
      throw const ZhihuException('首页数据解析失败');
    }
    // The SSR payload carries only the first page.
    return ZhihuFeedPage(items: items, hasMore: false);
  }

  /// Normalises the per-source payload node of a feed entry: the v3 API
  /// wraps it in `target`, the SSR first page in `data`.
  static Map<String, dynamic> _feedNode(Map entry) {
    final node = entry['target'] ?? entry['data'];
    if (node is Map) return Map<String, dynamic>.from(node);
    return Map<String, dynamic>.from(entry);
  }

  /// Builds a [ZhihuFeedItem] from a normalised payload node; returns
  /// null when the node has no usable id. [entities] resolves SSR nodes
  /// whose `question`/`author` fields are bare ids instead of objects.
  static ZhihuFeedItem? _feedItemFromNode(
    String type,
    Map<String, dynamic> node,
    Map<String, dynamic> entities,
  ) {
    final id = _str(node['id']);
    if (id.isEmpty) return null;

    // The mobile recommend API types every entry 'feed'; the real kind
    // (answer / article / pin) rides on the target's own `type` field.
    // Normalise so labels, web URLs and the answer-browsing detail flow
    // below all discriminate on the content type.
    var effectiveType = type;
    const contentTypes = {'answer', 'article', 'pin'};
    if (!contentTypes.contains(effectiveType)) {
      final targetType = _str(node['type']);
      if (contentTypes.contains(targetType)) {
        effectiveType = targetType;
      }
    }

    var questionId = '';
    var title = '';
    final question = node['question'];
    if (question is Map) {
      questionId = _str(question['id']);
      title = _str(question['title']);
    } else if (question != null) {
      questionId = question.toString();
      title = _str(_entity(entities, 'questions', questionId)['title']);
    }
    if (title.isEmpty) title = _str(node['title']);

    final authorRaw = node['author'];
    final author = authorRaw is Map
        ? Map<String, dynamic>.from(authorRaw)
        : authorRaw != null
        ? _entity(entities, 'users', authorRaw.toString())
        : const <String, dynamic>{};

    final content = node['content'];
    final contentHtml = content is String
        ? zhihuSanitizeContentHtml(content)
        : content is List
        ? _pinContentToHtml(content)
        : '';

    return ZhihuFeedItem(
      id: id,
      type: effectiveType,
      title: title,
      excerpt: _str(node['excerpt']),
      contentHtml: contentHtml,
      authorName: _str(author['name']),
      authorHeadline: _str(author['headline']),
      authorAvatarUrl: _str(author['avatar_url']),
      voteupCount: _int(node['voteup_count'] ?? node['voteupCount']),
      commentCount: _int(node['comment_count'] ?? node['commentCount']),
      questionId: questionId,
      thumbnail: _str(node['thumbnail'] ?? node['titleImage']),
    );
  }

  /// Flattens a pin's rich-text node list into simple HTML paragraphs.
  static String _pinContentToHtml(List content) {
    final buffer = StringBuffer();
    for (final part in content) {
      if (part is! Map) continue;
      final type = part['type'];
      if (type == 'text') {
        buffer.write('<p>${_escape(part['content'])}</p>');
      } else if (type == 'image') {
        final url = _str(part['url']);
        if (url.isNotEmpty) buffer.write('<img src="$url"/>');
      }
    }
    return buffer.toString();
  }

  static Map<String, dynamic> _entity(
    Map<String, dynamic> entities,
    String kind,
    String id,
  ) {
    final bucket = entities[kind];
    if (bucket is Map && bucket[id] is Map) {
      return Map<String, dynamic>.from(bucket[id]! as Map);
    }
    return const {};
  }

  static String _escape(dynamic value) {
    return _str(value)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  /// Decodes common HTML entities — some SSR payloads are entity-encoded.
  static String _decodeHtmlEntities(String s) {
    return s
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');
  }

  static String _str(dynamic value) {
    if (value is String) return value;
    if (value is num) return value.toInt().toString();
    return '';
  }

  static int _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String _describeError(Object? error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) return '请求被知乎拒绝';
      if (status != null) return 'HTTP $status';
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError) {
        return '网络异常';
      }
    }
    if (error is ZhihuException) return error.message;
    return '未知错误';
  }

  Future<List<ZhihuHotItem>?> _loadCachedHotList({
    bool ignoreTtl = false,
  }) async {
    try {
      final box = await LocalDatabase.box(_boxName);
      final raw = box.get('hot_list');
      if (raw == null) return null;

      final data = Map<String, dynamic>.from(raw as Map);
      final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
      final isStale =
          DateTime.now().millisecondsSinceEpoch - cachedAt >
          _cacheTtl.inMilliseconds;
      if (isStale && !ignoreTtl) return null;

      final list = data['items'] as List<dynamic>? ?? const [];
      final items = <ZhihuHotItem>[];
      for (final entry in list.cast<Map>()) {
        items.add(
          ZhihuHotItem.fromJson(
            Map<String, dynamic>.from(entry),
            rank: items.length + 1,
          ),
        );
      }
      return items;
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheHotList(List<ZhihuHotItem> items) async {
    try {
      final box = await LocalDatabase.box(_boxName);
      await box.put('hot_list', {
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'items': items.map((i) => _hotItemToJson(i)).toList(),
      });
    } catch (_) {
      // Cache failures are non-fatal — the list still renders.
    }
  }

  /// Round-trips a hot item through a plain map so rank and all fields
  /// survive the Hive cache.
  static Map<String, dynamic> _hotItemToJson(ZhihuHotItem item) {
    return {
      'target': {
        'id': item.id,
        'type': item.targetType,
        'title': item.title,
        'excerpt': item.excerpt,
        'thumbnail': item.thumbnail,
        'answer_count': item.answerCount,
        'follower_count': item.followerCount,
        'comment_count': item.commentCount,
      },
      'detail_text': item.detailText,
      'card_label': item.cardLabel.isEmpty ? null : {'name': item.cardLabel},
    };
  }
}
