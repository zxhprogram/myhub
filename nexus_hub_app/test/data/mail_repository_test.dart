import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_address.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mime_part.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/client/mail_client.dart';
import 'package:nexus_hub_app/data/models/mail_account_model.dart';
import 'package:nexus_hub_app/data/repositories/mail_repository.dart';
import 'package:nexus_hub_app/data/services/local_database.dart';

class _FakeMailClient implements MailClient {
  bool _connected = false;
  final _unseen = <int>{1};

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    _connected = true;
  }

  @override
  Future<void> authenticate() async {}

  @override
  Future<Map<int, MailEnvelope>> fetchEnvelopes(
    String folder, {
    int? limit,
  }) async {
    return {1: _envelope(subject: 'Hello'), 2: _envelope(subject: 'Update')};
  }

  @override
  Future<MailMessage> fetchMessage(int uid, {String? folder}) async {
    return _message(uid: uid, subject: 'Hello', body: 'Body for $uid');
  }

  @override
  Future<void> markAsRead(int uid) async {
    _unseen.remove(uid);
  }

  @override
  Future<List<int>> searchUnseen(String folder) async => _unseen.toList();

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  MailEnvelope _envelope({required String subject}) => MailEnvelope(
    subject: subject,
    from: [const MailAddress(name: 'Sender', address: 'sender@example.com')],
    to: [const MailAddress(address: 'user@example.com')],
    date: DateTime.utc(2026, 6, 28, 10, 0),
  );

  MailMessage _message({
    required int uid,
    required String subject,
    required String body,
  }) {
    final envelope = _envelope(subject: subject);
    final root = MimePart(
      partId: '1',
      headers: const {'content-type': 'text/plain; charset=utf-8'},
      body: utf8.encode(body),
    );
    return MailMessage(
      envelope: envelope,
      root: root,
      plainTextBody: body,
      messageId: '<$uid@example.com>',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LocalDatabase.useInMemoryDatabaseForTesting();
    await LocalDatabase.clearAll();
  });

  group('MailRepository', () {
    late MailRepository repository;

    setUp(() {
      repository = MailRepository(
        account: const MailAccount(
          emailAddress: 'user@example.com',
          host: 'test.example.com',
          port: 993,
          username: 'user',
          password: 'pass',
        ),
        client: _FakeMailClient(),
      );
    });

    tearDown(() async {
      await repository.dispose();
    });

    test('fetchFolder returns messages and caches them', () async {
      final items = await repository.fetchFolder('INBOX');

      expect(items.length, 2);
      expect(items.map((e) => e.uid), containsAll([1, 2]));
      expect(items.every((e) => e.folder == 'INBOX'), isTrue);

      // Second call should serve from cache without re-fetching.
      final cached = await repository.fetchFolder('INBOX');
      expect(cached.length, 2);
    });

    test('search filters by subject', () async {
      await repository.fetchFolder('INBOX');

      final results = await repository.search('Update', 'INBOX');

      expect(results.length, 1);
      expect(results.first.subject, 'Update');
    });

    test('markAsRead updates unread counts', () async {
      await repository.fetchFolder('INBOX');
      final before = await repository.getUnreadCounts();
      expect(before['INBOX'], 1);

      await repository.markAsRead(1);
      final after = await repository.getUnreadCounts();
      // A count of zero is omitted from the grouped query result.
      expect(after['INBOX'], isNull);
    });

    test('fetchMessage returns full message', () async {
      final message = await repository.fetchMessage(1);

      expect(message.subject, 'Hello');
      expect(message.plainTextBody, 'Body for 1');
    });
  });
}
