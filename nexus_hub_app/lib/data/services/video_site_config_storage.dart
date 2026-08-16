import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_site_config.dart';

/// Persisted storage of the video sub-app's saved data sources.
///
/// Holds every [VideoSiteConfig] the user created plus which one is
/// active. An in-memory copy (see [sources] / [current]) lets the
/// [VideoSiteService] instances created by the browse, detail and play
/// pages pick up the active source synchronously — [load] only needs to
/// run once, from the video browse page.
class VideoSiteConfigStorage {
  VideoSiteConfigStorage._();

  static const _key = 'nexus_video_sources_v1';

  /// Key of the pre-multi-source format (a single config); imported on
  /// first load so nothing saved earlier is lost.
  static const _legacyKey = 'nexus_video_site_config_v1';

  static List<VideoSiteConfig> _sources = [];
  static String _activeId = VideoSiteConfig.defaultId;

  /// All saved sources in list order; unmodifiable.
  static List<VideoSiteConfig> get sources => List.unmodifiable(_sources);

  /// The active source: the one browsing and playback go through.
  /// Falls back to the built-in default until [load] ran (or if the
  /// persisted data is unusable).
  static VideoSiteConfig get current {
    return _sources
            .where((s) => s.id == _activeId)
            .firstOrNull ??
        VideoSiteConfig.defaultConfig;
  }

  /// Loads the persisted sources and the active one into memory.
  ///
  /// Storage failures never escape; the built-in default remains active
  /// instead.
  static Future<VideoSiteConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        _applyJson(jsonDecode(raw) as Map<String, dynamic>);
      } else {
        await _migrateLegacy(prefs);
      }
    } catch (_) {
      // Corrupt or unreadable preferences fall back to the defaults.
    }
    return current;
  }

  /// Adds [config] if its id is new, replaces the stored one with the
  /// same id otherwise, and optionally makes it active. Persists the
  /// result.
  static Future<void> upsert(
    VideoSiteConfig config, {
    bool activate = false,
  }) async {
    _sources = [
      for (final source in _sources)
        source.id == config.id ? config : source,
      if (!_sources.any((s) => s.id == config.id)) config,
    ];
    if (activate) {
      _activeId = config.id;
    } else if (_activeId.isEmpty) {
      _activeId = _sources.first.id;
    }
    await _persist();
  }

  /// Deletes the source with [id]. Deleting the active source activates
  /// the first remaining one; the last source is never deleted.
  static Future<void> remove(String id) async {
    if (_sources.length <= 1) return;
    _sources = [
      for (final source in _sources)
        if (source.id != id) source,
    ];
    if (_activeId == id) {
      _activeId = _sources.first.id;
    }
    await _persist();
  }

  /// Makes the source with [id] active. Persists the choice.
  static Future<void> setActive(String id) async {
    if (_sources.any((s) => s.id == id)) {
      _activeId = id;
      await _persist();
    }
  }

  static void _applyJson(Map<String, dynamic> json) {
    final loaded = (json['sources'] as List<dynamic>? ?? const [])
        .map((e) => VideoSiteConfig.fromJson(e as Map<String, dynamic>))
        .toList();
    if (loaded.isEmpty) return;
    _sources = loaded;
    final activeId = json['activeId'] as String? ?? '';
    _activeId = loaded.any((s) => s.id == activeId)
        ? activeId
        : loaded.first.id;
  }

  /// Imports the single-config format from before multiple sources were
  /// supported, keeping any customized domains.
  static Future<void> _migrateLegacy(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyKey);
    _sources = [
      VideoSiteConfig.defaultConfig,
      VideoSiteConfig.movie555DefaultConfig,
    ];
    _activeId = VideoSiteConfig.defaultId;
    if (raw != null && raw.isNotEmpty) {
      try {
        final legacy = VideoSiteConfig.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        final customized = legacy.domain != VideoSiteConfig.defaultDomain ||
            legacy.parseDomain != VideoSiteConfig.defaultParseDomain;
        if (customized) {
          _sources = [
            VideoSiteConfig.defaultConfig,
            VideoSiteConfig.movie555DefaultConfig,
            legacy.copyWith(
              id: VideoSiteConfig.generateId(),
              name: '导入的数据源',
            ),
          ];
          _activeId = _sources.last.id;
        }
      } catch (_) {
        // Unreadable legacy data leaves the default sources in place.
      }
    }
    await _persist();
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'version': 1,
          'activeId': _activeId,
          'sources': [for (final source in _sources) source.toJson()],
        }),
      );
    } catch (_) {
      // Ignore persistence failures (e.g. missing platform channel in tests).
    }
  }
}
