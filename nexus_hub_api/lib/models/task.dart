import 'package:sqlite3/sqlite3.dart';

/// Task domain model.
class Task {
  const Task({
    this.id,
    required this.title,
    required this.description,
    required this.tag,
    required this.priority,
    required this.status,
    this.dueDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String description;
  final String tag;
  final String priority;
  final String status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Task.fromRow(Row row) {
    return Task(
      id: row['id'] as int,
      title: row['title'] as String,
      description: row['description'] as String,
      tag: row['tag'] as String,
      priority: row['priority'] as String,
      status: row['status'] as String,
      dueDate: row['due_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['due_date'] as int)
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'tag': tag,
        'priority': priority,
        'status': status,
        'dueDate': dueDate?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  Task copyWith({
    int? id,
    String? title,
    String? description,
    String? tag,
    String? priority,
    String? status,
    DateTime? dueDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      tag: tag ?? this.tag,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
