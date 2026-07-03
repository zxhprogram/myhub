import 'dart:convert';

/// Configuration for an IMAP/POP3 mail account.
class MailAccount {
  const MailAccount({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.mailbox = 'INBOX',
    this.useSsl = true,
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String mailbox;
  final bool useSsl;

  factory MailAccount.fromJson(Map<String, dynamic> json) {
    return MailAccount(
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 993,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      mailbox: json['mailbox'] as String? ?? 'INBOX',
      useSsl: json['useSsl'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'mailbox': mailbox,
        'useSsl': useSsl,
      };

  MailAccount copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    String? mailbox,
    bool? useSsl,
  }) {
    return MailAccount(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      mailbox: mailbox ?? this.mailbox,
      useSsl: useSsl ?? this.useSsl,
    );
  }

  @override
  String toString() => 'MailAccount($username@$host:$port)';

  String toRawJson() => jsonEncode(toJson());
}
