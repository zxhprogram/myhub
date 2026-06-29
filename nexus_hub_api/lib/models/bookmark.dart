import 'package:sqlite3/sqlite3.dart';

/// Bookmark domain model.
class Bookmark {
  const Bookmark({
    this.id,
    required this.title,
    required this.url,
    required this.tags,
    required this.category,
    this.image = '',
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String url;
  final List<String> tags;
  final String category;
  final String image;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Bookmark.fromRow(Row row) {
    return Bookmark(
      id: row['id'] as int,
      title: row['title'] as String,
      url: row['url'] as String,
      tags: (row['tags'] as String)
          .split(',')
          .where((t) => t.isNotEmpty)
          .toList(),
      category: row['category'] as String,
      image: (row['image'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'url': url,
    'tags': tags,
    'category': category,
    'image': image,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  Bookmark copyWith({
    int? id,
    String? title,
    String? url,
    List<String>? tags,
    String? category,
    String? image,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      image: image ?? this.image,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
