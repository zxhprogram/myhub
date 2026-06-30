/// Data model for a bookmark received from the API.
class BookmarkModel {
  const BookmarkModel({
    this.id,
    required this.title,
    required this.url,
    required this.tags,
    required this.category,
    this.image = '',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String url;
  final List<String> tags;
  final String category;
  final String image;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory BookmarkModel.fromJson(Map<String, dynamic> json) {
    return BookmarkModel(
      id: json['id'] as int?,
      title: json['title'] as String,
      url: json['url'] as String,
      tags: (json['tags'] as List<dynamic>).cast<String>(),
      category: json['category'] as String,
      image: (json['image'] as String?) ?? '',
      sortOrder: (json['sortOrder'] as int?) ?? 0,
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
    'image': image,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  BookmarkModel copyWith({
    int? id,
    String? title,
    String? url,
    List<String>? tags,
    String? category,
    String? image,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BookmarkModel(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      image: image ?? this.image,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
