import 'package:sqlite3/sqlite3.dart';

/// Clipboard history item domain model.
class ClipboardItem {
  const ClipboardItem({
    this.id,
    required this.content,
    required this.type,
    required this.createdAt,
  });

  final int? id;
  final String content;
  final String type;
  final DateTime createdAt;

  factory ClipboardItem.fromRow(Row row) {
    return ClipboardItem(
      id: row['id'] as int,
      content: row['content'] as String,
      type: row['type'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'type': type,
        'createdAt': createdAt.toIso8601String(),
      };
}
