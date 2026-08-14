import '../models/mail_account_model.dart';
import 'mail_sender.dart';

MailSender createMailSenderImpl(MailAccount account) => _StubMailSender();

class _StubMailSender implements MailSender {
  @override
  Future<void> send({
    required List<String> to,
    List<String>? cc,
    required String subject,
    required String htmlBody,
    String? textBody,
  }) async {
    throw MailSendException(
      'Sending email is not supported on the Web platform.',
      recoverable: false,
    );
  }
}
