import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/zhihu_models.dart';

/// Persisted Zhihu web-session storage.
///
/// Holds the cookie jar captured from the WebView login page (keyed by
/// the presence of the `z_c0` session token) plus the signed-in user's
/// profile. An in-memory copy lets [ZhihuService] instances replay the
/// cookies synchronously as a `Cookie` request header — [load] only needs
/// to run once per app start (the service also awaits it before requests,
/// so pages never have to).
class ZhihuAuthStore {
  ZhihuAuthStore._();

  static const _key = 'nexus_zhihu_auth_v1';

  static String? _cookieHeader;
  static ZhihuUser? _user;
  static int _loginAtMs = 0;
  static Future<void>? _loading;

  /// Set by [logout] so the next login page opening clears the parked
  /// WebView's zhihu cookies — otherwise its still-valid session would
  /// auto-login instantly with the previous account.
  static bool _webSessionInvalidated = false;

  /// Cookie header of the stored web session (`name=value; ...`), or null
  /// when logged out.
  static String? get cookieHeader => _cookieHeader;

  /// The signed-in user's profile, when both known and logged in.
  static ZhihuUser? get user => isLoggedIn ? _user : null;

  /// Unix time (ms) of the login that produced the stored session.
  static int get loginAtMs => _loginAtMs;

  static bool get isLoggedIn {
    final header = _cookieHeader;
    return header != null &&
        header.contains(RegExp(r'(^|;\s*)z_c0='));
  }

  /// Loads the persisted session into memory; safe to call repeatedly.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final cookie = data['cookie'] as String?;
      if (cookie == null || cookie.isEmpty) return;
      _cookieHeader = cookie;
      _loginAtMs = (data['login_at'] as num?)?.toInt() ?? 0;
      final user = data['user'];
      if (user is Map) {
        _user = ZhihuUser.fromMap(Map<String, dynamic>.from(user));
      }
    } catch (_) {
      // Corrupt or unreadable preferences leave the store logged out.
    }
  }

  /// Stores a captured cookie jar as the active web session. The jar must
  /// contain the `z_c0` token — callers only invoke this after login was
  /// detected — otherwise it is rejected.
  static Future<void> save(String cookieHeader) async {
    if (!cookieHeader.contains(RegExp(r'(^|;\s*)z_c0='))) return;
    _cookieHeader = cookieHeader;
    _user = null;
    _loginAtMs = DateTime.now().millisecondsSinceEpoch;
    await _persist();
  }

  /// Caches the signed-in user's profile alongside the session.
  static Future<void> setUser(ZhihuUser user) async {
    if (!isLoggedIn) return;
    _user = user;
    await _persist();
  }

  /// Drops the stored session and profile.
  static Future<void> logout() async {
    _cookieHeader = null;
    _user = null;
    _loginAtMs = 0;
    _webSessionInvalidated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  /// Reads and resets the logout flag; consumed by the login page before
  /// it loads the sign-in URL.
  static bool consumeWebSessionInvalidated() {
    final value = _webSessionInvalidated;
    _webSessionInvalidated = false;
    return value;
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'version': 1,
          'cookie': _cookieHeader,
          'login_at': _loginAtMs,
          'user': _user?.toMap(),
        }),
      );
    } catch (_) {
      // Ignore persistence failures (e.g. missing platform channel).
    }
  }
}
