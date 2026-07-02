import 'package:sqlite3/sqlite3.dart';

/// Clipboard history item domain model.
class ClipboardItem {
  const ClipboardItem({
    this.id,
    required this.content,
    required this.type,
    this.filePath,
    this.mimeType,
    required this.createdAt,
  });

  final int? id;
  final String content;
  final String type;
  final String? filePath;
  final String? mimeType;
  final DateTime createdAt;

  factory ClipboardItem.fromRow(Row row) {
    return ClipboardItem(
      id: row['id'] as int,
      content: row['content'] as String,
      type: row['type'] as String,
      filePath: row['file_path'] as String?,
      mimeType: row['mime_type'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'type': type,
        'filePath': filePath,
        'mimeType': mimeType,
        'createdAt': createdAt.toIso8601String(),
      };
}
