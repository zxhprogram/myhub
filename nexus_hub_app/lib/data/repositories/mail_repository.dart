import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../client/mail_client.dart';
import '../client/mail_client_factory.dart';
import '../models/mail_account_model.dart';
import '../models/mail_item_model.dart';
import '../services/local_database.dart';

/// Repository that orchestrates mail fetching, caching, and mutations.
class MailRepository {
  MailRepository({
    required MailAccount account,
    MailClient? client,
  }) : _client = client ?? createMailClient(account);

  final MailClient _client;
  bool _initialized = false;

  /// Fetches messages for a folder, using cache unless [forceRefresh] is true.
  Future<List<MailItem>> fetchFolder(String folder, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await _loadCachedFolder(folder);
      if (cached.isNotEmpty) return cached;
    }

    await _ensureReady();

    try {
      final unseenUids = await _client.searchUnseen(folder);
      final envelopes = await _client.fetchEnvelopes(folder);
      final items = <MailItem>[];
      for (final entry in envelopes.entries) {
        final uid = entry.key;
        final envelope = entry.value;
        final message = await _client.fetchMessage(uid);
        final labels = _inferLabels(envelope, message);
        final snippet = _makeSnippet(message);
        items.add(
          MailItem(
            uid: uid,
            folder: folder,
            envelope: envelope,
            isRead: !unseenUids.contains(uid),
            labels: labels,
            snippet: snippet,
          ),
        );
      }
      await _cacheItems(items);
      return await _loadCachedFolder(folder);
    } on MailException {
      final cached = await _loadCachedFolder(folder);
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  /// Returns the full message for a UID, preferring cache.
  Future<MailMessage> fetchMessage(int uid) async {
    final cached = await _loadCachedMessage(uid);
    if (cached != null) return cached;

    await _ensureReady();
    final message = await _client.fetchMessage(uid);
    await _cacheMessage(uid, message);
    return message;
  }

  /// Marks a message as read both locally and on the server.
  Future<void> markAsRead(int uid) async {
    await _markLocalRead(uid, true);
    if (_client.isConnected) {
      try {
        await _client.markAsRead(uid);
      } on MailException {
        // Optimistic local update is kept; server will catch up next sync.
      }
    }
  }

  /// Searches cached messages in [folder] by subject, sender, or snippet.
  Future<List<MailItem>> search(String query, String folder) async {
    final lower = query.toLowerCase();
    final all = await _loadCachedFolder(folder);
    return all.where((item) {
      return item.subject.toLowerCase().contains(lower) ||
          item.senderDisplay.toLowerCase().contains(lower) ||
          item.snippet.toLowerCase().contains(lower);
    }).toList();
  }

  /// Returns unread counts per folder from the cache.
  Future<Map<String, int>> getUnreadCounts() async {
    final db = await LocalDatabase.instance;
    final rows = await db.rawQuery('''
      SELECT folder, COUNT(*) as cnt
      FROM mail_messages
      WHERE is_read = 0
      GROUP BY folder
    ''');
    final result = <String, int>{};
    for (final row in rows) {
      result[row['folder'] as String] = row['cnt'] as int;
    }
    return result;
  }

  /// Closes the underlying mail connection.
  Future<void> dispose() async {
    if (_client.isConnected) {
      await _client.disconnect();
    }
    _initialized = false;
  }

  Future<void> _ensureReady() async {
    if (_initialized) return;
    await _client.connect();
    await _client.authenticate();
    _initialized = true;
  }

  Future<List<MailItem>> _loadCachedFolder(String folder) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'mail_messages',
      where: 'folder = ?',
      whereArgs: [folder],
      orderBy: 'fetched_at DESC',
    );
    return rows.map(MailItem.fromJson).toList();
  }

  Future<MailMessage?> _loadCachedMessage(int uid) async {
    final db = await LocalDatabase.instance;
    final rows = await db.query(
      'mail_messages',
      where: 'uid = ?',
      whereArgs: [uid],
    );
    if (rows.isEmpty) return null;
    final json = rows.first['message_json'] as String?;
    if (json == null || json.isEmpty) return null;
    return MailMessage.fromJson(
      Map<String, dynamic>.from(
        // ignore: avoid_dynamic_calls
        const JsonCodec().decode(json) as Map,
      ),
    );
  }

  Future<void> _cacheItems(List<MailItem> items) async {
    final db = await LocalDatabase.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in items) {
      await db.insert(
        'mail_messages',
        {
          ...item.toJson(),
          'fetched_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _cacheMessage(int uid, MailMessage message) async {
    final db = await LocalDatabase.instance;
    await db.update(
      'mail_messages',
      {
        'message_json': const JsonCodec().encode(message.toJson()),
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'uid = ?',
      whereArgs: [uid],
    );
  }

  Future<void> _markLocalRead(int uid, bool read) async {
    final db = await LocalDatabase.instance;
    await db.update(
      'mail_messages',
      {'is_read': read ? 1 : 0},
      where: 'uid = ?',
      whereArgs: [uid],
    );
  }

  List<String> _inferLabels(MailEnvelope envelope, MailMessage message) {
    final text = '${envelope.subject} ${message.plainTextBody}'.toLowerCase();
    final from = envelope.from.firstOrNull?.address.toLowerCase() ?? '';
    final labels = <String>[];
    final workHints = [
      'linear',
      'stripe',
      'figma',
      'github',
      'design system',
      'security',
      'roadmap',
      'all-hands',
      'payout',
    ];
    final personalHints = ['medium', 'weekend', 'plans', 'personal'];
    if (workHints.any((hint) => text.contains(hint) || from.contains(hint))) {
      labels.add('Work');
    }
    if (personalHints.any((hint) => text.contains(hint) || from.contains(hint))) {
      labels.add('Personal');
    }
    return labels;
  }

  String _makeSnippet(MailMessage message) {
    final text = message.plainTextBody.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= 140) return text;
    return '${text.substring(0, 140)}...';
  }
}
