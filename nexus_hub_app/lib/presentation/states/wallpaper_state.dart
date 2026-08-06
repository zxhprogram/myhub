import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/wallpaper_item.dart';
import '../../data/services/wallpaper_service.dart';

/// Signals-based state for the desktop wallpaper.
///
/// Holds the list of wallpapers available from the network source, the
/// currently applied wallpaper (persisted across restarts), and loading /
/// error state for the picker dialog.
class WallpaperState {
  WallpaperState._({WallpaperService? service})
      : _service = service ?? WallpaperService();

  /// The singleton instance used across the app.
  static final WallpaperState instance = WallpaperState._();

  static const _storageKey = 'nexus_wallpaper_v1';

  final WallpaperService _service;
  bool _initialized = false;

  /// Wallpapers available in the picker, newest first.
  final wallpapers = signal<List<WallpaperItem>>(const []);

  /// The currently applied wallpaper, or null for the default gradient.
  final currentWallpaper = signal<WallpaperItem?>(null);

  final isLoading = signal<bool>(false);
  final error = signal<String?>(null);

  /// Loads the persisted wallpaper and fetches the recent list.
  ///
  /// Idempotent: the network fetch runs only once for the process lifetime.
  /// Storage failures (e.g. no platform channel in tests) never escape.
  Future<void> init() async {
    try {
      final loaded = await _loadPersisted();
      if (loaded != null) {
        currentWallpaper.value = loaded;
      }
    } catch (_) {
      // Keep the default gradient; the user can still pick a wallpaper.
    }
    if (_initialized) {
      return;
    }
    _initialized = true;
    await refresh();
  }

  /// Fetches the recent wallpaper list, or sets [error] on failure.
  Future<void> refresh() async {
    isLoading.value = true;
    error.value = null;
    try {
      wallpapers.value = await _service.fetchRecent();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  /// Applies [item] as the desktop wallpaper and persists it.
  Future<void> setWallpaper(WallpaperItem item) async {
    currentWallpaper.value = item;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(item.toJson()));
  }

  /// Resets to the default gradient background.
  Future<void> clearWallpaper() async {
    currentWallpaper.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<WallpaperItem?> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        return null;
      }
      return WallpaperItem.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
