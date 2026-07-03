import '../models/mail_account_model.dart';
import 'mail_client.dart';
import 'mail_client_stub.dart'
    if (dart.library.io) 'mail_client_io.dart';

/// Creates a platform-appropriate [MailClient] for the given account.
///
/// On native platforms (dart:io) this uses a real IMAP client backed by
/// easy_mail. On Web this falls back to a stub client that returns mock data
/// so the UI remains runnable where dart:io sockets are unavailable.
MailClient createMailClient(MailAccount account) => createMailClientImpl(account);
