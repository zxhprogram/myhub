import 'package:dio/dio.dart';

import '../models/finance_calendar_model.dart';
import 'local_database.dart';

/// Service for the fx678 weekly financial calendar
/// (https://rl.fx678.com/Index_week.html).
///
/// The whole week is server-rendered as one `<table class="cjsj_tab">` per
/// day. Each day table starts with a date header row and then rows like:
/// ```html
/// <tr data-master="2" data-level="0" data-type="1" data-flag=0>
///   <td rowspan="2" class="rm tab_time tab_time...">07:50</td>
///   <td rowspan="2" class="rm tab_time tab_time...">
///     <div class="c_japan circle_flag"></div></td>
///   <td class="tab_font"><a href="/id/....html">日本 7月 ...</a></td>
///   <td class="previous_price">5.7</td>
///   <td class="survey_price"></td>
///   <td class="gb" id="...">5.4</td>   <!-- 公布值 -->
///   <td></td>                          <!-- 重要性 -->
///   <td><div class="getmore2">--</div></td>
///   ...
/// ```
/// Rows that continue a rowspan group carry no time/country cells, so the
/// last seen master values are inherited. Parsed with regular expressions,
/// matching the other fx678 scrapers (no HTML package dependency).
class FinanceCalendarService {
  FinanceCalendarService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _cacheKey = 'week';
  static const _cacheTtl = Duration(minutes: 30);

  /// Returns the cached week if fresh, otherwise fetches from the web.
  Future<List<FinanceCalendarDay>> fetchWeek() async {
    final cached = await _loadCached(ignoreTtl: false);
    if (cached != null) return cached;
    return _fetchAndCache();
  }

  /// Force-refresh from the web; falls back to stale cache on failure.
  Future<List<FinanceCalendarDay>> refreshWeek() async {
    try {
      return await _fetchAndCache();
    } catch (_) {
      final stale = await _loadCached(ignoreTtl: true);
      if (stale != null) return stale;
      rethrow;
    }
  }

  Future<List<FinanceCalendarDay>> _fetchAndCache() async {
    final days = await _fetchFromWeb();
    await _cacheDays(days);
    return days;
  }

  Future<List<FinanceCalendarDay>> _fetchFromWeb() async {
    final response = await _dio.get<String>(
      'https://rl.fx678.com/Index_week.html',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/125.0.0.0 Safari/537.36',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ),
    );

    final days = _parseHtml(response.data ?? '');
    if (days.isEmpty) {
      throw StateError('No calendar rows found on the page.');
    }
    return days;
  }

  List<FinanceCalendarDay> _parseHtml(String html) {
    final days = <FinanceCalendarDay>[];

    final datePattern = RegExp(
      r'<th colspan="9">\s*(\d{4}-\d{2}-\d{2})[^<（(]*[（(](周.)',
      caseSensitive: false,
    );
    final rowPattern = RegExp(
      r'<tr\b([^>]*)>(.*?)</tr>',
      caseSensitive: false,
      dotAll: true,
    );
    final cellPattern = RegExp(
      r'<td\b([^>]*)>(.*?)</td>',
      caseSensitive: false,
      dotAll: true,
    );
    final flagPattern = RegExp(r'c_(\w+)\s+circle_flag');
    final linkPattern = RegExp(r'<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>');
    final levelPattern = RegExp(r'data-level="(\d+)"');
    final typePattern = RegExp(r'data-type="(\d+)"');

    // One chunk per day table; chunks without a date header (holiday tables
    // at the bottom of the page) are skipped. The page renders the whole
    // week twice, so later duplicates of a date are dropped as well.
    final seenDates = <String>{};
    for (final chunk in html.split('<table class="cjsj_tab').skip(1)) {
      final dateMatch = datePattern.firstMatch(chunk);
      if (dateMatch == null) continue;
      if (!seenDates.add(dateMatch.group(1)!)) continue;

      var lastTime = '';
      var lastCountry = '';
      final events = <FinanceCalendarEvent>[];

      for (final rowMatch in rowPattern.allMatches(chunk)) {
        final rowAttrs = rowMatch.group(1) ?? '';
        final rowHtml = rowMatch.group(2)!;
        if (!rowHtml.contains('<td')) continue;

        var time = '';
        var country = '';
        var name = '';
        var detailUrl = '';
        var previousValue = '';
        var surveyValue = '';
        var actualValue = '';
        var importance = '';
        var nextCellIsImportance = false;

        for (final cellMatch in cellPattern.allMatches(rowHtml)) {
          final cellAttrs = cellMatch.group(1) ?? '';
          final cellHtml = cellMatch.group(2)!;

          if (nextCellIsImportance) {
            nextCellIsImportance = false;
            importance = _stripHtml(cellHtml);
            continue;
          }

          // The flag cell also carries the `tab_time` class, so test for
          // the country marker first.
          final flagMatch = flagPattern.firstMatch(cellHtml);
          if (flagMatch != null) {
            country = flagMatch.group(1)!;
          } else if (cellAttrs.contains('tab_time')) {
            time = _stripHtml(cellHtml);
          } else if (cellAttrs.contains('tab_font')) {
            final linkMatch = linkPattern.firstMatch(cellHtml);
            if (linkMatch != null) {
              detailUrl = _normalizeUrl(linkMatch.group(1)!);
              name = _stripHtml(linkMatch.group(2)!);
            } else {
              name = _stripHtml(cellHtml);
            }
          } else if (cellAttrs.contains('previous_price')) {
            previousValue = _stripHtml(cellHtml);
          } else if (cellAttrs.contains('survey_price')) {
            surveyValue = _stripHtml(cellHtml);
          } else if (RegExp(r'\bgb\b').hasMatch(cellAttrs)) {
            actualValue = _stripHtml(cellHtml);
            nextCellIsImportance = true;
          }
        }

        if (name.isEmpty) continue;

        // Sub-rows of a rowspan group inherit time and country from the
        // master row.
        if (time.isEmpty) time = lastTime;
        if (country.isEmpty) country = lastCountry;
        lastTime = time;
        lastCountry = country;

        if (importance.isEmpty && levelPattern.firstMatch(rowAttrs)?.group(1) == '1') {
          importance = '高';
        }

        events.add(FinanceCalendarEvent(
          time: time,
          countryCode: country,
          name: name,
          previousValue: previousValue,
          surveyValue: surveyValue,
          actualValue: actualValue,
          importance: importance,
          detailUrl: detailUrl,
          isKeyEvent: typePattern.firstMatch(rowAttrs)?.group(1) == '0',
        ));
      }

      if (events.isNotEmpty) {
        days.add(FinanceCalendarDay(
          dateLabel: dateMatch.group(1)!,
          weekday: dateMatch.group(2)!,
          events: events,
        ));
      }
    }

    return days;
  }

  String _normalizeUrl(String href) {
    if (href.startsWith('http')) return href;
    return 'https://rl.fx678.com$href';
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\s*--\s*'), '')
        .trim();
  }

  Future<List<FinanceCalendarDay>?> _loadCached({required bool ignoreTtl}) async {
    try {
      final box = await LocalDatabase.box('finance_calendar');
      final raw = box.get(_cacheKey);
      if (raw == null) return null;

      final data = Map<String, dynamic>.from(raw as Map);
      if (!ignoreTtl) {
        final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - cachedAt > _cacheTtl.inMilliseconds) return null;
      }

      final list = data['days'] as List<dynamic>;
      return list
          .cast<Map<String, dynamic>>()
          .map(FinanceCalendarDay.fromJson)
          .toList();
    } catch (_) {
      // Cache is an optimization only; fall through to the network.
      return null;
    }
  }

  Future<void> _cacheDays(List<FinanceCalendarDay> days) async {
    try {
      final box = await LocalDatabase.box('finance_calendar');
      await box.put(_cacheKey, {
        'cached_at': DateTime.now().millisecondsSinceEpoch,
        'days': days.map((d) => d.toJson()).toList(),
      });
    } catch (_) {
      // Cache is an optimization only; ignore write failures.
    }
  }
}
