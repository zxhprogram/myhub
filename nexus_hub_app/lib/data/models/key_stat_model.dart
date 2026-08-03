/// Data model for a single key's press statistics on a given date.
class KeyStatModel {
  const KeyStatModel({
    required this.keyCode,
    required this.keyName,
    this.pressCount = 0,
  });

  final int keyCode;
  final String keyName;
  final int pressCount;

  factory KeyStatModel.fromJson(Map<String, dynamic> json) {
    return KeyStatModel(
      keyCode: json['keyCode'] as int,
      keyName: json['keyName'] as String,
      pressCount: json['pressCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'keyCode': keyCode,
    'keyName': keyName,
    'pressCount': pressCount,
  };

  KeyStatModel copyWith({int? pressCount}) {
    return KeyStatModel(
      keyCode: keyCode,
      keyName: keyName,
      pressCount: pressCount ?? this.pressCount,
    );
  }
}

/// Aggregated key statistics for a single day.
class DailyKeyStats {
  DailyKeyStats({required this.date, Map<int, KeyStatModel>? stats})
    : stats = stats ?? {};

  /// Date string in YYYY-MM-DD format.
  final String date;

  /// Map of keyCode -> KeyStatModel.
  final Map<int, KeyStatModel> stats;

  int get totalPresses => stats.values.fold(0, (sum, s) => sum + s.pressCount);

  factory DailyKeyStats.fromJson(Map<String, dynamic> json) {
    final statsMap = <int, KeyStatModel>{};
    final raw = (json['stats'] as Map?) ?? <dynamic, dynamic>{};
    for (final entry in raw.entries) {
      final keyCode = int.parse(entry.key);
      statsMap[keyCode] = KeyStatModel.fromJson(
        Map<String, dynamic>.from(entry.value),
      );
    }
    return DailyKeyStats(date: json['date'] as String, stats: statsMap);
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'stats': stats.map(
      (key, value) => MapEntry(key.toString(), value.toJson()),
    ),
  };
}
