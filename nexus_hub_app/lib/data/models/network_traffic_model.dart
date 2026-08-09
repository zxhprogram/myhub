/// Traffic models used by the network monitor.
///
/// A [MinuteTraffic] captures the bytes transferred during one minute and is
/// persisted in the Hive box `network_traffic` keyed by `YYYY-MM-DD HH:mm`.
library;

/// Traffic recorded for a single minute.
class MinuteTraffic {
  const MinuteTraffic({
    required this.time,
    required this.recvBytes,
    required this.sentBytes,
  });

  final DateTime time;

  /// Bytes received during this minute.
  final int recvBytes;

  /// Bytes sent during this minute.
  final int sentBytes;

  int get totalBytes => recvBytes + sentBytes;

  factory MinuteTraffic.fromJson(Map<String, dynamic> json) {
    return MinuteTraffic(
      time: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
      recvBytes: (json['recv'] as int? ?? 0),
      sentBytes: (json['sent'] as int? ?? 0),
    );
  }

  Map<String, dynamic> toJson() => {
    't': time.millisecondsSinceEpoch,
    'recv': recvBytes,
    'sent': sentBytes,
  };
}

/// Per-day aggregate of minute records.
class DailyTraffic {
  const DailyTraffic({
    required this.date,
    required this.recvBytes,
    required this.sentBytes,
  });

  final DateTime date;
  final int recvBytes;
  final int sentBytes;

  int get totalBytes => recvBytes + sentBytes;
}

/// Per-hour aggregate of minute records for a single day.
class HourlyTraffic {
  const HourlyTraffic({
    required this.hour,
    required this.recvBytes,
    required this.sentBytes,
  });

  final int hour;
  final int recvBytes;
  final int sentBytes;

  int get totalBytes => recvBytes + sentBytes;
}

/// Aggregate summary of every recorded minute.
class NetworkTrafficSummary {
  const NetworkTrafficSummary({
    required this.totalRecv,
    required this.totalSent,
    required this.recordCount,
  });

  final int totalRecv;
  final int totalSent;
  final int recordCount;

  int get totalBytes => totalRecv + totalSent;
}

/// Formats a byte count into a compact human-readable string.
///
/// `bytes: 1536` → `1.5 KB`; when [perSecond] is true the unit gains a `/s`
/// suffix so the result can be reused for speed values.
String formatBytes(int bytes, {bool perSecond = false}) {
  if (bytes < 0) bytes = 0;
  if (bytes < 1024) {
    return '$bytes B${perSecond ? '/s' : ''}';
  }
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var i = -1;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  final unit = units[i] + (perSecond ? '/s' : '');
  return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} $unit';
}
