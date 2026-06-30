import 'package:equatable/equatable.dart';

/// Clipboard history item model used by the frontend.
class ClipboardItemModel extends Equatable {
  const ClipboardItemModel({
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

  bool get hasFile => filePath != null && filePath!.isNotEmpty;
  bool get isImage => hasFile && (mimeType?.startsWith('image/') ?? false);

  factory ClipboardItemModel.fromJson(Map<String, dynamic> json) {
    return ClipboardItemModel(
      id: json['id'] as int?,
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      filePath: json['filePath'] as String?,
      mimeType: json['mimeType'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
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

  Map<String, dynamic> toDb() => {
        'id': id,
        'content': content,
        'type': type,
        'file_path': filePath,
        'mime_type': mimeType,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ClipboardItemModel.fromDb(Map<String, dynamic> row) {
    return ClipboardItemModel(
      id: row['id'] as int?,
      content: row['content'] as String,
      type: row['type'] as String,
      filePath: row['file_path'] as String?,
      mimeType: row['mime_type'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    );
  }

  ClipboardItemModel copyWith({
    int? id,
    String? content,
    String? type,
    String? filePath,
    String? mimeType,
    DateTime? createdAt,
  }) =>
      ClipboardItemModel(
        id: id ?? this.id,
        content: content ?? this.content,
        type: type ?? this.type,
        filePath: filePath ?? this.filePath,
        mimeType: mimeType ?? this.mimeType,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  List<Object?> get props =>
      [id, content, type, filePath, mimeType, createdAt];
}
