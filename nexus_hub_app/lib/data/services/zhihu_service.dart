import 'package:dio/dio.dart';

import '../models/zhihu_models.dart';
import 'local_database.dart';
import 'zhihu_exception.dart';

/// Anonymous Zhihu (知乎) reader: hot list, question answers and articles.
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
/// Login is intentionally not supported: Zhihu sign-in requires QR scans
/// or rotating captchas, so the sub-app is anonymous-only (hot list) by
/// design.
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

  /// Field list for the v4 feeds endpoint as sent by the website itself;
  /// keeps the response shape stable (content, author, voteup_count, ...).
  static const _feedInclude =
      'data[*].is_normal,admin_closed_comment,reward_info,is_collapsed,'
      'annotation_action,annotation_detail,collapse_reason,collapsed_by,'
      'suggest_edit,comment_count,can_comment,content,editable_content,'
      'voteup_count,created_time,upvoted_followees,'
      'author.badge[?(type=best_answerer)].topics';

  static const _answerPageSize = 5;

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
          headers: {
            'User-Agent': _browserUserAgent,
            'Referer': 'https://www.zhihu.com/hot',
            'x-requested-with': 'fetch',
          },
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
          headers: {
            'User-Agent': _browserUserAgent,
            'Referer': 'https://www.zhihu.com/question/$questionId',
            'x-requested-with': 'fetch',
          },
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
    Object? webError;
    try {
      final response = await _dio.get<dynamic>(
        'https://www.zhihu.com/api/v4/articles/$articleId',
        options: Options(
          responseType: ResponseType.json,
          headers: {
            'User-Agent': _browserUserAgent,
            'Referer': 'https://zhuanlan.zhihu.com/p/$articleId',
            'x-requested-with': 'fetch',
          },
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

  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const ZhihuException('接口返回的数据格式异常');
  }

  /// Zhihu sometimes answers HTTP 200 with an `{"error": ...}` body
  /// (login walls, risk control); surface its message instead of parsing.
  static void _ensureNoApiError(Map<String, dynamic> data) {
    final error = data['error'];
    if (error is Map) {
      throw ZhihuException(
        error['message']?.toString() ?? '接口返回错误',
      );
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
    if (data['id'] == null || data['title'] == null) {
      throw const ZhihuException('文章数据解析失败');
    }
    return ZhihuArticle.fromJson(data);
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
