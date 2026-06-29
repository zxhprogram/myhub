/// Data model for a bookmark received from the API.
class BookmarkModel {
  const BookmarkModel({
    this.id,
    required this.title,
    required this.url,
    required this.tags,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String url;
  final List<String> tags;
  final String category;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BookmarkModel.fromJson(Map<String, dynamic> json) {
    return BookmarkModel(
      id: json['id'] as int?,
      title: json['title'] as String,
      url: json['url'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      category: json['category'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'tags': tags,
        'category': category,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
