import '../models/key_stat_model.dart';
import '../services/local_database.dart';
import '../services/input_hook_service.dart';

/// Repository for persisting and querying key press statistics.
///
/// Storage uses Hive box `key_stats` with date strings (YYYY-MM-DD) as keys
/// and [DailyKeyStats] JSON as values.
class KeyStatsRepository {
  static const _boxName = 'key_stats';

  /// Record a single key press for today.
  static Future<void> recordKeyPress(int keyCode) async {
    final box = await LocalDatabase.box(_boxName);
    final today = _today();
    final raw = box.get(today);
    final dailyStats = raw != null
        ? DailyKeyStats.fromJson(Map<String, dynamic>.from(raw))
        : DailyKeyStats(date: today);

    final keyName = VirtualKey.name(keyCode);
    final existing = dailyStats.stats[keyCode];
    dailyStats.stats[keyCode] = KeyStatModel(
      keyCode: keyCode,
      keyName: keyName,
      pressCount: (existing?.pressCount ?? 0) + 1,
    );

    await box.put(today, dailyStats.toJson());
  }

  /// Get statistics for a specific date.
  /// Returns null if no data exists for that date.
  static Future<DailyKeyStats?> getStatsForDate(DateTime date) async {
    final box = await LocalDatabase.box(_boxName);
    final dateStr = _formatDate(date);
    final raw = box.get(dateStr);
    if (raw == null) return null;
    return DailyKeyStats.fromJson(Map<String, dynamic>.from(raw));
  }

  /// Get all available dates that have statistics records.
  static Future<List<String>> getAvailableDates() async {
    final box = await LocalDatabase.box(_boxName);
    final keys = box.keys.cast<String>().toList();
    keys.sort((a, b) => b.compareTo(a)); // newest first
    return keys;
  }

  /// Get statistics for all available dates (for aggregate views).
  static Future<List<DailyKeyStats>> getAllStats() async {
    final box = await LocalDatabase.box(_boxName);
    final dates = box.keys.cast<String>().toList();
    dates.sort();
    final result = <DailyKeyStats>[];
    for (final date in dates) {
      final raw = box.get(date);
      if (raw != null) {
        result.add(DailyKeyStats.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return result;
  }

  /// Clear all statistics (for testing).
  static Future<void> clearAll() async {
    final box = await LocalDatabase.box(_boxName);
    await box.clear();
  }

  static String _today() => _formatDate(DateTime.now());

  static String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
