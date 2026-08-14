/// Platform-agnostic mail sending interface.
abstract class MailSender {
  /// Sends an email with the given [to] recipients, [cc] copy recipients,
  /// [subject], and [htmlBody] content.
  ///
  /// [textBody] is an optional plain-text fallback for clients that do not
  /// support HTML.
  Future<void> send({
    required List<String> to,
    List<String>? cc,
    required String subject,
    required String htmlBody,
    String? textBody,
  });
}

/// Application-level exception wrapping SMTP protocol or network errors.
class MailSendException implements Exception {
  MailSendException(this.message, {this.recoverable = true});

  final String message;
  final bool recoverable;

  @override
  String toString() => 'MailSendException: $message';
}
