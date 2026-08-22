import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import 'ebook_charset.dart';

/// A single spine document of an EPUB book, ready for rendering.
class EpubChapter {
  const EpubChapter({
    required this.title,
    required this.path,
    required this.bodyHtml,
  });

  final String title;

  /// Normalized path of the source file inside the EPUB archive. Used to
  /// resolve internal `ebook-chapter://` links.
  final String path;

  /// Inner HTML of the document `<body>` with image sources rewritten to
  /// `ebook-img://` pseudo URLs resolved at render time from [EpubBook.images].
  final String bodyHtml;
}

/// Fully parsed EPUB book.
class EpubBook {
  const EpubBook({
    required this.title,
    required this.author,
    required this.chapters,
    required this.images,
    this.coverImage,
  });

  final String title;
  final String author;
  final List<EpubChapter> chapters;

  /// Image resources keyed by normalized archive path. Values are the raw
  /// image bytes; `Image.memory` sniffs the format.
  final Map<String, Uint8List> images;

  final Uint8List? coverImage;
}

/// Parses EPUB 2/3 archives into [EpubBook].
///
/// Pure Dart (archive + xml + html packages only) so it can run inside a
/// background isolate via [EpubParser.parseInIsolate]. The reading order
/// follows the OPF spine; chapter titles come from the EPUB3 nav document
/// or the EPUB2 NCX, falling back to each document's `<title>`/heading.
class EpubParser {
  const EpubParser._();

  static const _containerPath = 'META-INF/container.xml';
  static const _imagePseudoScheme = 'ebook-img://';
  static const _chapterPseudoScheme = 'ebook-chapter://';

  /// Parses [bytes] on the current isolate. Prefer [parseInIsolate] for
  /// large books to keep the UI responsive.
  static EpubBook parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    // Case-insensitive lookup index; some zips mix path casing between
    // the OPF references and the actual entries.
    final byLowerName = <String, ArchiveFile>{};
    for (final file in archive) {
      if (file.isFile) byLowerName[file.name.toLowerCase()] = file;
    }

    ArchiveFile? entryOf(String path) =>
        archive.findFile(path) ?? byLowerName[path.toLowerCase()];

    final containerEntry = entryOf(_containerPath);
    if (containerEntry == null) {
      throw const FormatException('EPUB 中缺少 META-INF/container.xml');
    }

    // container.xml -> OPF path
    final containerDoc = XmlDocument.parse(_decode(containerEntry));
    final opfPathAttr = _allElements(containerDoc)
        .firstWhere(
          (e) => e.name.local == 'rootfile',
          orElse: () => throw const FormatException('container.xml 无效'),
        )
        .getAttribute('full-path');
    if (opfPathAttr == null || opfPathAttr.isEmpty) {
      throw const FormatException('container.xml 缺少 full-path');
    }
    final opfPath = _normalizePath('', opfPathAttr);
    final opfEntry = entryOf(opfPath);
    if (opfEntry == null) {
      throw FormatException('找不到 OPF 文件: $opfPath');
    }

    final opfDoc = XmlDocument.parse(_decode(opfEntry));
    final opfDir = _dirname(opfPath);

    // metadata
    String? title;
    String? author;
    for (final e in _allElements(opfDoc)) {
      final ns = e.name.namespaceUri ?? '';
      final isDc = ns.contains('purl.org/dc/elements');
      if (isDc && e.name.local == 'title' && title == null) {
        title = e.innerText.trim();
      } else if (isDc && e.name.local == 'creator' && author == null) {
        author = e.innerText.trim();
      }
    }

    // manifest: id -> (href, mediaType, properties)
    final items = <String, _ManifestItem>{};
    for (final e in _allElements(opfDoc)) {
      if (e.name.local != 'item') continue;
      final id = e.getAttribute('id');
      final href = e.getAttribute('href');
      if (id == null || href == null) continue;
      items[id] = _ManifestItem(
        path: _normalizePath(opfDir, href),
        mediaType: e.getAttribute('media-type') ?? '',
        properties: e.getAttribute('properties') ?? '',
      );
    }

    // spine: reading order + optional EPUB2 NCX id
    final spineIds = <String>[];
    String? ncxId;
    for (final e in _allElements(opfDoc)) {
      if (e.name.local == 'spine') {
        ncxId = e.getAttribute('toc');
      } else if (e.name.local == 'itemref') {
        final idref = e.getAttribute('idref');
        if (idref != null) spineIds.add(idref);
      }
    }

    // table of contents: map of chapter path -> title
    final tocTitles = <String, String>{};
    final navItem = items.values.where(
      (i) => i.properties.split(' ').contains('nav'),
    );
    if (navItem.isNotEmpty) {
      final navEntry = entryOf(navItem.first.path);
      if (navEntry != null) {
        _collectNavTitles(html_parser.parse(_decode(navEntry)), tocTitles);
      }
    } else if (ncxId != null && items[ncxId] != null) {
      final ncxEntry = entryOf(items[ncxId]!.path);
      if (ncxEntry != null) {
        _collectNcxTitles(html_parser.parse(_decode(ncxEntry)), tocTitles);
      }
    }

    // chapters in spine order
    final images = <String, Uint8List>{};
    final chapters = <EpubChapter>[];
    // Collect all document paths first so chapter links can point at
    // chapters that appear later in the spine.
    final spinePaths = <String>{};
    for (final id in spineIds) {
      final item = items[id];
      if (item == null) continue;
      final isDoc =
          item.mediaType == 'application/xhtml+xml' ||
          item.mediaType == 'text/html';
      if (isDoc) spinePaths.add(item.path);
    }
    for (final id in spineIds) {
      final item = items[id];
      if (item == null) continue;
      final isDoc =
          item.mediaType == 'application/xhtml+xml' ||
          item.mediaType == 'text/html';
      if (!isDoc) continue;
      final entry = entryOf(item.path);
      if (entry == null) continue;
      chapters.add(
        _buildChapter(
          source: _decode(entry),
          path: item.path,
          fallbackIndex: chapters.length,
          entryOf: entryOf,
          tocTitles: tocTitles,
          images: images,
          spinePaths: spinePaths,
        ),
      );
    }

    if (chapters.isEmpty) {
      throw const FormatException('EPUB 中没有可读章节');
    }

    return EpubBook(
      title: _isEmpty(title) ? '未命名书籍' : title!,
      author: _isEmpty(author) ? '未知作者' : author!,
      chapters: chapters,
      images: images,
      coverImage: _findCover(opfDoc, items, entryOf),
    );
  }

  /// Decodes an archive entry to text, tolerating GBK encoded documents.
  static String _decode(ArchiveFile file) => decodeTextBytes(file.content);

  static bool _isEmpty(String? s) => s == null || s.trim().isEmpty;

  /// Builds a renderable chapter from one spine document.
  static EpubChapter _buildChapter({
    required String source,
    required String path,
    required int fallbackIndex,
    required ArchiveFile? Function(String) entryOf,
    required Map<String, String> tocTitles,
    required Map<String, Uint8List> images,
    required Set<String> spinePaths,
  }) {
    final doc = html_parser.parse(source);

    // Drop elements that are useless or harmful in the widget renderer.
    for (final selector in const ['script', 'style', 'link', 'meta']) {
      doc.querySelectorAll(selector).forEach((n) => n.remove());
    }

    // Rewrite <img src> to ebook-img:// pseudo URLs backed by [images].
    for (final img in doc.querySelectorAll('img')) {
      final src = img.attributes['src'];
      if (src == null || src.isEmpty) continue;
      final imagePath = _normalizePath(_dirname(path), src);
      final entry = entryOf(imagePath);
      if (entry != null) {
        images[imagePath] = entry.content;
        img.attributes['src'] = '$_imagePseudoScheme$imagePath';
      } else {
        img.remove();
      }
    }

    // Rewrite internal chapter links to ebook-chapter:// URLs; external
    // http(s) links are left untouched.
    for (final anchor in doc.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      if (href == null || href.isEmpty) continue;
      if (href.startsWith('http://') || href.startsWith('https://')) continue;
      final target = _normalizePath(_dirname(path), href);
      if (spinePaths.contains(target)) {
        anchor.attributes['href'] = '$_chapterPseudoScheme$target';
      }
    }

    String? title = tocTitles[path];
    if (_isEmpty(title)) {
      title = doc.head?.querySelector('title')?.text.trim();
    }
    if (_isEmpty(title)) {
      title = doc.body?.querySelector('h1, h2, h3')?.text.trim();
    }
    if (_isEmpty(title)) {
      title = '第 ${fallbackIndex + 1} 节';
    }

    return EpubChapter(
      title: title!,
      path: path,
      bodyHtml: doc.body?.innerHtml ?? '',
    );
  }

  /// EPUB3 nav document: `<nav epub:type="toc">` (or any nav) anchors.
  static void _collectNavTitles(dom.Document doc, Map<String, String> out) {
    dom.Element? nav;
    for (final candidate in doc.querySelectorAll('nav')) {
      final type =
          candidate.attributes['epub:type'] ??
          candidate.attributes['type'] ??
          '';
      if (type.split(' ').contains('toc')) {
        nav = candidate;
        break;
      }
    }
    nav ??= doc.querySelector('nav') ?? doc.body;
    if (nav == null) return;
    for (final anchor in nav.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href'];
      final text = anchor.text.trim();
      if (href == null || text.isEmpty) continue;
      final key = _stripFragment(href);
      out.putIfAbsent(key, () => text);
    }
  }

  /// EPUB2 NCX: navPoint labels.
  static void _collectNcxTitles(dom.Document doc, Map<String, String> out) {
    for (final point in doc.querySelectorAll('navPoint')) {
      final src = point.querySelector('content')?.attributes['src'];
      final text = point.querySelector('navLabel')?.text.trim();
      if (src == null || _isEmpty(text)) continue;
      out.putIfAbsent(_stripFragment(src), () => text!);
    }
  }

  /// Resolves the cover image bytes from the OPF declarations.
  static Uint8List? _findCover(
    XmlDocument opfDoc,
    Map<String, _ManifestItem> items,
    ArchiveFile? Function(String) entryOf,
  ) {
    // EPUB3: <item properties="cover-image">
    for (final item in items.values) {
      if (item.properties.split(' ').contains('cover-image')) {
        return entryOf(item.path)?.content;
      }
    }
    // EPUB2: <meta name="cover" content="cover-id"/>
    for (final e in _allElements(opfDoc)) {
      if (e.name.local != 'meta') continue;
      if (e.getAttribute('name') != 'cover') continue;
      final id = e.getAttribute('content');
      final item = id == null ? null : items[id];
      if (item != null) return entryOf(item.path)?.content;
    }
    return null;
  }

  /// All descendant XML elements regardless of namespace. Namespaces vary
  /// between EPUB files (OPF/DC/container URIs, sometimes different
  /// prefixes), so elements are matched by local name.
  static Iterable<XmlElement> _allElements(XmlNode node) =>
      node.descendants.whereType<XmlElement>();

  static String _stripFragment(String href) {
    final noFragment = href.split('#').first;
    return _normalizePath('', noFragment);
  }

  static String _dirname(String path) {
    final i = path.lastIndexOf('/');
    return i == -1 ? '' : path.substring(0, i);
  }

  /// Resolves [href] relative to [baseDir] into a normalized zip path,
  /// handling `..`/`.` segments and URL escaping. Backslashes are tolerated.
  static String _normalizePath(String baseDir, String href) {
    var cleaned = href.replaceAll('\\', '/');
    try {
      cleaned = Uri.decodeComponent(cleaned);
    } catch (_) {
      // Keep as-is on malformed escapes.
    }
    final combined = baseDir.isEmpty ? cleaned : '$baseDir/$cleaned';
    final segments = <String>[];
    for (final seg in combined.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (segments.isNotEmpty) segments.removeLast();
        continue;
      }
      segments.add(seg);
    }
    return segments.join('/');
  }
}

class _ManifestItem {
  const _ManifestItem({
    required this.path,
    required this.mediaType,
    required this.properties,
  });

  final String path;
  final String mediaType;
  final String properties;
}
