import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/ebook_book.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';
import '../../components/nexus_toast.dart';
import '../../layout/page_scaffold.dart';
import '../../states/ebook_library_state.dart';
import 'epub_reader_page.dart';
import 'pdf_reader_page.dart';
import 'txt_reader_page.dart';

/// 电子书阅读 — 本地书架。
///
/// 导入的文件被复制到应用目录，阅读进度保存在 Hive。点击书籍按格式
/// 打开对应阅读器（PDF / EPUB / TXT）。
class EbookLibraryPage extends StatefulWidget {
  const EbookLibraryPage({super.key});

  @override
  State<EbookLibraryPage> createState() => _EbookLibraryPageState();
}

class _EbookLibraryPageState extends State<EbookLibraryPage> {
  final _state = EbookLibraryState.instance;

  static const _typeGroup = XTypeGroup(
    label: '电子书',
    extensions: ['pdf', 'epub', 'txt'],
  );

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  Future<void> _import() async {
    final files = await openFiles(acceptedTypeGroups: [_typeGroup]);
    if (files.isEmpty) return;
    var ok = 0;
    final failures = <String>[];
    for (final file in files) {
      try {
        await _state.importFile(file.path);
        ok++;
      } catch (e) {
        failures.add('${p.basename(file.path)}：$e');
      }
    }
    if (!mounted) return;
    if (failures.isEmpty) {
      nexusToast(context, '已导入 $ok 本书');
    } else {
      nexusToast(
        context,
        '成功 $ok 本，失败 ${failures.length} 本：${failures.first}',
        isError: true,
        showDuration: const Duration(seconds: 5),
      );
    }
  }

  void _open(BuildContext context, EbookBook book) {
    final reader = switch (book.formatEnum) {
      EbookFormat.pdf => PdfReaderPage(book: book),
      EbookFormat.epub => EpubReaderPage(book: book),
      EbookFormat.txt => TxtReaderPage(book: book),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => reader));
  }

  void _confirmRemove(BuildContext context, EbookBook book) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) {
          return AlertDialog(
            title: Text(
              '移除 "${book.title}"？',
              style: NexusTypography.headlineSm,
            ),
            content: Text(
              '将从书架移除并删除应用目录中的副本，不影响原始文件。',
              style: NexusTypography.bodyMd,
            ),
            actions: [
              Button.text(
                onPressed: () => closeOverlay<void>(context),
                child: const Text('取消'),
              ),
              Button.destructive(
                onPressed: () {
                  closeOverlay<void>(context);
                  _state.removeBook(book);
                },
                child: const Text('移除'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    _state.books.watch(context);
    _state.isImporting.watch(context);
    final books = _state.books.value;
    final importing = _state.isImporting.value;

    return PageScaffold(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ebook Reader', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                '本地书架，支持 PDF / EPUB / TXT',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          NexusButton(
            label: importing ? '导入中…' : '导入图书',
            icon: LucideIcons.bookPlus,
            isLoading: importing,
            onPressed: importing ? null : _import,
          ),
        ],
      ),
      child: books.isEmpty
          ? NexusEmptyState(
              icon: LucideIcons.bookOpen,
              title: '书架还是空的',
              subtitle: '导入 PDF、EPUB 或 TXT 文件开始阅读',
              action: NexusButton(
                label: '导入图书',
                icon: LucideIcons.bookPlus,
                onPressed: _import,
              ),
            )
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 172,
                mainAxisSpacing: NexusSpacing.md,
                crossAxisSpacing: NexusSpacing.md,
                childAspectRatio: 0.56,
              ),
              itemCount: books.length,
              itemBuilder: (context, index) {
                final book = books[index];
                return _BookCard(
                  book: book,
                  onTap: () => _open(context, book),
                  onRemove: () => _confirmRemove(context, book),
                );
              },
            ),
    );
  }
}

class _BookCard extends StatefulWidget {
  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onRemove,
  });

  final EbookBook book;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final book = widget.book;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _BookCover(book: book),
                  if (_hovering)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: IconButton.ghost(
                        icon: Icon(
                          LucideIcons.trash2,
                          size: 16,
                          color: colorScheme.destructive,
                        ),
                        onPressed: widget.onRemove,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.foreground,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              book.author.isEmpty ? _formatLabel(book) : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.xs),
            _ProgressStrip(progress: book.progress),
          ],
        ),
      ),
    );
  }

  static String _formatLabel(EbookBook book) => book.format.toUpperCase();
}

/// Cover area: extracted EPUB cover, live PDF first page, or a gradient
/// placeholder with the format badge.
class _BookCover extends StatelessWidget {
  const _BookCover({required this.book});

  final EbookBook book;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _coverContent(context),
          Positioned(
            left: 6,
            bottom: 6,
            child: NexusBadge(
              label: book.format.toUpperCase(),
              backgroundColor: colorScheme.background.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final coverPath = book.coverPath;
    if (book.formatEnum == EbookFormat.epub && coverPath != null) {
      return Image.file(
        File(coverPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(colorScheme),
      );
    }
    if (book.formatEnum == EbookFormat.pdf) {
      // Render the first page live through PDFium; no pre-rendered
      // thumbnail is stored.
      return PdfDocumentViewBuilder.file(
        book.filePath,
        builder: (context, document) => PdfPageView(
          document: document,
          pageNumber: 1,
          backgroundColor: colorScheme.card,
        ),
        errorBuilder: (context, error, stackTrace) => _placeholder(colorScheme),
      );
    }
    return _placeholder(colorScheme);
  }

  Widget _placeholder(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        book.formatEnum == EbookFormat.txt
            ? LucideIcons.fileText
            : LucideIcons.bookOpen,
        size: 36,
        color: colorScheme.mutedForeground.withValues(alpha: 0.6),
      ),
    );
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clamped = progress.clamp(0.0, 1.0);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.muted,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: clamped,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${(clamped * 100).round()}%',
          style: NexusTypography.labelSm.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      ],
    );
  }
}
