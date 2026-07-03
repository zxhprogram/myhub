import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_address.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mime_part.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/data/client/mail_client.dart';
import 'package:nexus_hub_app/data/models/mail_account_model.dart';
import 'package:nexus_hub_app/data/repositories/mail_repository.dart';
import 'package:nexus_hub_app/data/services/local_database.dart';
import 'package:nexus_hub_app/presentation/pages/mail_page.dart';
import 'package:nexus_hub_app/presentation/states/mail_state.dart';

class _FakeMailClient implements MailClient {
  @override
  bool get isConnected => true;

  @override
  Future<void> connect() async {}

  @override
  Future<void> authenticate() async {}

  @override
  Future<Map<int, MailEnvelope>> fetchEnvelopes(
    String folder, {
    int? limit,
  }) async {
    return {
      1: _envelope('Inbox message'),
      2: _envelope('Another inbox'),
    };
  }

  @override
  Future<MailMessage> fetchMessage(int uid) async {
    return _message(uid);
  }

  @override
  Future<void> markAsRead(int uid) async {}

  @override
  Future<List<int>> searchUnseen(String folder) async => [1];

  @override
  Future<void> disconnect() async {}

  MailEnvelope _envelope(String subject) => MailEnvelope(
        subject: subject,
        from: [const MailAddress(name: 'Linear App', address: 'a@b.com')],
        to: [const MailAddress(address: 'user@example.com')],
        date: DateTime.now(),
      );

  MailMessage _message(int uid) {
    final body = 'Body for $uid';
    return MailMessage(
      envelope: _envelope('Inbox message'),
      root: MimePart(
        partId: '1',
        headers: const {'content-type': 'text/plain; charset=utf-8'},
        body: utf8.encode(body),
      ),
      plainTextBody: body,
    );
  }
}

MailRepository _makeRepository() => MailRepository(
      account: const MailAccount(
        host: 'test',
        port: 993,
        username: 'user',
        password: 'pass',
      ),
      client: _FakeMailClient(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LocalDatabase.useInMemoryDatabaseForTesting();
  });

  test('MailState loads inbox messages', () async {
    final state = MailState(repository: _makeRepository());
    await state.load();

    expect(state.emails.value.length, 2);
    expect(state.emails.value.first.senderName, 'Linear App');
    expect(state.unreadCounts.value['INBOX'], 1);
    expect(state.error.value, isNull);

    await state.dispose();
  });

  test('MailState selects a message and fetches body', () async {
    final state = MailState(repository: _makeRepository());
    await state.load();

    await state.selectEmail(state.emails.value.first);

    expect(state.selectedEmail.value, isNotNull);
    expect(state.selectedEmailMessage.value, isNotNull);
    expect(state.selectedEmailMessage.value!.plainTextBody, 'Body for 1');

    await state.dispose();
  });

  test('MailState switches folders', () async {
    final state = MailState(repository: _makeRepository());
    await state.load();
    expect(state.selectedFolder.value, 'INBOX');

    await state.loadFolder('SENT');

    expect(state.selectedFolder.value, 'SENT');
    expect(state.emails.value.length, 2);

    await state.dispose();
  });

  testWidgets('MailPage renders without error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MailPage(repository: _makeRepository())),
      ),
    );
    await tester.pump();

    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Inbox'), findsWidgets);
  });
}
