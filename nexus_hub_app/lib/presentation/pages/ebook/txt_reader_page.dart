import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/ebook_book.dart';
import '../../../data/services/ebook/txt_parser.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../states/ebook_library_state.dart';

/// TXT 阅读器 — 章节目录 + 滚动正文。
///
/// 编码探测（UTF-8/GBK）与章节切分由 [TxtParser] 完成；阅读位置与
/// 字号防抖写入书架，行为与 EPUB 阅读器一致。
class TxtReaderPage extends StatefulWidget {
  const TxtReaderPage({super.key, required this.book});

  final EbookBook book;

  @override
  State<TxtReaderPage> createState() => _TxtReaderPageState();
}

class _TxtReaderPageState extends State<TxtReaderPage> {
  static const _maxContentWidth = 820.0;

  final ScrollController _scroll = ScrollController();
  final Map<int, double> _chapterOffsets = {};
  Timer? _saveDebounce;

  late EbookBook _book;
  TxtBook? _txt;
  String? _error;
  int _chapterIndex = 0;
  double _fontSize = 17;
  bool _showToc = true;
  bool _dirty = false;

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
      final txt = await EbookLibraryState.instance.openTxt(widget.book);
      if (!mounted) return;
      setState(() {
        _txt = txt;
        _chapterIndex = _book.lastChapterIndex.clamp(
          0,
          txt.chapters.length - 1,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target = _book.lastScrollOffset;
        if (target > 0) _scroll.jumpTo(target);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '无法读取该书：$e');
    }
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
    if (!_dirty || _txt == null) return;
    _dirty = false;
    _book = _book.copyWith(
      lastChapterIndex: _chapterIndex,
      lastScrollOffset: _chapterOffsets[_chapterIndex] ?? 0,
      scrollFraction: _scrollFraction,
      fontSize: _fontSize,
      totalChapters: _txt!.chapters.length,
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
    final txt = _txt;
    if (txt == null || index < 0 || index >= txt.chapters.length) return;
    if (index == _chapterIndex) return;
    if (_scroll.hasClients) _chapterOffsets[_chapterIndex] = _scroll.offset;
    setState(() => _chapterIndex = index);
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _chapterOffsets.putIfAbsent(index, () => 0);
      if (target > 0) _scroll.jumpTo(target);
    });
  }

  void _changeFontSize(double delta) {
    final fraction = _scrollFraction;
    setState(() => _fontSize = (_fontSize + delta).clamp(12.0, 30.0));
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent * fraction);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final txt = _txt;

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

    if (txt == null) {
      return Container(
        color: colorScheme.background,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final multiChapter = txt.chapters.length > 1;

    return Container(
      color: colorScheme.background,
      child: Column(
        children: [
          _buildToolbar(context, txt, multiChapter),
          Divider(height: 1, color: colorScheme.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_showToc && multiChapter) ...[
                  _buildTocPanel(context, txt.chapters),
                  VerticalDivider(width: 1, color: colorScheme.border),
                ],
                Expanded(child: _buildContent(context, txt)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, TxtBook txt, bool multiChapter) {
    final colorScheme = Theme.of(context).colorScheme;

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
          if (multiChapter)
            IconButton.ghost(
              icon: Icon(
                _showToc
                    ? LucideIcons.panelLeftClose
                    : LucideIcons.panelLeftOpen,
                size: 18,
              ),
              onPressed: () => setState(() => _showToc = !_showToc),
            ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Text(
              multiChapter
                  ? '${_book.title} · ${_chapterIndex + 1} / ${txt.chapters.length}'
                  : _book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.foreground,
              ),
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
          if (multiChapter) ...[
            IconButton.ghost(
              icon: const Icon(LucideIcons.chevronLeft, size: 20),
              onPressed: _chapterIndex > 0
                  ? () => _goToChapter(_chapterIndex - 1)
                  : null,
            ),
            IconButton.ghost(
              icon: const Icon(LucideIcons.chevronRight, size: 20),
              onPressed: _chapterIndex < txt.chapters.length - 1
                  ? () => _goToChapter(_chapterIndex + 1)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTocPanel(BuildContext context, List<TxtChapter> chapters) {
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

  Widget _buildContent(BuildContext context, TxtBook txt) {
    final colorScheme = Theme.of(context).colorScheme;
    final body = txt.chapterBodies[_chapterIndex];

    return SingleChildScrollView(
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
                  txt.chapters[_chapterIndex].title,
                  style: NexusTypography.headlineSm.copyWith(
                    color: colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: NexusSpacing.lg),
                _buildParagraphs(context, body),
                const SizedBox(height: NexusSpacing.xl),
                if (txt.chapters.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_chapterIndex > 0)
                        Button.outline(
                          onPressed: () => _goToChapter(_chapterIndex - 1),
                          child: const Text('上一章'),
                        )
                      else
                        const SizedBox.shrink(),
                      if (_chapterIndex < txt.chapters.length - 1)
                        Button.primary(
                          onPressed: () => _goToChapter(_chapterIndex + 1),
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
    );
  }

  /// Renders the chapter as indented paragraphs split on blank lines;
  /// single newlines inside a paragraph are kept as hard breaks.
  Widget _buildParagraphs(BuildContext context, String body) {
    final colorScheme = Theme.of(context).colorScheme;
    final paragraphs = body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) {
      return Text(
        '（本章没有内容）',
        style: NexusTypography.bodyMd.copyWith(
          color: colorScheme.mutedForeground,
        ),
      );
    }

    final style = NexusTypography.bodyLg.copyWith(
      fontSize: _fontSize,
      height: 1.7,
      color: colorScheme.foreground,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final paragraph in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.sm + 4),
            child: Text(paragraph, style: style),
          ),
      ],
    );
  }
}
