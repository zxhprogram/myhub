import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/ssh_profile.dart';

/// Signals-based state for the Terminal app's saved SSH connection profiles.
///
/// Profiles persist across restarts via [SharedPreferences] (same approach as
/// [DesktopState]). Live terminal sessions are page-local and not persisted.
class TerminalState {
  TerminalState._();

  /// The singleton instance used across the app.
  static final TerminalState instance = TerminalState._();

  static const _storageKey = 'nexus_terminal_ssh_profiles_v1';

  static int _idCounter = 0;

  /// Saved SSH profiles, in the order they were created.
  final profiles = signal<List<SshProfile>>(const []);

  bool _initialized = false;

  /// Loads persisted profiles once; safe to call from every entry point.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      profiles.value = list
          .map((e) => SshProfile.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    } catch (_) {
      // Corrupted storage — start fresh rather than crash.
      profiles.value = const [];
    }
  }

  /// Adds a new profile (or replaces one with the same id) and persists.
  Future<void> addProfile(SshProfile profile) async {
    profiles.value = [...profiles.value, profile];
    await _persist();
  }

  /// Replaces the stored profile that shares [profile]'s id.
  Future<void> updateProfile(SshProfile profile) async {
    profiles.value = [
      for (final p in profiles.value)
        if (p.id == profile.id) profile else p,
    ];
    await _persist();
  }

  /// Removes the profile with [id].
  Future<void> deleteProfile(String id) async {
    profiles.value =
        profiles.value.where((p) => p.id != id).toList(growable: false);
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(profiles.value.map((p) => p.toJson()).toList()),
    );
  }

  /// Stable-enough id: timestamp prefix + monotonic counter.
  static String generateId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }
}
