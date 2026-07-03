// ignore: implementation_imports
import 'package:easy_mail/src/models/attachment.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_address.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mime_part.dart';

import '../models/mail_account_model.dart';
import 'mail_client.dart';

MailClient createMailClientImpl(MailAccount account) => _StubMailClient(account);

class _StubMailClient implements MailClient {
  _StubMailClient(this._account);

  final MailAccount _account;
  final _unreadUids = <int>{1, 2};
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    await Future.delayed(const Duration(milliseconds: 400));
    _connected = true;
  }

  @override
  Future<void> authenticate() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (_account.username.isEmpty || _account.password.isEmpty) {
      throw MailException('Invalid credentials', recoverable: false);
    }
  }

  @override
  Future<Map<int, MailEnvelope>> fetchEnvelopes(
    String folder, {
    int? limit,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final messages = _messagesForFolder(folder);
    final result = <int, MailEnvelope>{};
    var count = 0;
    for (final entry in messages.entries) {
      if (limit != null && count >= limit) break;
      result[entry.key] = entry.value.envelope;
      count++;
    }
    return result;
  }

  @override
  Future<MailMessage> fetchMessage(int uid) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final all = _allMessages();
    final message = all[uid];
    if (message == null) {
      throw MailException('Message not found', recoverable: true);
    }
    return message;
  }

  @override
  Future<void> markAsRead(int uid) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _unreadUids.remove(uid);
  }

  @override
  Future<List<int>> searchUnseen(String folder) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final uids = _messagesForFolder(folder).keys.toSet();
    return _unreadUids.where(uids.contains).toList();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  Map<int, MailMessage> _messagesForFolder(String folder) {
    return Map.fromEntries(
      _allMessages().entries.where((e) => e.value._folder == folder),
    );
  }

  Map<int, MailMessage> _allMessages() => _stubMessages;
}

extension _FolderExt on MailMessage {
  static final _folders = <MailMessage, String>{};
  String get _folder => _folders[this] ?? 'INBOX';
  set _folder(String value) => _folders[this] = value;
}

MailMessage _message({
  required String folder,
  required int uid,
  required String subject,
  required String fromName,
  required String fromAddress,
  required String toAddress,
  required String body,
  required DateTime date,
  List<String> labels = const [],
  List<Attachment> attachments = const [],
}) {
  final envelope = MailEnvelope(
    subject: subject,
    from: [MailAddress(name: fromName, address: fromAddress)],
    to: [MailAddress(address: toAddress)],
    date: date,
    messageId: '<$uid@stub.nexus>',
  );

  final root = MimePart(
    partId: '1',
    headers: const {'content-type': 'text/plain; charset=utf-8'},
    body: body.codeUnits,
  );

  final message = MailMessage(
    envelope: envelope,
    root: root,
    plainTextBody: body,
    htmlBody: '<p>${body.replaceAll('\n', '<br>')}</p>',
    attachments: attachments,
    rawHeaders: const {},
    messageId: envelope.messageId,
  );
  message._folder = folder;
  return message;
}

final Map<int, MailMessage> _stubMessages = {
  1: _message(
    folder: 'INBOX',
    uid: 1,
    subject: 'New feature update: Project views are here',
    fromName: 'Linear App',
    fromAddress: 'updates@linear.app',
    toAddress: 'nexus.user@hub.io',
    body: 'Hi Team, we\'ve just rolled out significant updates to how you view your projects. Check out the new bento-style dashboard and let us know what you think.\n\nBest,\nLinear Team',
    date: DateTime.now().subtract(const Duration(hours: 2)),
    labels: ['Work'],
  ),
  2: _message(
    folder: 'INBOX',
    uid: 2,
    subject: 'Your weekly payout summary',
    fromName: 'Stripe',
    fromAddress: 'payouts@stripe.com',
    toAddress: 'nexus.user@hub.io',
    body: 'The summary of your payouts for the period ending November 14 is now available in your dashboard. Total processed: \$1,240.00.\n\nView dashboard for details.',
    date: DateTime.now().subtract(const Duration(days: 1)),
    labels: ['Work'],
  ),
  3: _message(
    folder: 'INBOX',
    uid: 3,
    subject: 'Nexus Hub: Design System v2.1 Feedback',
    fromName: 'Alex Rivera',
    fromAddress: 'alex.rivera@figma.com',
    toAddress: 'nexus.user@hub.io',
    body: 'Hey there,\n\nI\'ve just finished reviewing the latest iteration of the Nexus Hub Design System (v2.1). The move towards a more rigid 8px grid system is definitely paying off.\n\nA few specific points:\n- The SideNavBar separation logic feels much cleaner now.\n- We might need to adjust the primary-container contrast ratio for darker themes.\n- The new 2xl corner radius on cards really softens the industrial feel.\n\nLet\'s touch base tomorrow morning at 10 AM.\n\nBest regards,\nAlex Rivera\nSenior Product Designer',
    date: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
    labels: ['Work'],
  ),
  4: _message(
    folder: 'INBOX',
    uid: 4,
    subject: '[Security] New SSH key added',
    fromName: 'GitHub',
    fromAddress: 'noreply@github.com',
    toAddress: 'nexus.user@hub.io',
    body: 'A new public SSH key was added to your GitHub account (nexus-mac-m3). If you did not perform this action, please review your security settings immediately.\n\nGitHub Security',
    date: DateTime.now().subtract(const Duration(days: 3)),
    labels: ['Work'],
  ),
  5: _message(
    folder: 'INBOX',
    uid: 5,
    subject: '10 UI Trends to Watch in 2025',
    fromName: 'Medium Daily',
    fromAddress: 'daily@medium.com',
    toAddress: 'nexus.user@hub.io',
    body: 'From hyper-minimalism to advanced glassmorphism, here are the trends that will define digital interfaces next year. Read the full article on Medium.',
    date: DateTime.now().subtract(const Duration(days: 4)),
    labels: ['Personal'],
  ),
  6: _message(
    folder: 'SENT',
    uid: 6,
    subject: 'Re: Q4 roadmap',
    fromName: 'Nexus User',
    fromAddress: 'nexus.user@hub.io',
    toAddress: 'team@hub.io',
    body: 'Hi team,\n\nAttached is the updated Q4 roadmap. Please review and add your comments.\n\nThanks!',
    date: DateTime.now().subtract(const Duration(days: 2)),
    labels: ['Work'],
  ),
  7: _message(
    folder: 'SENT',
    uid: 7,
    subject: 'Weekend plans',
    fromName: 'Nexus User',
    fromAddress: 'nexus.user@hub.io',
    toAddress: 'friend@example.com',
    body: 'Hey! Are we still on for hiking this Saturday? Let me know by Thursday.',
    date: DateTime.now().subtract(const Duration(days: 5)),
    labels: ['Personal'],
  ),
  8: _message(
    folder: 'DRAFTS',
    uid: 8,
    subject: 'Draft: All-hands meeting notes',
    fromName: 'Nexus User',
    fromAddress: 'nexus.user@hub.io',
    toAddress: 'all@hub.io',
    body: 'Draft notes from today\'s all-hands meeting. Still need to fill in the action items.',
    date: DateTime.now().subtract(const Duration(hours: 5)),
    labels: ['Work'],
  ),
  9: _message(
    folder: 'TRASH',
    uid: 9,
    subject: 'Expired offer',
    fromName: 'Marketing Bot',
    fromAddress: 'promo@example.com',
    toAddress: 'nexus.user@hub.io',
    body: 'This offer has expired and the message was moved to trash.',
    date: DateTime.now().subtract(const Duration(days: 10)),
    labels: [],
  ),
  10: _message(
    folder: 'SPAM',
    uid: 10,
    subject: 'Congratulations! You won!',
    fromName: 'Spammy Prizes',
    fromAddress: 'prizes@spam.example',
    toAddress: 'nexus.user@hub.io',
    body: 'Click here to claim your prize. This message was filtered as spam.',
    date: DateTime.now().subtract(const Duration(days: 2)),
    labels: [],
  ),
};
