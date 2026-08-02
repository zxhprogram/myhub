// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

/// Platform-agnostic mail client interface.
abstract class MailClient {
  Future<void> connect();
  Future<void> authenticate();
  Future<Map<int, MailEnvelope>> fetchEnvelopes(String folder, {int? limit});
  Future<MailMessage> fetchMessage(int uid, {String? folder});
  Future<void> markAsRead(int uid);
  Future<List<int>> searchUnseen(String folder);
  Future<void> disconnect();
  bool get isConnected;
}

/// Application-level exception wrapping protocol or network errors.
class MailException implements Exception {
  MailException(this.message, {this.recoverable = true});

  final String message;
  final bool recoverable;

  @override
  String toString() => 'MailException: $message';
}
