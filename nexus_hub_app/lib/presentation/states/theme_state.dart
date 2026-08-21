import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// Signals-based state for the application theme mode.
///
/// Persists the user's choice across restarts and reacts to system changes
/// when set to [ThemeMode.system].
class ThemeState {
  ThemeState._();

  /// The singleton instance used across the app.
  static final ThemeState instance = ThemeState._();

  static const _storageKey = 'nexus_theme_mode_v1';

  final themeMode = signal<ThemeMode>(ThemeMode.system);

  /// Loads the persisted theme mode.
  ///
  /// Storage failures never escape; the default remains [ThemeMode.system].
  Future<void> init() async {
    themeMode.value = await _load();
  }

  /// Sets and persists a new theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
    } catch (_) {
      // Ignore persistence failures (e.g. missing platform channel in tests).
    }
  }

  /// Cycles through light → dark → system → light.
  Future<void> toggle() async {
    final next = switch (themeMode.value) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    await setThemeMode(next);
  }

  Future<ThemeMode> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      return _parse(raw);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static ThemeMode _parse(String? value) {
    return ThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ThemeMode.system,
    );
  }
}
