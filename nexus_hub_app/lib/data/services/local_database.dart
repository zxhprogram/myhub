import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';

/// Local key-value storage backed by Hive boxes.
///
/// Replaces the previous SQLite-based [LocalDatabase]. Each former SQL table
/// is now a Hive [Box] storing JSON-compatible [Map<String, dynamic>] records.
class LocalDatabase {
  LocalDatabase._();

  static bool _initialized = false;
  static bool _testMode = false;
  static String? _testPath;

  static const _boxNames = <String>[
    'mail_messages',
    'tasks',
    'bookmarks',
    'clipboard',
    'collections',
    'bookmark_collections',
    'global_indices',
    'key_stats',
    'network_traffic',
    'trending_repos',
    'google_news',
  ];

  /// Use a temporary Hive directory for unit testing.
  ///
  /// Must be called before accessing [box] in tests to avoid platform
  /// channel dependencies such as path_provider.
  static void useInMemoryDatabaseForTesting() {
    _testMode = true;
  }

  /// Ensures Hive is initialized and all boxes are open.
  static Future<void> _ensureInit() async {
    if (_initialized) return;

    if (_testMode) {
      _testPath ??= (await Directory.systemTemp.createTemp('hive_test_')).path;
      Hive.init(_testPath!);
    } else {
      await Hive.initFlutter();
    }

    for (final name in _boxNames) {
      await Hive.openBox(name);
    }

    _initialized = true;
  }

  /// Returns the Hive [Box] for the given former table [name].
  static Future<Box> box(String name) async {
    await _ensureInit();
    return Hive.box(name);
  }

  /// Clears all records from every box. Useful for test isolation.
  static Future<void> clearAll() async {
    for (final name in _boxNames) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).clear();
      }
    }
  }

  /// Closes all boxes and resets initialization state.
  static Future<void> close() async {
    await Hive.close();
    _initialized = false;
    _testPath = null;
  }
}
