import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_account_model.dart';

/// Persisted storage for the user's mail account configuration.
///
/// Uses shared_preferences to store the account JSON. Note that this keeps
/// the password in plain text on disk; if stronger protection is needed on
/// Windows, install the Visual Studio C++ ATL component and switch to
/// flutter_secure_storage.
class MailAccountStorage {
  static const _key = 'nexus_mail_account_v1';

  /// Loads the saved account, or returns an empty account if none exists.
  static Future<MailAccount> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return _emptyAccount();
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MailAccount.fromJson(json);
    } catch (_) {
      return _emptyAccount();
    }
  }

  /// Saves the account configuration to local preferences.
  static Future<void> save(MailAccount account) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(account.toJson()));
  }

  /// Clears any saved account configuration.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static MailAccount _emptyAccount() => const MailAccount(
        emailAddress: '',
        username: '',
        password: '',
        host: '',
        port: 993,
        smtpHost: '',
        smtpPort: 587,
      );
}
