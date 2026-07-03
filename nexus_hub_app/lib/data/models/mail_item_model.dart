import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_envelope.dart';

/// A lightweight, UI-ready mail item backed by an envelope.
class MailItem {
  const MailItem({
    required this.uid,
    required this.folder,
    required this.envelope,
    required this.isRead,
    required this.labels,
    required this.snippet,
  });

  final int uid;
  final String folder;
  final MailEnvelope envelope;
  final bool isRead;
  final List<String> labels;
  final String snippet;

  String get subject => envelope.subject;
  String get senderName => envelope.from.firstOrNull?.name ?? '';
  String get senderAddress => envelope.from.firstOrNull?.address ?? '';
  String get senderDisplay => envelope.from.firstOrNull?.toString() ?? '';
  DateTime? get date => envelope.date;

  factory MailItem.fromJson(Map<String, dynamic> json) {
    return MailItem(
      uid: json['uid'] as int,
      folder: json['folder'] as String,
      envelope: MailEnvelope.fromJson(
        jsonDecode(json['envelope_json'] as String) as Map<String, dynamic>,
      ),
      isRead: (json['is_read'] as int) == 1,
      labels: (json['labels'] as String).split(',').where((s) => s.isNotEmpty).toList(),
      snippet: json['snippet'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'folder': folder,
        'envelope_json': jsonEncode(envelope.toJson()),
        'is_read': isRead ? 1 : 0,
        'labels': labels.join(','),
        'snippet': snippet,
      };

  MailItem copyWith({
    int? uid,
    String? folder,
    MailEnvelope? envelope,
    bool? isRead,
    List<String>? labels,
    String? snippet,
  }) {
    return MailItem(
      uid: uid ?? this.uid,
      folder: folder ?? this.folder,
      envelope: envelope ?? this.envelope,
      isRead: isRead ?? this.isRead,
      labels: labels ?? this.labels,
      snippet: snippet ?? this.snippet,
    );
  }
}
