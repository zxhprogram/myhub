import '../models/mail_account_model.dart';
import 'mail_sender.dart';
import 'mail_sender_stub.dart'
    if (dart.library.io) 'mail_sender_io.dart';

/// Creates a platform-appropriate [MailSender] for the given account.
///
/// On native platforms (dart:io) this uses a real SMTP client backed by
/// easy_mail. On Web this falls back to a stub that throws, since dart:io
/// sockets are unavailable.
MailSender createMailSender(MailAccount account) =>
    createMailSenderImpl(account);
