import 'dart:async';

import 'package:easy_mail/easy_mail.dart';

import '../models/mail_account_model.dart';
import 'mail_client.dart';

MailClient createMailClientImpl(MailAccount account) => _ImapMailClient(account);

class _ImapMailClient implements MailClient {
  _ImapMailClient(this._account);

  final MailAccount _account;
  ImapClient? _client;
  String? _selectedMailbox;

  @override
  bool get isConnected => _client?.isConnected ?? false;

  @override
  Future<void> connect() async {
    try {
      final client = ImapClient(
        host: _account.host,
        port: _account.port,
        tlsOptions: _account.useSsl
            ? TlsOptions.secureImplicit
            : TlsOptions.insecure,
      );
      await client.connect().timeout(const Duration(seconds: 30));
      _client = client;
    } on TimeoutException {
      throw MailException(
        'Connection timed out. Please check the server host, port, and network.',
        recoverable: true,
      );
    } on ImapException catch (e) {
      var message = 'Connection failed: ${e.message}';
      if (e.message.contains('Bad greeting')) {
        message = 'Connection failed: the server did not respond with a valid IMAP greeting. '
            'Please check that the incoming server host, port, and SSL/TLS setting are correct '
            '(e.g. imap.qq.com:993 with SSL enabled).';
      }
      throw MailException(message, recoverable: true);
    } catch (e) {
      throw MailException('Connection failed: $e', recoverable: true);
    }
  }

  @override
  Future<void> authenticate() async {
    final client = _client;
    if (client == null) {
      throw MailException('Not connected', recoverable: true);
    }
    try {
      await client.login(_account.username, _account.password).timeout(
        const Duration(seconds: 30),
      );
    } on TimeoutException {
      throw MailException('Authentication timed out.', recoverable: true);
    } on ImapException catch (e) {
      throw MailException('Authentication failed: ${e.message}', recoverable: false);
    }
  }

  @override
  Future<Map<int, MailEnvelope>> fetchEnvelopes(
    String folder, {
    int? limit,
  }) async {
    final client = await _ensureSelected(folder);
    try {
      final uids = await client.search(filter: 'ALL');
      // IMAP SEARCH returns UIDs in ascending order (oldest first). Take the
      // NEWEST [limit] messages by slicing from the end, matching the
      // behavior of the easy_mail example (uids.reversed.take(50)).
      final effectiveUids = limit != null && uids.length > limit
          ? uids.sublist(uids.length - limit)
          : uids;
      final result = <int, MailEnvelope>{};
      for (final uid in effectiveUids) {
        result[uid] = await client.fetchEnvelope(uid);
      }
      return result;
    } on ImapException catch (e) {
      throw MailException('Fetch failed: ${e.message}', recoverable: true);
    }
  }

  @override
  Future<MailMessage> fetchMessage(int uid) async {
    final client = _client;
    if (client == null) {
      throw MailException('Not connected', recoverable: true);
    }
    try {
      return await client.fetchMessage(uid);
    } on ImapException catch (e) {
      throw MailException('Fetch message failed: ${e.message}', recoverable: true);
    }
  }

  @override
  Future<void> markAsRead(int uid) async {
    final client = _client;
    if (client == null) {
      throw MailException('Not connected', recoverable: true);
    }
    try {
      await client.markSeen(uid);
    } on ImapException catch (e) {
      throw MailException('Mark seen failed: ${e.message}', recoverable: true);
    }
  }

  @override
  Future<List<int>> searchUnseen(String folder) async {
    final client = await _ensureSelected(folder);
    try {
      return await client.search(filter: 'UNSEEN');
    } on ImapException catch (e) {
      throw MailException('Search failed: ${e.message}', recoverable: true);
    }
  }

  @override
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    _selectedMailbox = null;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {
        // Best effort.
      }
    }
  }

  Future<ImapClient> _ensureSelected(String folder) async {
    final client = _client;
    if (client == null) {
      throw MailException('Not connected', recoverable: true);
    }
    if (_selectedMailbox != folder) {
      await client.selectMailbox(folder);
      _selectedMailbox = folder;
    }
    return client;
  }
}
