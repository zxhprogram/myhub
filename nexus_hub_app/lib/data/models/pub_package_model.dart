/// A package listed by the pub.dev packages API (newest published first).
class PubPackage {
  const PubPackage({
    required this.name,
    required this.version,
    this.description = '',
    this.topics = const [],
    this.homepage = '',
  });

  /// Parses one entry of the `GET https://pub.dev/api/packages` response:
  /// `{name, latest: {version, pubspec: {description, topics, homepage}}}`.
  factory PubPackage.fromJson(Map<String, dynamic> json) {
    final latest = json['latest'] as Map<String, dynamic>?;
    final pubspec = latest?['pubspec'] as Map<String, dynamic>?;
    final name = json['name'] as String? ?? pubspec?['name'] as String? ?? '';
    return PubPackage(
      name: name,
      version: latest?['version'] as String? ?? '',
      description: pubspec?['description'] as String? ?? '',
      topics: (pubspec?['topics'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      homepage: pubspec?['homepage'] as String? ?? '',
    );
  }

  /// Flat encoding used by the Hive cache in [PubDevService].
  factory PubPackage.fromCacheJson(Map<String, dynamic> json) {
    return PubPackage(
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      description: json['description'] as String? ?? '',
      topics: (json['topics'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      homepage: json['homepage'] as String? ?? '',
    );
  }

  Map<String, dynamic> toCacheJson() {
    return {
      'name': name,
      'version': version,
      'description': description,
      'topics': topics,
      'homepage': homepage,
    };
  }

  final String name;
  final String version;
  final String description;
  final List<String> topics;
  final String homepage;

  /// Canonical pub.dev page for the package, used when the card is tapped.
  String get url => 'https://pub.dev/packages/$name';

  bool get hasDescription => description.isNotEmpty;
}

/// A single released version of a package, from the package detail API.
class PubPackageVersion {
  const PubPackageVersion({required this.version, this.published, this.description = ''});

  factory PubPackageVersion.fromJson(Map<String, dynamic> json) {
    final pubspec = json['pubspec'] as Map<String, dynamic>?;
    return PubPackageVersion(
      version: json['version'] as String? ?? '',
      published: DateTime.tryParse(json['published'] as String? ?? ''),
      description: pubspec?['description'] as String? ?? '',
    );
  }

  final String version;
  final DateTime? published;
  final String description;

  bool get hasDescription => description.isNotEmpty;
}

/// Pana/pub.dev score metrics, from `GET /api/packages/<name>/score`.
class PubPackageScore {
  const PubPackageScore({
    this.grantedPoints = 0,
    this.maxPoints = 0,
    this.likeCount = 0,
    this.downloadCount30Days = 0,
  });

  factory PubPackageScore.fromJson(Map<String, dynamic> json) {
    return PubPackageScore(
      grantedPoints: (json['grantedPoints'] as num?)?.toInt() ?? 0,
      maxPoints: (json['maxPoints'] as num?)?.toInt() ?? 0,
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      downloadCount30Days: (json['downloadCount30Days'] as num?)?.toInt() ?? 0,
    );
  }

  final int grantedPoints;
  final int maxPoints;
  final int likeCount;
  final int downloadCount30Days;
}

/// Full native-rendered package detail: latest metadata, all versions and
/// score metrics (no webview involved).
class PubPackageDetail {
  const PubPackageDetail({
    required this.name,
    required this.version,
    this.description = '',
    this.topics = const [],
    this.homepage = '',
    this.repository = '',
    this.published,
    this.versions = const [],
    this.score,
    this.readmeHtml = '',
  });

  factory PubPackageDetail.fromApi({
    required Map<String, dynamic> json,
    PubPackageScore? score,
    String readmeHtml = '',
  }) {
    final latest = json['latest'] as Map<String, dynamic>?;
    final pubspec = latest?['pubspec'] as Map<String, dynamic>?;
    final versions = (json['versions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PubPackageVersion.fromJson)
        .where((v) => v.version.isNotEmpty)
        .toList();
    return PubPackageDetail(
      name: json['name'] as String? ?? '',
      version: latest?['version'] as String? ?? '',
      description: pubspec?['description'] as String? ?? '',
      topics: (pubspec?['topics'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      homepage: pubspec?['homepage'] as String? ?? '',
      repository: pubspec?['repository'] as String? ?? '',
      published: DateTime.tryParse(latest?['published'] as String? ?? ''),
      versions: versions,
      score: score,
      readmeHtml: readmeHtml,
    );
  }

  final String name;
  final String version;
  final String description;
  final List<String> topics;
  final String homepage;
  final String repository;
  final DateTime? published;
  final List<PubPackageVersion> versions;
  final PubPackageScore? score;

  /// Pre-rendered README HTML scraped from the pub.dev package page.
  /// Empty when the page has no README or it could not be fetched.
  final String readmeHtml;

  /// Newer versions first (pub.dev already returns them in that order).
  List<PubPackageVersion> get sortedVersions => versions;

  /// Canonical pub.dev page for the package.
  String get url => 'https://pub.dev/packages/$name';

  bool get hasDescription => description.isNotEmpty;
  bool get hasHomepage => homepage.isNotEmpty;
  bool get hasRepository => repository.isNotEmpty;
  bool get hasReadme => readmeHtml.isNotEmpty;
}
