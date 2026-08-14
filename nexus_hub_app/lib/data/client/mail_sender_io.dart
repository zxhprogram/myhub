import 'dart:async';

import 'package:easy_mail/easy_mail.dart';

import '../models/mail_account_model.dart';
import 'mail_sender.dart';

MailSender createMailSenderImpl(MailAccount account) =>
    _SmtpMailSender(account);

class _SmtpMailSender implements MailSender {
  _SmtpMailSender(this._account);

  final MailAccount _account;

  @override
  Future<void> send({
    required List<String> to,
    List<String>? cc,
    required String subject,
    required String htmlBody,
    String? textBody,
  }) async {
    final fromAddress = MailAddress(address: _account.emailAddress);
    final recipients = <MailAddress>[
      ...to.where((e) => e.trim().isNotEmpty).map(
            (e) => MailAddress(address: e.trim()),
          ),
      ...?cc?.where((e) => e.trim().isNotEmpty).map(
            (e) => MailAddress(address: e.trim()),
          ),
    ];
    if (recipients.isEmpty) {
      throw MailSendException('No recipients specified.', recoverable: false);
    }

    final builder = MimeMessageBuilder()
        .from(fromAddress)
        .subject(subject)
        .html(htmlBody);
    if (textBody != null && textBody.isNotEmpty) {
      builder.text(textBody);
    }
    for (final recipient in to.where((e) => e.trim().isNotEmpty)) {
      builder.to(MailAddress(address: recipient.trim()));
    }
    if (cc != null) {
      for (final copy in cc.where((e) => e.trim().isNotEmpty)) {
        builder.cc(MailAddress(address: copy.trim()));
      }
    }
    final rawMessage = builder.build();

    final client = SmtpClient(
      host: _account.smtpHost,
      port: _account.smtpPort,
      tlsOptions: _resolveTlsOptions(_account),
    );

    try {
      await client.connect().timeout(const Duration(seconds: 30));
      await client
          .authenticate(PlainAuthenticator(_account.username, _account.password))
          .timeout(const Duration(seconds: 30));
      final response = await client
          .send(
            from: fromAddress,
            recipients: recipients,
            rawMessage: rawMessage,
          )
          .timeout(const Duration(seconds: 60));
      if (!response.isSuccess) {
        throw MailSendException(
          'Server rejected the message: ${response.code} ${response.message}',
          recoverable: true,
        );
      }
    } on TimeoutException {
      throw MailSendException(
        'Sending timed out. Please check your network and SMTP settings.',
        recoverable: true,
      );
    } on SmtpException catch (e) {
      throw MailSendException('SMTP error: ${e.message}', recoverable: true);
    } finally {
      try {
        await client.quit().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Best effort — the message was already sent (or failed).
      }
    }
  }

  TlsOptions _resolveTlsOptions(MailAccount account) {
    if (!account.smtpUseSsl) return TlsOptions.insecure;
    // Port 587 typically uses STARTTLS; port 465 uses implicit TLS.
    if (account.smtpPort == 587) return TlsOptions.secureStartTls;
    return TlsOptions.secureImplicit;
  }
}
