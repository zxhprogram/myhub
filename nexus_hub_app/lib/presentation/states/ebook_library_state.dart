import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:kindle_unpack/kindle_unpack.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/ebook_book.dart';
import '../../data/services/ebook/epub_parser.dart';
import '../../data/services/ebook/txt_parser.dart';
import '../../data/services/local_database.dart';

/// Signals-backed singleton for the Ebook Reader sub-app.
///
/// The bookshelf is fully local: imported files are copied into
/// `{appSupport}/ebooks/`, metadata and reading positions live in the
/// `ebooks` Hive box, and only the currently opened book is kept parsed
/// in memory (large books can easily weigh dozens of megabytes).
class EbookLibraryState {
  EbookLibraryState._();

  static final EbookLibraryState instance = EbookLibraryState._();

  static const _boxName = 'ebooks';

  /// Shelf books, most recently opened first.
  final books = signal<List<EbookBook>>(const []);

  final isImporting = signal<bool>(false);

  /// Error message of the last failed import, cleared on the next one.
  final importError = signal<String?>(null);

  EpubBook? _epubCache;
  String? _epubCacheId;
  TxtBook? _txtCache;
  String? _txtCacheId;

  Future<Box>? _box;

  Future<Box> get _hiveBox => _box ??= LocalDatabase.box(_boxName);

  Future<Directory> _storageDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'ebooks'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> load() async {
    final box = await _hiveBox;
    final list =
        box.values
            .map((v) => EbookBook.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList()
          ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    books.value = list;
  }

  /// Imports one book file, copying it into the app storage.
  ///
  /// Returns the created shelf entry; throws with a user-presentable
  /// message on unsupported formats or parse failures.
  Future<EbookBook> importFile(String sourcePath) async {
    final ext = p.extension(sourcePath).toLowerCase().replaceFirst('.', '');
    if (ext != 'pdf' &&
        ext != 'epub' &&
        ext != 'txt' &&
        ext != 'mobi' &&
        ext != 'azw3') {
      throw '不支持的格式：$ext（仅支持 PDF / EPUB / TXT / MOBI / AZW3）';
    }

    isImporting.value = true;
    importError.value = null;
    try {
      final dir = await _storageDir();
      final id = _newId();
      final fileName = '$id.$ext';
      final destPath = p.join(dir.path, fileName);
      await File(sourcePath).copy(destPath);

      try {
        final book = switch (ext) {
          'pdf' => await _inspectPdf(destPath, id, sourcePath),
          'epub' => await _inspectEpub(destPath, id, sourcePath, dir),
          'mobi' ||
          'azw3' => await _inspectKindle(destPath, id, ext, sourcePath, dir),
          _ => _inspectTxt(destPath, id, sourcePath),
        };
        final box = await _hiveBox;
        await box.put(book.id, book.toJson());
        books.value = [book, ...books.value];
        return book;
      } catch (_) {
        // Do not keep the copied file around when parsing failed.
        final copied = File(destPath);
        if (await copied.exists()) await copied.delete();
        final cache = File('$destPath.epub');
        if (await cache.exists()) await cache.delete();
        rethrow;
      }
    } catch (e) {
      importError.value = e.toString();
      rethrow;
    } finally {
      isImporting.value = false;
    }
  }

  Future<EbookBook> _inspectPdf(
    String destPath,
    String id,
    String sourcePath,
  ) async {
    await _ensurePdfrxReady();
    final doc = await PdfDocument.openFile(destPath);
    try {
      return EbookBook(
        id: id,
        title: _titleFromFileName(sourcePath),
        author: '',
        format: 'pdf',
        filePath: destPath,
        totalPages: doc.pages.length,
        addedAt: DateTime.now(),
        lastOpenedAt: DateTime.now(),
      );
    } finally {
      await doc.dispose();
    }
  }

  Future<EbookBook> _inspectEpub(
    String destPath,
    String id,
    String sourcePath,
    Directory dir,
  ) async {
    final bytes = await File(destPath).readAsBytes();
    final parsed = await Isolate.run(() => EpubParser.parse(bytes));

    String? coverPath;
    final cover = parsed.coverImage;
    if (cover != null && cover.isNotEmpty) {
      final ext = _sniffImageExt(cover);
      final file = File(p.join(dir.path, '$id$ext'));
      await file.writeAsBytes(cover);
      coverPath = file.path;
    }

    return EbookBook(
      id: id,
      title: _isEmpty(parsed.title)
          ? _titleFromFileName(sourcePath)
          : parsed.title,
      author: parsed.author,
      format: 'epub',
      filePath: destPath,
      coverPath: coverPath,
      totalChapters: parsed.chapters.length,
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );
  }

  EbookBook _inspectTxt(String destPath, String id, String sourcePath) {
    // TXT inspection (encoding + chapter split) is deferred to open time;
    // only the shelf identity is needed here.
    return EbookBook(
      id: id,
      title: _titleFromFileName(sourcePath),
      author: '',
      format: 'txt',
      filePath: destPath,
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );
  }

  /// Kindle 格式（MOBI/AZW3）导入：提取书名/作者/封面，并把整书转换为
  /// EPUB 缓存在原副本旁（`<副本路径>.epub`），打开时直接复用 EPUB 阅读器。
  ///
  /// DRM 加密或损坏的文件在转换阶段抛错，导致整个导入失败（副本一并清理）。
  Future<EbookBook> _inspectKindle(
    String destPath,
    String id,
    String ext,
    String sourcePath,
    Directory dir,
  ) async {
    final bytes = await File(destPath).readAsBytes();
    final KindleBook kindle;
    try {
      kindle = await Isolate.run(() => KindleBook.fromBytes(bytes));
    } catch (e) {
      throw '无法解析 Kindle 文件（可能受 DRM 保护或已损坏）：$e';
    }
    final epubBytes = await Isolate.run(() => kindle.toEpub());
    await File('$destPath.epub').writeAsBytes(epubBytes);

    String? coverPath;
    final cover = kindle.images.cover;
    if (cover != null && cover.data.isNotEmpty) {
      final file = File(p.join(dir.path, '$id${_sniffImageExt(cover.data)}'));
      await file.writeAsBytes(cover.data);
      coverPath = file.path;
    }

    return EbookBook(
      id: id,
      title: _isEmpty(kindle.title)
          ? _titleFromFileName(sourcePath)
          : kindle.title,
      author: kindle.exth?.authors.join(', ') ?? '',
      format: ext,
      filePath: destPath,
      coverPath: coverPath,
      addedAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );
  }

  /// Removes the book from the shelf along with its stored file and cover.
  Future<void> removeBook(EbookBook book) async {
    final box = await _hiveBox;
    await box.delete(book.id);
    books.value = books.value.where((b) => b.id != book.id).toList();
    final isKindle =
        book.formatEnum == EbookFormat.mobi ||
        book.formatEnum == EbookFormat.azw3;
    for (final path in [
      book.filePath,
      if (isKindle) '${book.filePath}.epub',
      book.coverPath,
    ]) {
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    if (_epubCacheId == book.id) {
      _epubCache = null;
      _epubCacheId = null;
    }
    if (_txtCacheId == book.id) {
      _txtCache = null;
      _txtCacheId = null;
    }
  }

  /// Parses the EPUB for reading; the result is cached until another book
  /// is opened. MOBI/AZW3 books read from their converted EPUB cache.
  Future<EpubBook> openEpub(EbookBook book) async {
    if (_epubCacheId == book.id && _epubCache != null) return _epubCache!;
    final bytes = await File(await _resolveEpubPath(book)).readAsBytes();
    final parsed = await Isolate.run(() => EpubParser.parse(bytes));
    _epubCache = parsed;
    _epubCacheId = book.id;
    await _touchOpened(book, totalChapters: parsed.chapters.length);
    return parsed;
  }

  /// Path of the EPUB to parse for [book]. MOBI/AZW3 books read from the
  /// converted EPUB cached next to the original copy; the cache is
  /// regenerated from the Kindle file when missing (e.g. removed manually).
  Future<String> _resolveEpubPath(EbookBook book) async {
    final format = book.formatEnum;
    if (format != EbookFormat.mobi && format != EbookFormat.azw3) {
      return book.filePath;
    }
    final cachePath = '${book.filePath}.epub';
    final cache = File(cachePath);
    if (await cache.exists()) return cachePath;
    final bytes = await File(book.filePath).readAsBytes();
    final KindleBook kindle;
    try {
      kindle = await Isolate.run(() => KindleBook.fromBytes(bytes));
    } catch (e) {
      throw '无法解析 Kindle 文件（可能受 DRM 保护或已损坏）：$e';
    }
    await cache.writeAsBytes(await Isolate.run(() => kindle.toEpub()));
    return cachePath;
  }

  /// Parses the TXT for reading; the result is cached until another book
  /// is opened. Also fills in the chapter count discovered at parse time.
  Future<TxtBook> openTxt(EbookBook book) async {
    if (_txtCacheId == book.id && _txtCache != null) {
      await _touchOpened(book);
      return _txtCache!;
    }
    final bytes = await File(book.filePath).readAsBytes();
    final parsed = await Isolate.run(() => TxtParser.parse(bytes));
    _txtCache = parsed;
    _txtCacheId = book.id;
    await _touchOpened(book, totalChapters: parsed.chapters.length);
    return parsed;
  }

  /// Persists reading position / settings changes of [updated] and
  /// replaces it on the shelf signal.
  Future<void> saveProgress(EbookBook updated) async {
    final box = await _hiveBox;
    await box.put(updated.id, updated.toJson());
    books.value = [
      for (final b in books.value)
        if (b.id == updated.id) updated else b,
    ];
  }

  Future<void> _touchOpened(EbookBook book, {int? totalChapters}) async {
    final updated = book.copyWith(
      lastOpenedAt: DateTime.now(),
      totalChapters: totalChapters ?? book.totalChapters,
    );
    await saveProgress(updated);
  }

  static bool _isEmpty(String s) => s.trim().isEmpty;

  static String _titleFromFileName(String path) {
    final name = p.basenameWithoutExtension(path);
    return name.trim().isEmpty ? '未命名书籍' : name.trim();
  }

  static String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = math.Random().nextInt(0x7FFFFFFF).toRadixString(36);
    return '$ts-$rand';
  }

  static String _sniffImageExt(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    return '.jpg';
  }

  static Future<void>? _pdfrxBoot;

  /// PDFium must be initialized before [PdfDocument] is used outside the
  /// widget tree (the viewer widgets initialize it on their own).
  static Future<void> _ensurePdfrxReady() =>
      _pdfrxBoot ??= pdfrxFlutterInitialize();
}
