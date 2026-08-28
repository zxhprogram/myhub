import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kindle_unpack/kindle_unpack.dart';

import 'package:nexus_hub_app/data/models/ebook_book.dart';
import 'package:nexus_hub_app/data/services/ebook/ebook_charset.dart';
import 'package:nexus_hub_app/data/services/ebook/epub_parser.dart';
import 'package:nexus_hub_app/data/services/ebook/txt_parser.dart';

/// Builds a minimal but valid EPUB 3 archive in memory.
Uint8List buildTestEpub() {
  final archive = Archive();
  void addText(String path, String content) =>
      archive.add(ArchiveFile.string(path, content));

  addText(
    'META-INF/container.xml',
    '<?xml version="1.0"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" '
        'media-type="application/oebps-package+xml"/></rootfiles></container>',
  );

  addText(
    'OEBPS/content.opf',
    '<?xml version="1.0"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="3.0" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" unique-identifier="uid">'
        '<metadata><dc:title>测试之书</dc:title>'
        '<dc:creator>张三</dc:creator>'
        '<dc:identifier id="uid">test-1</dc:identifier></metadata>'
        '<manifest>'
        '<item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" '
        'properties="nav"/>'
        '<item id="img1" href="images/a.png" media-type="image/png" '
        'properties="cover-image"/>'
        '</manifest>'
        '<spine><itemref idref="ch1"/><itemref idref="ch2"/></spine>'
        '</package>',
  );

  addText(
    'OEBPS/ch1.xhtml',
    '<?xml version="1.0" encoding="utf-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml"><head>'
        '<title>Ignored title</title>'
        '<link rel="stylesheet" href="style.css"/></head>'
        '<body><h1>第一章 起始</h1>'
        '<p>你好世界。</p>'
        '<img src="images/a.png" alt="a"/>'
        '<a href="ch2.xhtml">下一章</a>'
        '<script>evil()</script>'
        '</body></html>',
  );

  addText(
    'OEBPS/ch2.xhtml',
    '<?xml version="1.0" encoding="utf-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title>'
        '</head><body><p>第二章内容。</p></body></html>',
  );

  addText(
    'OEBPS/nav.xhtml',
    '<?xml version="1.0" encoding="utf-8"?>'
        '<html xmlns="http://www.w3.org/1999/xhtml" '
        'xmlns:epub="http://www.idpf.org/2007/ops"><body>'
        '<nav epub:type="toc"><ol>'
        '<li><a href="ch1.xhtml">目录·第一章</a></li>'
        '<li><a href="ch2.xhtml">目录·第二章</a></li>'
        '</ol></nav></body></html>',
  );

  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
  archive.add(ArchiveFile.bytes('OEBPS/images/a.png', png));

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('EpubParser', () {
    test('parses metadata, spine order and TOC titles', () {
      final book = EpubParser.parse(buildTestEpub());

      expect(book.title, '测试之书');
      expect(book.author, '张三');
      expect(book.chapters.length, 2);
      // nav.xhtml is in the manifest but not in the spine.
      expect(book.chapters.map((c) => c.path).toList(), [
        'OEBPS/ch1.xhtml',
        'OEBPS/ch2.xhtml',
      ]);
      // Titles come from the EPUB3 nav document.
      expect(book.chapters[0].title, '目录·第一章');
      expect(book.chapters[1].title, '目录·第二章');
    });

    test('rewrites image sources to the pseudo scheme', () {
      final book = EpubParser.parse(buildTestEpub());

      expect(book.images.containsKey('OEBPS/images/a.png'), isTrue);
      expect(book.images['OEBPS/images/a.png']!.length, 8);
      expect(
        book.chapters[0].bodyHtml,
        contains('ebook-img://OEBPS/images/a.png'),
      );
    });

    test('rewrites internal chapter links', () {
      final book = EpubParser.parse(buildTestEpub());

      expect(
        book.chapters[0].bodyHtml,
        contains('ebook-chapter://OEBPS/ch2.xhtml'),
      );
    });

    test('extracts the cover image and strips scripts/styles', () {
      final book = EpubParser.parse(buildTestEpub());

      expect(book.coverImage, isNotNull);
      expect(book.coverImage!.length, 8);
      expect(book.chapters[0].bodyHtml.contains('script'), isFalse);
      expect(book.chapters[0].bodyHtml.contains('stylesheet'), isFalse);
      expect(book.chapters[0].bodyHtml.contains('你好世界'), isTrue);
    });

    test('throws on invalid archives', () {
      expect(
        () => EpubParser.parse(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('TxtParser', () {
    test('splits Chinese chapter headings', () {
      const text = '简介文字\n\n第一章 起点\n\n内容一。\n\n第二章 转折\n\n内容二。\n';
      final book = TxtParser.parse(Uint8List.fromList(utf8.encode(text)));

      expect(book.chapters.length, 3);
      expect(book.chapters[0].title, '开篇');
      expect(book.chapters[1].title, '第一章 起点');
      expect(book.chapters[2].title, '第二章 转折');
      expect(book.chapterBodies[1].contains('内容一'), isTrue);
      expect(book.chapterBodies[1].contains('第一章'), isFalse);
      expect(book.chapterBodies[2].contains('内容二'), isTrue);
    });

    test('falls back to a single chapter without headings', () {
      final book = TxtParser.parse(
        Uint8List.fromList(utf8.encode('只是一段普通文本，没有章节。')),
      );
      expect(book.chapters.length, 1);
      expect(book.chapters.single.title, '正文');
    });

    test('decodes GBK encoded novels', () {
      const text = '第一章 大梦\n\n谁先觉。';
      final book = TxtParser.parse(Uint8List.fromList(gbk.encode(text)));
      expect(book.chapters.first.title, '第一章 大梦');
      expect(book.chapterBodies.first.contains('谁先觉'), isTrue);
    });
  });

  group('decodeTextBytes', () {
    test('prefers strict UTF-8 and falls back to GBK', () {
      expect(decodeTextBytes(Uint8List.fromList(utf8.encode('中文'))), '中文');
      final gbkBytes = gbk.encode('编码测试');
      expect(decodeTextBytes(Uint8List.fromList(gbkBytes)), '编码测试');
    });
  });

  group('KindleBook (MOBI → EPUB → EpubParser)', () {
    // Real public-domain MOBI (Project Gutenberg #1342), same fixture
    // kindle_unpack itself tests against.
    late Uint8List mobiBytes;
    late EpubBook epub;

    setUpAll(() {
      final fixture = File('test/fixtures/pg1342.mobi');
      if (!fixture.existsSync()) {
        throw StateError('fixture missing: ${fixture.path}');
      }
      mobiBytes = fixture.readAsBytesSync();
      final kindle = KindleBook.fromBytes(mobiBytes);
      epub = EpubParser.parse(kindle.toEpub());
    });

    test('parses Kindle metadata from EXTH', () {
      final kindle = KindleBook.fromBytes(mobiBytes);
      expect(kindle.title, contains('Pride and Prejudice'));
      expect(kindle.exth?.authors.first, contains('Austen'));
      expect(kindle.images.cover, isNotNull);
      expect(kindle.images.cover!.data, isNotEmpty);
    });

    test('converted EPUB parses into chapters', () {
      expect(epub.chapters, isNotEmpty);
      expect(epub.chapters.first.bodyHtml, isNotEmpty);
      // Cover lands in the OPF as cover-image and is picked up.
      expect(epub.coverImage, isNotNull);
      // Note: Mobi-7 inline images use `recindex` attributes which
      // kindle_unpack does not rewrite to `src`, so `epub.images` stays
      // empty for this fixture — the reader shows text without inline
      // images for such books (cover still works via the shelf).
    });

    test('converted EPUB keeps the book text', () {
      final joined = epub.chapters.map((c) => c.bodyHtml).join();
      expect(joined, contains('truth universally acknowledged'));
    });
  });

  group('EbookBook', () {
    test('JSON round trip preserves reading position', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      final book = EbookBook(
        id: 'b1',
        title: '书名',
        author: '作者',
        format: 'epub',
        filePath: '/tmp/b1.epub',
        coverPath: '/tmp/b1.jpg',
        totalChapters: 12,
        lastChapterIndex: 5,
        lastScrollOffset: 320.5,
        scrollFraction: 0.42,
        fontSize: 19,
        addedAt: now,
        lastOpenedAt: now,
      );

      final restored = EbookBook.fromJson(book.toJson());
      expect(restored.id, book.id);
      expect(restored.title, book.title);
      expect(restored.formatEnum, EbookFormat.epub);
      expect(restored.totalChapters, 12);
      expect(restored.lastChapterIndex, 5);
      expect(restored.lastScrollOffset, 320.5);
      expect(restored.scrollFraction, 0.42);
      expect(restored.fontSize, 19);
      expect(restored.lastOpenedAt, now);
      // 5/12 chapters read.
      expect(restored.progress, closeTo(5 / 12, 1e-9));
    });

    test('PDF progress is page based', () {
      final book = EbookBook(
        id: 'b2',
        title: 't',
        author: '',
        format: 'pdf',
        filePath: '/tmp/b2.pdf',
        totalPages: 100,
        lastPage: 25,
        addedAt: DateTime.now(),
        lastOpenedAt: DateTime.now(),
      );
      expect(book.progress, 0.25);
    });

    test('MOBI/AZW3 progress is chapter based', () {
      final now = DateTime.now();
      for (final format in ['mobi', 'azw3']) {
        final book = EbookBook(
          id: 'b-$format',
          title: 't',
          author: '',
          format: format,
          filePath: '/tmp/b.$format',
          totalChapters: 10,
          lastChapterIndex: 3,
          addedAt: now,
          lastOpenedAt: now,
        );
        expect(book.formatEnum.name, format);
        expect(book.progress, closeTo(0.3, 1e-9));
      }
    });
  });
}
