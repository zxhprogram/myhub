import '../models/network_traffic_model.dart';
import '../services/local_database.dart';

/// Repository for persisting and querying per-minute network traffic records.
///
/// Storage uses Hive box `network_traffic` with minute strings (`YYYY-MM-DD
/// HH:mm`) as keys and `{recv, sent}` maps as values, mirroring the
/// `key_stats` box pattern used by the key-stats repository.
class NetworkTrafficRepository {
  NetworkTrafficRepository._();

  static const _boxName = 'network_traffic';

  /// Record the bytes transferred during the minute containing [time].
  ///
  /// If a record for the same minute already exists the deltas are accumulated
  /// so overlapping write windows never lose data. Negative deltas (counter
  /// resets) are clamped to zero.
  static Future<void> recordMinute(
    DateTime time,
    int recvBytes,
    int sentBytes,
  ) async {
    final box = await LocalDatabase.box(_boxName);
    final key = _minuteKey(time);
    final raw = box.get(key) as Map?;
    final existingRecv = raw?['recv'] as int? ?? 0;
    final existingSent = raw?['sent'] as int? ?? 0;
    await box.put(key, {
      'recv': existingRecv + (recvBytes > 0 ? recvBytes : 0),
      'sent': existingSent + (sentBytes > 0 ? sentBytes : 0),
    });
  }

  /// All recorded minutes, oldest first.
  static Future<List<MinuteTraffic>> getAllRecords() async {
    final box = await LocalDatabase.box(_boxName);
    final records = <MinuteTraffic>[];
    for (final key in box.keys.cast<String>()) {
      final time = _parseMinuteKey(key);
      if (time == null) continue;
      final raw = box.get(key) as Map?;
      records.add(
        MinuteTraffic(
          time: time,
          recvBytes: raw?['recv'] as int? ?? 0,
          sentBytes: raw?['sent'] as int? ?? 0,
        ),
      );
    }
    records.sort((a, b) => a.time.compareTo(b.time));
    return records;
  }

  /// Aggregate summary across all recorded minutes.
  static Future<NetworkTrafficSummary> getSummary() async {
    final records = await getAllRecords();
    var recv = 0;
    var sent = 0;
    for (final r in records) {
      recv += r.recvBytes;
      sent += r.sentBytes;
    }
    return NetworkTrafficSummary(
      totalRecv: recv,
      totalSent: sent,
      recordCount: records.length,
    );
  }

  /// Per-day aggregates, oldest first. When [start]/[end] are given only
  /// minutes inside the inclusive range are aggregated.
  static Future<List<DailyTraffic>> getDailyTotals({
    DateTime? start,
    DateTime? end,
  }) async {
    final records = await getAllRecords();
    final byDate = <String, DailyTraffic>{};
    for (final r in records) {
      if (start != null && r.time.isBefore(start)) continue;
      if (end != null && r.time.isAfter(end)) continue;
      final key = _dateKey(r.time);
      final existing = byDate[key];
      byDate[key] = DailyTraffic(
        date: _dateOnly(r.time),
        recvBytes: (existing?.recvBytes ?? 0) + r.recvBytes,
        sentBytes: (existing?.sentBytes ?? 0) + r.sentBytes,
      );
    }
    final daily = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return daily;
  }

  /// Per-hour aggregates for a single day (24 slots, 0-23).
  static Future<List<HourlyTraffic>> getHourlyTotals(DateTime day) async {
    final box = await LocalDatabase.box(_boxName);
    final dateStr = _dateKey(day);
    final hourly = List.generate(
      24,
      (h) => HourlyTraffic(hour: h, recvBytes: 0, sentBytes: 0),
    );
    for (final key in box.keys.cast<String>()) {
      if (!key.startsWith(dateStr)) continue;
      final time = _parseMinuteKey(key);
      if (time == null) continue;
      final raw = box.get(key) as Map?;
      final recv = raw?['recv'] as int? ?? 0;
      final sent = raw?['sent'] as int? ?? 0;
      hourly[time.hour] = HourlyTraffic(
        hour: time.hour,
        recvBytes: hourly[time.hour].recvBytes + recv,
        sentBytes: hourly[time.hour].sentBytes + sent,
      );
    }
    return hourly;
  }

  /// Clear all records (for testing).
  static Future<void> clearAll() async {
    final box = await LocalDatabase.box(_boxName);
    await box.clear();
  }

  static String _minuteKey(DateTime time) =>
      '${_dateKey(time)} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  static String _dateKey(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime time) =>
      DateTime(time.year, time.month, time.day);

  static DateTime? _parseMinuteKey(String key) {
    final parts = key.split(' ');
    if (parts.length != 2) return null;
    final d = parts[0].split('-');
    final t = parts[1].split(':');
    if (d.length != 3 || t.length != 2) return null;
    return DateTime(
      int.parse(d[0]),
      int.parse(d[1]),
      int.parse(d[2]),
      int.parse(t[0]),
      int.parse(t[1]),
    );
  }
}
