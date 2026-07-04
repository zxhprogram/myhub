import 'dart:convert';

/// Configuration for an IMAP/POP3 and SMTP mail account.
class MailAccount {
  const MailAccount({
    required this.emailAddress,
    required this.username,
    required this.password,
    required this.host,
    required this.port,
    this.smtpHost = '',
    this.smtpPort = 587,
    this.smtpUseSsl = true,
    this.mailbox = 'INBOX',
    this.useSsl = true,
  });

  /// Full email address shown to the user (e.g. user@example.com).
  final String emailAddress;

  /// Login username for both IMAP and SMTP.
  final String username;

  /// Account password.
  final String password;

  /// Incoming mail server (IMAP/POP3) host.
  final String host;

  /// Incoming mail server port.
  final int port;

  /// Outgoing mail server (SMTP) host.
  final String smtpHost;

  /// Outgoing mail server port.
  final int smtpPort;

  /// Whether SMTP uses SSL/TLS.
  final bool smtpUseSsl;

  /// Default mailbox/folder to select.
  final String mailbox;

  /// Whether the incoming server uses SSL/TLS.
  final bool useSsl;

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    return MailAccount(
      emailAddress: json['emailAddress'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 993,
      smtpHost: json['smtpHost'] as String? ?? '',
      smtpPort: json['smtpPort'] as int? ?? 587,
      smtpUseSsl: json['smtpUseSsl'] as bool? ?? true,
      mailbox: json['mailbox'] as String? ?? 'INBOX',
      useSsl: json['useSsl'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'emailAddress': emailAddress,
        'username': username,
        'password': password,
        'host': host,
        'port': port,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpUseSsl': smtpUseSsl,
        'mailbox': mailbox,
        'useSsl': useSsl,
      };

  MailAccount copyWith({
    String? emailAddress,
    String? username,
    String? password,
    String? host,
    int? port,
    String? smtpHost,
    int? smtpPort,
    bool? smtpUseSsl,
    String? mailbox,
    bool? useSsl,
  }) {
    return MailAccount(
      emailAddress: emailAddress ?? this.emailAddress,
      username: username ?? this.username,
      password: password ?? this.password,
      host: host ?? this.host,
      port: port ?? this.port,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpUseSsl: smtpUseSsl ?? this.smtpUseSsl,
      mailbox: mailbox ?? this.mailbox,
      useSsl: useSsl ?? this.useSsl,
    );
  }

  /// Returns true when all required fields for receiving mail are present.
  bool get isValid {
    return emailAddress.trim().isNotEmpty &&
        username.trim().isNotEmpty &&
        password.isNotEmpty &&
        host.trim().isNotEmpty &&
        port > 0 &&
        port <= 65535 &&
        smtpHost.trim().isNotEmpty &&
        smtpPort > 0 &&
        smtpPort <= 65535;
  }

  @override
  String toString() => 'MailAccount($emailAddress @ $host:$port)';

  String toRawJson() => jsonEncode(toJson());
}
