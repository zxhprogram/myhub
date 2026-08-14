import 'dart:async';
import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

import '../client/mail_client.dart';
import '../client/mail_client_factory.dart';
import '../client/mail_sender.dart';
import '../client/mail_sender_factory.dart';
import '../models/mail_account_model.dart';
import '../models/mail_item_model.dart';
import '../services/local_database.dart';

/// Repository that orchestrates mail fetching, caching, and mutations.
class MailRepository {
  MailRepository({
    required MailAccount account,
    MailClient? client,
    MailSender? sender,
  })  : _client = client ?? createMailClient(account),
        _sender = sender ?? createMailSender(account);

  final MailClient _client;
  final MailSender _sender;
  bool _initialized = false;

  /// Fetches messages for a folder, using cache unless [forceRefresh] is true.
  ///
  /// Only fetches envelopes (headers) for the list view — full message bodies
  /// are fetched on-demand when the user opens a message. This avoids the
  /// freeze caused by downloading every full RFC822 message (with attachments)
  /// just to build the list.
  Future<List<MailItem>> fetchFolder(
    String folder, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = await _loadCachedFolder(folder);
      if (cached.isNotEmpty) return cached;
    }

    await _ensureReady();

    try {
      final unseenUids = await _client
          .searchUnseen(folder)
          .timeout(const Duration(seconds: 30));
      final envelopes = await _client
          .fetchEnvelopes(folder, limit: 50)
          .timeout(const Duration(seconds: 60));
      final items = <MailItem>[];
      for (final entry in envelopes.entries) {
        final uid = entry.key;
        final envelope = entry.value;
        final labels = _inferLabels(envelope);
        items.add(
          MailItem(
            uid: uid,
            folder: folder,
            envelope: envelope,
            isRead: !unseenUids.contains(uid),
            labels: labels,
            snippet: '',
          ),
        );
      }
      await _cacheItems(items);
      return await _loadCachedFolder(folder);
    } on MailException {
      final cached = await _loadCachedFolder(folder);
      if (cached.isNotEmpty) return cached;
      rethrow;
    } on TimeoutException {
      final cached = await _loadCachedFolder(folder);
      if (cached.isNotEmpty) return cached;
      throw MailException(
        'Timed out while fetching messages. Please check your network and try again.',
        recoverable: true,
      );
    }
  }

  /// Returns the full message for a UID, preferring cache.
  Future<MailMessage> fetchMessage(int uid, {String? folder}) async {
    final cached = await _loadCachedMessage(uid);
    if (cached != null) return cached;

    await _ensureReady();
    final message = await _client.fetchMessage(uid, folder: folder);
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
    final box = await LocalDatabase.box('mail_messages');
    final result = <String, int>{};
    for (final value in box.values) {
      final record = Map<String, dynamic>.from(value as Map);
      final isRead = (record['is_read'] as int) == 1;
      if (!isRead) {
        final folder = record['folder'] as String;
        result[folder] = (result[folder] ?? 0) + 1;
      }
    }
    return result;
  }

  /// Sends an email via SMTP.
  Future<void> sendMail({
    required List<String> to,
    List<String>? cc,
    required String subject,
    required String htmlBody,
    String? textBody,
  }) async {
    await _sender.send(
      to: to,
      cc: cc,
      subject: subject,
      htmlBody: htmlBody,
      textBody: textBody,
    );
  }

  /// Closes the underlying mail connection.
  Future<void> dispose() async {
    if (_client.isConnected) {
      await _client.disconnect();
    }
    _initialized = false;
  }

  Future<void> _ensureReady() async {
    // Check the actual connection state rather than a flag, because the
    // server may have dropped the connection since we last initialized.
    if (_client.isConnected) return;
    await _client.connect();
    await _client.authenticate();
    _initialized = true;
  }

  String _key(String folder, int uid) => '$folder:$uid';

  Future<List<MailItem>> _loadCachedFolder(String folder) async {
    final box = await LocalDatabase.box('mail_messages');
    final items = <MailItem>[];
    for (final value in box.values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['folder'] == folder) {
        items.add(MailItem.fromJson(record));
      }
    }
    items.sort((a, b) {
      final aDate = a.date?.millisecondsSinceEpoch ?? 0;
      final bDate = b.date?.millisecondsSinceEpoch ?? 0;
      return bDate.compareTo(aDate);
    });
    return items;
  }

  Future<MailMessage?> _loadCachedMessage(int uid) async {
    final box = await LocalDatabase.box('mail_messages');
    for (final value in box.values) {
      final record = Map<String, dynamic>.from(value as Map);
      if (record['uid'] == uid) {
        final json = record['message_json'] as String?;
        if (json == null || json.isEmpty) return null;
        return MailMessage.fromJson(
          Map<String, dynamic>.from(const JsonCodec().decode(json) as Map),
        );
      }
    }
    return null;
  }

  Future<void> _cacheItems(List<MailItem> items) async {
    final box = await LocalDatabase.box('mail_messages');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in items) {
      final record = Map<String, dynamic>.from(item.toJson());
      record['fetched_at'] = now;
      await box.put(_key(item.folder, item.uid), record);
    }
  }

  Future<void> _cacheMessage(int uid, MailMessage message) async {
    final box = await LocalDatabase.box('mail_messages');
    for (final key in box.keys) {
      final record = Map<String, dynamic>.from(box.get(key) as Map);
      if (record['uid'] == uid) {
        record['message_json'] = const JsonCodec().encode(message.toJson());
        record['fetched_at'] = DateTime.now().millisecondsSinceEpoch;
        await box.put(key, record);
        return;
      }
    }
  }

  Future<void> _markLocalRead(int uid, bool read) async {
    final box = await LocalDatabase.box('mail_messages');
    for (final key in box.keys) {
      final record = Map<String, dynamic>.from(box.get(key) as Map);
      if (record['uid'] == uid) {
        record['is_read'] = read ? 1 : 0;
        await box.put(key, record);
        return;
      }
    }
  }

  List<String> _inferLabels(MailEnvelope envelope) {
    final text = envelope.subject.toLowerCase();
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
    if (personalHints.any(
      (hint) => text.contains(hint) || from.contains(hint),
    )) {
      labels.add('Personal');
    }
    return labels;
  }
}
