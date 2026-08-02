import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../models/global_index_model.dart';
import '../services/local_database.dart';

/// Service for fetching and caching global index data from fx678.
class GlobalIndexService {
  GlobalIndexService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _cacheKey = 'global_indices';
  static const _cacheTtl = Duration(minutes: 5);

  /// Returns cached indices if fresh, otherwise fetches from the web.
  Future<List<GlobalIndex>> fetchIndices() async {
    final cached = await _loadCached();
    if (cached != null) return cached;
    return _fetchAndCache();
  }

  /// Force-refresh from the web regardless of cache age.
  Future<List<GlobalIndex>> refreshIndices() async {
    return _fetchAndCache();
  }

  Future<List<GlobalIndex>> _fetchAndCache() async {
    final indices = await _fetchFromWeb();
    await _cacheIndices(indices);
    return indices;
  }

  Future<List<GlobalIndex>> _fetchFromWeb() async {
    final response = await _dio.get<String>(
      'https://quote.fx678.com/exchange/GJZS',
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/125.0.0.0 Safari/537.36',
        },
      ),
    );

    return _parseHtml(response.data ?? '');
  }

  /// Parses the HTML table from the fx678 page into a list of [GlobalIndex].
  ///
  /// The table has server-rendered rows like:
  /// ```html
  /// <tr id="NIKKI">
  ///   <td><a class="mar_name" href="https://quote.fx678.com/symbol/NIKKI">日经225</a></td>
  ///   <td>64362.02</td>
  ///   <td><span class="arrow_red">2494.59</span></td>
  ///   <td class="red_tab">4.03%</td>
  ///   <td>65364.73</td>
  ///   <td>61948.23</td>
  ///   <td>61867.43</td>
  ///   <td>05:58:27</td>
  /// </tr>
  /// ```
  List<GlobalIndex> _parseHtml(String html) {
    final indices = <GlobalIndex>[];

    // Match each <tr> that has an id attribute (the symbol), avoiding the
    // header row which has <th> instead of <td>.
    final rowPattern = RegExp(
      r'<tr\s+id="(\w+)"[^>]*>'
      r'(.*?)'
      r'</tr>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final rowMatch in rowPattern.allMatches(html)) {
      final symbol = rowMatch.group(1)!;
      final rowContent = rowMatch.group(2)!;

      // Skip header rows (they contain <th>, not <td>).
      if (!rowContent.contains('<td')) continue;

      // Extract all <td> cells.
      final cellPattern = RegExp(
        r'<td[^>]*>(.*?)</td>',
        caseSensitive: false,
        dotAll: true,
      );
      final cells = cellPattern
          .allMatches(rowContent)
          .map((m) => m.group(1)!.trim())
          .toList();

      if (cells.length < 8) continue;

      // Extract name from the first cell's <a> tag.
      final namePattern = RegExp(
        r'<a[^>]+href="(https://quote\.fx678\.com/symbol/[^"]+)"[^>]*>'
        r'(.*?)</a>',
        caseSensitive: false,
        dotAll: true,
      );
      final nameMatch = namePattern.firstMatch(cells[0]);
      if (nameMatch == null) continue;

      final detailUrl = nameMatch.group(1)!;
      final name = _stripHtml(nameMatch.group(2)!);

      final latestPrice = _parseNum(cells[1]);
      final change = _parseNum(cells[2]);
      final changePercent = _parseNum(cells[3]);
      final high = _parseNum(cells[4]);
      final low = _parseNum(cells[5]);
      final prevClose = _parseNum(cells[6]);
      final updateTime = _stripHtml(cells[7]);

      indices.add(GlobalIndex(
        symbol: symbol,
        name: name,
        latestPrice: latestPrice,
        change: change,
        changePercent: changePercent,
        high: high,
        low: low,
        prevClose: prevClose,
        updateTime: updateTime,
        detailUrl: detailUrl,
      ));
    }

    return indices;
  }

  double _parseNum(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\d.\-]'), '');
    return double.tryParse(cleaned) ?? 0.0;
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
  }

  Future<List<GlobalIndex>?> _loadCached() async {
    final box = await LocalDatabase.box('global_indices');
    final raw = box.get(_cacheKey);
    if (raw == null) return null;

    final data = Map<String, dynamic>.from(raw as Map);
    final cachedAt = (data['cached_at'] as num?)?.toInt() ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - cachedAt > _cacheTtl.inMilliseconds) return null;

    final list = data['indices'] as List<dynamic>;
    return list
        .cast<Map<String, dynamic>>()
        .map(GlobalIndex.fromJson)
        .toList();
  }

  Future<void> _cacheIndices(List<GlobalIndex> indices) async {
    final box = await LocalDatabase.box('global_indices');
    await box.put(_cacheKey, {
      'cached_at': DateTime.now().millisecondsSinceEpoch,
      'indices': indices.map((i) => i.toJson()).toList(),
    });
  }
}