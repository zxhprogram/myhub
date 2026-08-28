/// Supported e-book formats of the Ebook Reader sub-app.
///
/// MOBI and AZW3 (Kindle formats) are converted to EPUB at open time and
/// rendered with the EPUB reader; the format is kept so the shelf can
/// still show the original file type.
enum EbookFormat { pdf, epub, txt, mobi, azw3 }

/// A book on the local bookshelf.
///
/// The source file is copied into the app's support directory at import
/// time; reading position and per-book settings are persisted in the
/// `ebooks` Hive box via [toJson]/[fromJson].
class EbookBook {
  EbookBook({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.filePath,
    this.coverPath,
    this.totalPages = 0,
    this.totalChapters = 0,
    this.lastPage = 1,
    this.lastChapterIndex = 0,
    this.lastScrollOffset = 0,
    this.scrollFraction = 0,
    this.fontSize = 17,
    required this.addedAt,
    required this.lastOpenedAt,
  });

  final String id;
  final String title;
  final String author;

  /// Extension without the dot, matches [EbookFormat.name].
  final String format;

  /// Absolute path of the imported copy inside the app support directory.
  final String filePath;

  /// Absolute path of the extracted cover image, when available.
  final String? coverPath;

  /// Page count for PDF books, 0 otherwise.
  final int totalPages;

  /// Number of chapters for EPUB/TXT/MOBI/AZW3 books, 0 otherwise.
  final int totalChapters;

  /// Last read page (1-based) for PDF books.
  final int lastPage;

  /// Last read chapter index (0-based) for EPUB/TXT books.
  final int lastChapterIndex;

  /// Last scroll offset within the current chapter for EPUB/TXT books.
  final double lastScrollOffset;

  /// Scroll fraction (0..1) of the current chapter, used for progress
  /// display when the chapter itself is long.
  final double scrollFraction;

  /// Reader font size for EPUB/TXT books.
  final double fontSize;

  final DateTime addedAt;
  final DateTime lastOpenedAt;

  EbookFormat get formatEnum => EbookFormat.values.firstWhere(
    (f) => f.name == format,
    orElse: () => EbookFormat.txt,
  );

  /// Overall reading progress in the 0..1 range for shelf display.
  double get progress {
    switch (formatEnum) {
      case EbookFormat.pdf:
        if (totalPages <= 0) return 0;
        return ((lastPage) / totalPages).clamp(0.0, 1.0);
      case EbookFormat.epub:
      case EbookFormat.txt:
      case EbookFormat.mobi:
      case EbookFormat.azw3:
        if (totalChapters <= 0) return 0;
        final chapterPart = lastChapterIndex / totalChapters;
        final withinChapter = totalChapters == 1
            ? scrollFraction.clamp(0.0, 1.0)
            : 0.0;
        return (chapterPart + withinChapter / totalChapters).clamp(0.0, 1.0);
    }
  }

  EbookBook copyWith({
    String? title,
    String? author,
    String? coverPath,
    int? totalPages,
    int? totalChapters,
    int? lastPage,
    int? lastChapterIndex,
    double? lastScrollOffset,
    double? scrollFraction,
    double? fontSize,
    DateTime? lastOpenedAt,
  }) {
    return EbookBook(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format,
      filePath: filePath,
      coverPath: coverPath ?? this.coverPath,
      totalPages: totalPages ?? this.totalPages,
      totalChapters: totalChapters ?? this.totalChapters,
      lastPage: lastPage ?? this.lastPage,
      lastChapterIndex: lastChapterIndex ?? this.lastChapterIndex,
      lastScrollOffset: lastScrollOffset ?? this.lastScrollOffset,
      scrollFraction: scrollFraction ?? this.scrollFraction,
      fontSize: fontSize ?? this.fontSize,
      addedAt: addedAt,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  factory EbookBook.fromJson(Map<String, dynamic> json) {
    return EbookBook(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      format: json['format'] as String? ?? 'txt',
      filePath: json['filePath'] as String? ?? '',
      coverPath: json['coverPath'] as String?,
      totalPages: json['totalPages'] as int? ?? 0,
      totalChapters: json['totalChapters'] as int? ?? 0,
      lastPage: json['lastPage'] as int? ?? 1,
      lastChapterIndex: json['lastChapterIndex'] as int? ?? 0,
      lastScrollOffset: (json['lastScrollOffset'] as num?)?.toDouble() ?? 0,
      scrollFraction: (json['scrollFraction'] as num?)?.toDouble() ?? 0,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 17,
      addedAt:
          DateTime.tryParse(json['addedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      lastOpenedAt:
          DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'format': format,
      'filePath': filePath,
      'coverPath': coverPath,
      'totalPages': totalPages,
      'totalChapters': totalChapters,
      'lastPage': lastPage,
      'lastChapterIndex': lastChapterIndex,
      'lastScrollOffset': lastScrollOffset,
      'scrollFraction': scrollFraction,
      'fontSize': fontSize,
      'addedAt': addedAt.toIso8601String(),
      'lastOpenedAt': lastOpenedAt.toIso8601String(),
    };
  }
}
