import 'package:flutter/foundation.dart';

/// A saved SSH connection profile used by the Terminal app to open remote
/// sessions.
///
/// The password is stored alongside the other fields in plain text (the same
/// trade-off as [MailAccountStorage]); switch to a secure storage package if
/// stronger protection is ever required.
@immutable
class SshProfile {
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String id;

  /// Display name shown in the sidebar and tab list.
  final String name;

  /// Remote host (IP or domain).
  final String host;

  /// Remote port, normally 22.
  final int port;

  /// Login account.
  final String username;

  /// Login password.
  final String password;

  /// `user@host:port` summary shown under the profile name.
  String get endpoint => '$username@$host:$port';

  SshProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
  }) {
    return SshProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  factory SshProfile.fromJson(Map<String, dynamic> json) {
    return SshProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 22,
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
      };
}
