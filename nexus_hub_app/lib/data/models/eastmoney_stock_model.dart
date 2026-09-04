// Models for Eastmoney (东方财富) quote APIs.
//
// Field values returned by the push2 endpoints use "-" for missing numbers,
// so all optional numerics are parsed via [numOrNull].

/// Watchlist category derived from the secid market prefix.
enum StockCategory { all, us, cn, indices }

/// Classifies a secid (e.g. `105.NVDA`, `1.000001`, `100.SPX`) into a filter
/// category. Markets 105/106/107 are US exchanges, 0/1 are 沪深 (SH/SZ),
/// 100 covers global indices; A-share indices follow code conventions
/// (`000xxx` on SH, `399xxx` on SZ).
StockCategory categoryOfSecid(String secid) {
  final dot = secid.indexOf('.');
  if (dot < 0) return StockCategory.cn;
  final market = int.tryParse(secid.substring(0, dot)) ?? -1;
  final code = secid.substring(dot + 1);

  switch (market) {
    case 105:
    case 106:
    case 107:
      return StockCategory.us;
    case 100:
      return StockCategory.indices;
    case 0:
      return code.startsWith('399') ? StockCategory.indices : StockCategory.cn;
    case 1:
      return code.startsWith('000') ? StockCategory.indices : StockCategory.cn;
    default:
      return StockCategory.cn;
  }
}

/// Real-time quote snapshot from the `ulist.np/get` endpoint.
class StockQuote {
  StockQuote({
    required this.secid,
    required this.code,
    required this.market,
    required this.name,
    required this.latestPrice,
    required this.change,
    required this.changePercent,
    this.volume,
    this.amount,
    this.amplitude,
    this.turnoverRate,
    this.peRatio,
    this.volumeRatio,
    this.high,
    this.low,
    this.open,
    required this.prevClose,
    this.totalMarketCap,
    this.floatMarketCap,
    this.updateTimeMs = 0,
  });

  final String secid;
  final String code;
  final int market;
  final String name;

  /// Latest price (f2).
  final double latestPrice;

  /// Change amount (f4) and percent (f3).
  final double change;
  final double changePercent;

  final double? volume; // f5 成交量（手/股）
  final double? amount; // f6 成交额
  final double? amplitude; // f7 振幅%
  final double? turnoverRate; // f8 换手率%
  final double? peRatio; // f9 市盈率(动)
  final double? volumeRatio; // f10 量比
  final double? high; // f15 最高
  final double? low; // f16 最低
  final double? open; // f17 今开
  final double prevClose; // f18 昨收
  final double? totalMarketCap; // f20 总市值
  final double? floatMarketCap; // f21 流通市值

  /// Update time as epoch seconds (f124).
  final int updateTimeMs;

  factory StockQuote.fromSecid(String secid) => StockQuote(
    secid: secid,
    code: secid.split('.').last,
    market: int.tryParse(secid.split('.').first) ?? 0,
    name: secid,
    latestPrice: 0,
    change: 0,
    changePercent: 0,
    prevClose: 0,
  );

  factory StockQuote.fromJson(String secid, Map<String, dynamic> json) {
    return StockQuote(
      secid: secid,
      code: json['f12']?.toString() ?? secid.split('.').last,
      market: numOrNull(json['f13'])?.toInt() ?? 0,
      name: json['f14']?.toString() ?? secid,
      latestPrice: numOrNull(json['f2']) ?? 0,
      change: numOrNull(json['f4']) ?? 0,
      changePercent: numOrNull(json['f3']) ?? 0,
      volume: numOrNull(json['f5']),
      amount: numOrNull(json['f6']),
      amplitude: numOrNull(json['f7']),
      turnoverRate: numOrNull(json['f8']),
      peRatio: numOrNull(json['f9']),
      volumeRatio: numOrNull(json['f10']),
      high: numOrNull(json['f15']),
      low: numOrNull(json['f16']),
      open: numOrNull(json['f17']),
      prevClose: numOrNull(json['f18']) ?? 0,
      totalMarketCap: numOrNull(json['f20']),
      floatMarketCap: numOrNull(json['f21']),
      updateTimeMs: (numOrNull(json['f124'])?.toInt() ?? 0) * 1000,
    );
  }

  bool get isUp => change > 0;
  bool get isDown => change < 0;

  StockCategory get category => categoryOfSecid(secid);
}

/// One intraday minute point from the `trends2/get` endpoint.
class MinutePoint {
  MinutePoint({
    required this.time,
    required this.price,
    required this.avgPrice,
  });

  /// Raw time string, e.g. `2026-09-01 21:30`.
  final String time;
  final double price;
  final double avgPrice;

  /// `HH:mm` label for axis rendering.
  String get timeLabel {
    final parts = time.split(' ');
    return parts.length > 1 ? parts[1] : time;
  }

  /// `MM-dd` label for multi-day trend rendering.
  String get dateLabel {
    final parts = time.split(' ');
    return parts.isNotEmpty ? parts[0] : time;
  }
}

/// Intraday trend series with the previous close used as the baseline.
class TrendData {
  TrendData({required this.preClose, required this.points});

  final double preClose;
  final List<MinutePoint> points;
}

/// One K-line bar from the `kline/get` endpoint.
class KlineBar {
  KlineBar({
    required this.date,
    required this.open,
    required this.close,
    required this.high,
    required this.low,
    this.volume,
    this.amount,
  });

  /// Raw date string, e.g. `2026-09-01`.
  final String date;
  final double open;
  final double close;
  final double high;
  final double low;
  final double? volume;
  final double? amount;

  bool get isUp => close >= open;
}

/// A search suggestion from the Eastmoney suggest API.
class StockSuggest {
  StockSuggest({
    required this.secid,
    required this.code,
    required this.name,
    required this.marketName,
  });

  /// Quote id usable as secid, e.g. `105.NVDA`.
  final String secid;
  final String code;
  final String name;
  final String marketName;

  factory StockSuggest.fromJson(Map<String, dynamic> json) {
    return StockSuggest(
      secid: json['QuoteID']?.toString() ?? '',
      code: json['Code']?.toString() ?? '',
      name: json['Name']?.toString() ?? '',
      marketName: json['SecurityTypeName']?.toString() ?? '',
    );
  }
}

/// Parses an API number that may arrive as `num`, numeric `String` or `-`.
double? numOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final cleaned = value.trim();
    if (cleaned.isEmpty || cleaned == '-') return null;
    return double.tryParse(cleaned);
  }
  return null;
}

/// Formats a large number with 万 / 亿 suffixes (e.g. 3327160000 -> 33.27亿).
String formatCompactNumber(double? value) {
  if (value == null) return '-';
  final abs = value.abs();
  if (abs >= 1000000000000) {
    return '${(value / 1000000000000).toStringAsFixed(2)}万亿';
  }
  if (abs >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(2)}亿';
  }
  if (abs >= 10000) {
    return '${(value / 10000).toStringAsFixed(2)}万';
  }
  return value.toStringAsFixed(0);
}
