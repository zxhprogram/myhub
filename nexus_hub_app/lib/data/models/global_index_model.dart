/// A single global index entry scraped from the fx678 quote page.
class GlobalIndex {
  GlobalIndex({
    required this.symbol,
    required this.name,
    required this.latestPrice,
    required this.change,
    required this.changePercent,
    required this.high,
    required this.low,
    required this.prevClose,
    this.updateTime = '',
    required this.detailUrl,
  });

  factory GlobalIndex.fromJson(Map<String, dynamic> json) {
    return GlobalIndex(
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      latestPrice: (json['latestPrice'] as num).toDouble(),
      change: (json['change'] as num).toDouble(),
      changePercent: (json['changePercent'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      prevClose: (json['prevClose'] as num).toDouble(),
      updateTime: (json['updateTime'] as String?) ?? '',
      detailUrl: json['detailUrl'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'symbol': symbol,
      'name': name,
      'latestPrice': latestPrice,
      'change': change,
      'changePercent': changePercent,
      'high': high,
      'low': low,
      'prevClose': prevClose,
      'updateTime': updateTime,
      'detailUrl': detailUrl,
    };
  }

  final String symbol;
  final String name;
  final double latestPrice;
  final double change;
  final double changePercent;
  final double high;
  final double low;
  final double prevClose;
  final String updateTime;
  final String detailUrl;

  bool get isUp => change >= 0;

  /// Formatted price string (e.g., "5,088.80").
  String get formattedPrice {
    final parts = latestPrice.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${buf.toString()}.${parts[1]}';
  }

  /// Formatted change string (e.g., "+52.13" or "-29.22").
  String get formattedChange {
    final prefix = isUp ? '+' : '';
    return '$prefix${change.toStringAsFixed(2)}';
  }

  /// Formatted change percent string (e.g., "+0.70%" or "-0.27%").
  String get formattedChangePercent {
    final prefix = isUp ? '+' : '';
    return '$prefix${changePercent.toStringAsFixed(2)}%';
  }
}