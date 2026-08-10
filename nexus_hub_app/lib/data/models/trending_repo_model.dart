/// A single trending GitHub repository returned by the githunt trending API.
class TrendingRepo {
  const TrendingRepo({
    required this.author,
    required this.name,
    required this.stars,
    required this.forks,
    required this.currentPeriodStars,
    this.avatar = '',
    this.url = '',
    this.description = '',
    this.language,
    this.languageColor = '',
    this.builtBy = const [],
  });

  factory TrendingRepo.fromJson(Map<String, dynamic> json) {
    return TrendingRepo(
      author: json['author'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
      url:
          json['url'] as String? ??
          (json['author'] != null && json['name'] != null
              ? 'https://github.com/${json['author']}/${json['name']}'
              : ''),
      description: json['description'] as String? ?? '',
      language: json['language'] as String?,
      languageColor: json['languagecolor'] as String? ?? '',
      stars: (json['stars'] as num?)?.toInt() ?? 0,
      forks: (json['forks'] as num?)?.toInt() ?? 0,
      currentPeriodStars: (json['currentperiodstars'] as num?)?.toInt() ?? 0,
      builtBy: (json['builtBy'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(TrendingContributor.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'author': author,
      'name': name,
      'avatar': avatar,
      'url': url,
      'description': description,
      'language': language,
      'languagecolor': languageColor,
      'stars': stars,
      'forks': forks,
      'currentperiodstars': currentPeriodStars,
      'builtBy': builtBy.map((c) => c.toJson()).toList(),
    };
  }

  final String author;
  final String name;
  final String avatar;
  final String url;
  final String description;
  final String? language;
  final String languageColor;
  final int stars;
  final int forks;
  final int currentPeriodStars;
  final List<TrendingContributor> builtBy;

  /// "owner/repo" shorthand used by GitHub trend lists.
  String get fullName => '$author/$name';

  bool get hasDescription => description.isNotEmpty;

  /// Formatted star count, e.g. "12.3k".
  String get formattedStars => _formatCount(stars);

  /// Formatted fork count, e.g. "1.2k".
  String get formattedForks => _formatCount(forks);

  /// Formatted current-period star count with sign, e.g. "+1.2k".
  String get formattedPeriodStars {
    final prefix = currentPeriodStars >= 0 ? '+' : '';
    return '$prefix${_formatCount(currentPeriodStars)}';
  }

  static String _formatCount(int count) {
    if (count < 1000) return '$count';
    if (count < 10000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '${(count / 1000).round()}k';
  }
}

/// A contributor whose avatar appears next to a trending repo.
class TrendingContributor {
  const TrendingContributor({
    required this.username,
    required this.href,
    required this.avatar,
  });

  factory TrendingContributor.fromJson(Map<String, dynamic> json) {
    return TrendingContributor(
      username: json['username'] as String? ?? '',
      href: json['href'] as String? ?? '',
      avatar: json['avatar'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'href': href,
      'avatar': avatar,
    };
  }

  final String username;
  final String href;
  final String avatar;
}