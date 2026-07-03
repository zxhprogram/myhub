// ignore: implementation_imports
import 'package:easy_mail/src/client/imap_client.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/security/tls_options.dart';

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
      await client.connect();
      _client = client;
    } on ImapException catch (e) {
      throw MailException('Connection failed: ${e.message}', recoverable: true);
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
      await client.login(_account.username, _account.password);
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
      final effectiveUids = limit != null && uids.length > limit
          ? uids.sublist(0, limit)
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
