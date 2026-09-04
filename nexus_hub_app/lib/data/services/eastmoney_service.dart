import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/eastmoney_stock_model.dart';
import '../services/local_database.dart';

/// Service for fetching quote data from the Eastmoney (东方财富) push2 APIs.
///
/// - Quotes:    https://push2.eastmoney.com/api/qt/ulist.np/get
/// - Intraday:  https://push2his.eastmoney.com/api/qt/stock/trends2/get
/// - K-line:    https://push2his.eastmoney.com/api/qt/stock/kline/get
/// - Search:    https://searchapi.eastmoney.com/api/suggest/get
class EastmoneyService {
  EastmoneyService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const _quoteBase = 'https://push2.eastmoney.com';
  static const _historyBase = 'https://push2his.eastmoney.com';
  static const _searchBase = 'https://searchapi.eastmoney.com';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/125.0.0.0 Safari/537.36',
    'Referer': 'https://quote.eastmoney.com/',
  };

  /// Default watchlist shown on first launch.
  static const defaultWatchlist = <String>[
    '1.000001', // 上证指数
    '0.399001', // 深证成指
    '1.000300', // 沪深300
    '0.399006', // 创业板指
    '100.SPX', // 标普500
    '100.NDX', // 纳斯达克100
    '100.DJIA', // 道琼斯
    '105.NVDA', // 英伟达
    '105.AAPL', // 苹果
    '106.TSLA', // 特斯拉
    '0.000001', // 平安银行
    '1.600519', // 贵州茅台
  ];

  static const _watchlistBox = 'stock_watchlist';
  static const _watchlistKey = 'secids';

  // ---------------------------------------------------------------- quotes

  /// Fetches real-time quotes for [secids]; returns a map keyed by secid.
  /// Secids missing from the response (delisted / invalid) are omitted.
  Future<Map<String, StockQuote>> fetchQuotes(List<String> secids) async {
    if (secids.isEmpty) return {};

    final response = await _dio.get<Map<String, dynamic>>(
      '$_quoteBase/api/qt/ulist.np/get',
      queryParameters: {
        'fltt': 2,
        'invt': 2,
        'secids': secids.join(','),
        'fields':
            'f2,f3,f4,f5,f6,f7,f8,f9,f10,f12,f13,f14,f15,f16,f17,f18,f20,f21,f124',
      },
      options: Options(headers: _headers),
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    final diff = data?['diff'] as List<dynamic>? ?? [];
    final quotes = <String, StockQuote>{};
    for (final item in diff) {
      if (item is! Map<String, dynamic>) continue;
      final quote = StockQuote.fromJson('', item);
      // f12/f13 give the code and market; rebuild the canonical secid.
      final secid = '${quote.market}.${quote.code}';
      quotes[secid] = StockQuote.fromJson(secid, item);
    }
    return quotes;
  }

  // ---------------------------------------------------------------- trends

  /// Fetches intraday minute data. [ndays] 1 = 当日分时, 5 = 5日分时.
  Future<TrendData> fetchTrends(String secid, {int ndays = 1}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_historyBase/api/qt/stock/trends2/get',
      queryParameters: {
        'secid': secid,
        'ndays': ndays,
        'iscr': 0,
        'fields1': 'f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58',
      },
      options: Options(headers: _headers),
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException('No trend data returned');
    }

    final preClose = numOrNull(data['preClose']) ?? 0;
    final trends = data['trends'] as List<dynamic>? ?? [];
    final points = trends
        .whereType<String>()
        .map(_parseTrendRow)
        .whereType<MinutePoint>()
        .toList();

    return TrendData(preClose: preClose, points: points);
  }

  /// Trend row format: `time,open,price,high,low,volume,amount,avg`.
  MinutePoint? _parseTrendRow(String row) {
    final parts = row.split(',');
    if (parts.length < 8) return null;
    return MinutePoint(
      time: parts[0],
      price: numOrNull(parts[2]) ?? 0,
      avgPrice: numOrNull(parts[7]) ?? 0,
    );
  }

  // ---------------------------------------------------------------- klines

  /// Fetches K-line bars. [klt]: 101=日K, 102=周K, 103=月K.
  Future<List<KlineBar>> fetchKlines(
    String secid, {
    required int klt,
    int limit = 120,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_historyBase/api/qt/stock/kline/get',
      queryParameters: {
        'secid': secid,
        'klt': klt,
        'fqt': 1,
        'end': '20500101',
        'lmt': limit,
        'fields1': 'f1,f2,f3,f4,f5,f6',
        'fields2': 'f51,f52,f53,f54,f55,f56,f57',
      },
      options: Options(headers: _headers),
    );

    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException('No kline data returned');
    }

    final klines = data['klines'] as List<dynamic>? ?? [];
    return klines
        .whereType<String>()
        .map(_parseKlineRow)
        .whereType<KlineBar>()
        .toList();
  }

  /// K-line row format: `date,open,close,high,low,volume,amount`.
  KlineBar? _parseKlineRow(String row) {
    final parts = row.split(',');
    if (parts.length < 5) return null;
    return KlineBar(
      date: parts[0],
      open: numOrNull(parts[1]) ?? 0,
      close: numOrNull(parts[2]) ?? 0,
      high: numOrNull(parts[3]) ?? 0,
      low: numOrNull(parts[4]) ?? 0,
      volume: numOrNull(parts.length > 5 ? parts[5] : '-'),
      amount: numOrNull(parts.length > 6 ? parts[6] : '-'),
    );
  }

  // ---------------------------------------------------------------- search

  /// Searches securities by code / name / pinyin.
  Future<List<StockSuggest>> search(String input) async {
    if (input.trim().isEmpty) return [];

    final response = await _dio.get<Map<String, dynamic>>(
      '$_searchBase/api/suggest/get',
      queryParameters: {
        'input': input.trim(),
        'type': 14,
        'token': 'D43BF722C8E33BDC906FB84D85E326E8',
        'count': 8,
      },
      options: Options(headers: _headers),
    );

    final table = response.data?['QuotationCodeTable'] as Map<String, dynamic>?;
    final dataList = table?['Data'] as List<dynamic>? ?? [];
    return dataList
        .whereType<Map<String, dynamic>>()
        .map(StockSuggest.fromJson)
        .where((s) => s.secid.isNotEmpty)
        .toList();
  }

  // ------------------------------------------------------------- watchlist

  /// Loads the persisted watchlist, falling back to [defaultWatchlist].
  Future<List<String>> loadWatchlist() async {
    final box = await LocalDatabase.box(_watchlistBox);
    final raw = box.get(_watchlistKey) as String?;
    if (raw == null || raw.isEmpty) return List.of(defaultWatchlist);

    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .cast<String>()
          .toList(growable: false);
      return list;
    } catch (_) {
      return List.of(defaultWatchlist);
    }
  }

  /// Persists the watchlist secids.
  Future<void> saveWatchlist(List<String> secids) async {
    final box = await LocalDatabase.box(_watchlistBox);
    await box.put(_watchlistKey, jsonEncode(secids));
  }
}
