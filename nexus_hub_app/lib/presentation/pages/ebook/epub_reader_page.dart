import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/ebook_book.dart';
import '../../../data/services/ebook/epub_parser.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_page_route.dart';
import '../../states/ebook_library_state.dart';
import '../google_news_article_page.dart';
import 'ebook_translate_dialog.dart';

/// EPUB 阅读器 — 左侧目录 + 右侧章节正文。
///
/// 章节由 [EpubParser] 解析，HTML 用 flutter_widget_from_html 渲染；
/// 书内图片通过 `ebook-img://` 伪协议由 [_EpubImageFactory] 从内存
/// 映射中解析，跨章链接通过 `ebook-chapter://` 跳转。阅读位置
/// （章节 + 滚动偏移）与字号防抖写入书架。
class EpubReaderPage extends StatefulWidget {
  const EpubReaderPage({super.key, required this.book});

  final EbookBook book;

  @override
  State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  static const _chapterScheme = 'ebook-chapter://';
  static const _maxContentWidth = 820.0;

  final ScrollController _scroll = ScrollController();
  final Map<int, double> _chapterOffsets = {};
  Timer? _saveDebounce;

  late EbookBook _book;
  EpubBook? _epub;
  String? _error;
  int _chapterIndex = 0;
  double _fontSize = 17;
  bool _showToc = true;
  bool _dirty = false;
  String _selectedText = '';

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _fontSize = _book.fontSize;
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _saveNow();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final epub = await EbookLibraryState.instance.openEpub(widget.book);
      if (!mounted) return;
      setState(() {
        _epub = epub;
        _chapterIndex = _book.lastChapterIndex.clamp(
          0,
          epub.chapters.length - 1,
        );
      });
      _restoreScrollAfterLayout();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法解析该书：$e');
    }
  }

  /// Restores the saved scroll offset once the chapter content has been
  /// laid out (image decoding may still shift extents afterwards; the
  /// offset is clamped by the scroll controller).
  void _restoreScrollAfterLayout() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _chapterOffsets.putIfAbsent(
        _chapterIndex,
        () => _book.lastScrollOffset,
      );
      if (target > 0) {
        _scroll.jumpTo(target);
      }
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    _chapterOffsets[_chapterIndex] = _scroll.offset;
    _scheduleSave();
  }

  void _scheduleSave() {
    _dirty = true;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  void _saveNow() {
    if (!_dirty || _epub == null) return;
    _dirty = false;
    _book = _book.copyWith(
      lastChapterIndex: _chapterIndex,
      lastScrollOffset: _chapterOffsets[_chapterIndex] ?? 0,
      scrollFraction: _scrollFraction,
      fontSize: _fontSize,
      totalChapters: _epub!.chapters.length,
    );
    EbookLibraryState.instance.saveProgress(_book);
  }

  double get _scrollFraction {
    if (!_scroll.hasClients) return _book.scrollFraction;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return 0;
    return (_scroll.offset / max).clamp(0.0, 1.0);
  }

  void _goToChapter(int index) {
    final epub = _epub;
    if (epub == null || index < 0 || index >= epub.chapters.length) return;
    if (index == _chapterIndex) return;
    if (_scroll.hasClients) _chapterOffsets[_chapterIndex] = _scroll.offset;
    setState(() {
      _chapterIndex = index;
      _selectedText = '';
    });
    _scheduleSave();
    _restoreScrollAfterLayout();
  }

  void _changeFontSize(double delta) {
    if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
      // Keep the reading position stable relative to the content when
      // the font size changes reflow the text.
      final fraction = _scrollFraction;
      setState(() => _fontSize = (_fontSize + delta).clamp(12.0, 30.0));
      _scheduleSave();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.jumpTo(_scroll.position.maxScrollExtent * fraction);
      });
    } else {
      setState(() => _fontSize = (_fontSize + delta).clamp(12.0, 30.0));
      _scheduleSave();
    }
  }

  Future<bool> _onTapUrl(String url) async {
    if (url.startsWith(_chapterScheme)) {
      final path = url.substring(_chapterScheme.length);
      final index = _epub?.chapters.indexWhere((c) => c.path == path) ?? -1;
      if (index >= 0) _goToChapter(index);
      return true;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      final uri = Uri.tryParse(url);
      if (uri != null && mounted) {
        await Navigator.of(context).push(
          NexusPageRoute<void>(
            builder: (_) => NexusWebViewPage(url: url, title: uri.host),
          ),
        );
      }
      return true;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final epub = _epub;

    if (_error != null) {
      return Container(
        color: colorScheme.background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('打开失败', style: NexusTypography.headlineSm),
              const SizedBox(height: NexusSpacing.sm),
              Text(
                _error!,
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: NexusSpacing.md),
              Button.outline(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回书架'),
              ),
            ],
          ),
        ),
      );
    }

    if (epub == null) {
      return Container(
        color: colorScheme.background,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final chapter = epub.chapters[_chapterIndex];

    return Container(
      color: colorScheme.background,
      child: Column(
        children: [
          _buildToolbar(context),
          Divider(height: 1, color: colorScheme.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showToc) _buildTocPanel(context, epub.chapters),
                if (_showToc)
                  VerticalDivider(width: 1, color: colorScheme.border),
                Expanded(child: _buildContent(context, chapter)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chapters = _epub!.chapters;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton.ghost(
            icon: const Icon(LucideIcons.arrowLeft, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          IconButton.ghost(
            icon: Icon(
              _showToc ? LucideIcons.panelLeftClose : LucideIcons.panelLeftOpen,
              size: 18,
            ),
            onPressed: () => setState(() => _showToc = !_showToc),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.foreground,
                  ),
                ),
                Text(
                  '${_chapterIndex + 1} / ${chapters.length} · ${chapters[_chapterIndex].title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.minus, size: 18),
            onPressed: () => _changeFontSize(-1),
          ),
          Text(
            _fontSize.round().toString(),
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.plus, size: 18),
            onPressed: () => _changeFontSize(1),
          ),
          const SizedBox(width: NexusSpacing.xs),
          IconButton.ghost(
            icon: const Icon(LucideIcons.settings, size: 18),
            onPressed: () => EbookTranslateConfigDialog.show(context),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.chevronLeft, size: 20),
            onPressed: _chapterIndex > 0
                ? () => _goToChapter(_chapterIndex - 1)
                : null,
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.chevronRight, size: 20),
            onPressed: _chapterIndex < chapters.length - 1
                ? () => _goToChapter(_chapterIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildTocPanel(BuildContext context, List<EpubChapter> chapters) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 260,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: NexusSpacing.xs),
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final current = index == _chapterIndex;
          return GestureDetector(
            onTap: () => _goToChapter(index),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.md,
                  vertical: NexusSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: current
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      width: 3,
                      color: current ? colorScheme.primary : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  chapters[index].title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelMd.copyWith(
                    color: current
                        ? colorScheme.primary
                        : colorScheme.foreground,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, EpubChapter chapter) {
    final colorScheme = Theme.of(context).colorScheme;
    // The floating translate button lives inside the SelectableRegion so the
    // tap on it does not clear the selection before it fires. HtmlWidget
    // participates in selection via the ambient SelectionRegistrar. Empty
    // selection controls keep the widget free of any material-styled toolbar.
    return DefaultSelectionStyle(
      selectionColor: colorScheme.primary.withValues(alpha: 0.3),
      child: SelectableRegion(
        selectionControls: emptyTextSelectionControls,
        onSelectionChanged: (selection) {
          final text = selection?.plainText ?? '';
          if (text == _selectedText) return;
          setState(() => _selectedText = text);
        },
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scroll,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxContentWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexusSpacing.xl,
                      vertical: NexusSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          chapter.title,
                          style: NexusTypography.headlineSm.copyWith(
                            color: colorScheme.foreground,
                          ),
                        ),
                        const SizedBox(height: NexusSpacing.lg),
                        HtmlWidget(
                          chapter.bodyHtml,
                          textStyle: NexusTypography.bodyLg.copyWith(
                            fontSize: _fontSize,
                            height: 1.7,
                            color: colorScheme.foreground,
                          ),
                          factoryBuilder: () =>
                              _EpubImageFactory(_epub!.images),
                          onTapUrl: _onTapUrl,
                        ),
                        const SizedBox(height: NexusSpacing.xl),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_chapterIndex > 0)
                              Button.outline(
                                onPressed: () =>
                                    _goToChapter(_chapterIndex - 1),
                                child: const Text('上一章'),
                              )
                            else
                              const SizedBox.shrink(),
                            if (_chapterIndex < _epub!.chapters.length - 1)
                              Button.primary(
                                onPressed: () =>
                                    _goToChapter(_chapterIndex + 1),
                                child: const Text('下一章'),
                              )
                            else
                              const SizedBox.shrink(),
                          ],
                        ),
                        const SizedBox(height: NexusSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_selectedText.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: NexusSpacing.lg,
                child: Center(child: _buildTranslateButton(context)),
              ),
          ],
        ),
      ),
    );
  }

  /// Floating pill shown above the content while text is selected.
  Widget _buildTranslateButton(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: theme.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Button.primary(
        leading: const Icon(LucideIcons.languages, size: 16),
        onPressed: () =>
            EbookTranslateDialog.show(context, text: _selectedText.trim()),
        child: const Text('翻译'),
      ),
    );
  }
}

/// Resolves `ebook-img://` sources from the parsed EPUB image map; other
/// schemes are passed through (network) or dropped to avoid broken
/// fetches for unresolved references.
class _EpubImageFactory extends WidgetFactory {
  _EpubImageFactory(this._images);

  final Map<String, Uint8List> _images;

  @override
  Widget? buildImageWidget(BuildTree tree, ImageSource src) {
    final url = src.url;
    if (url.startsWith('ebook-img://')) {
      final bytes = _images[url.substring('ebook-img://'.length)];
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        );
      }
      return const SizedBox.shrink();
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return super.buildImageWidget(tree, src);
    }
    return const SizedBox.shrink();
  }
}
