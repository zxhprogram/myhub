import 'dart:async';

import 'package:pdfrx/pdfrx.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/models/ebook_book.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_input.dart';
import '../../states/ebook_library_state.dart';

/// PDF 阅读器 — 基于 PDFium 的连续滚动视图。
///
/// 支持跳页、缩放，阅读位置（页码）防抖写入书架。
class PdfReaderPage extends StatefulWidget {
  const PdfReaderPage({super.key, required this.book});

  final EbookBook book;

  @override
  State<PdfReaderPage> createState() => _PdfReaderPageState();
}

class _PdfReaderPageState extends State<PdfReaderPage> {
  final PdfViewerController _controller = PdfViewerController();
  final TextEditingController _pageInput = TextEditingController();

  late EbookBook _book;
  late int _currentPage;
  int _totalPages = 0;
  bool _dirty = false;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _totalPages = _book.totalPages;
    _currentPage = _book.lastPage < 1 ? 1 : _book.lastPage;
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    if (_dirty) {
      EbookLibraryState.instance.saveProgress(
        _book.copyWith(lastPage: _currentPage),
      );
    }
    _pageInput.dispose();
    super.dispose();
  }

  void _onPageChanged(int? pageNumber) {
    if (pageNumber == null) return;
    setState(() {
      _currentPage = pageNumber;
      _dirty = true;
    });
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), _flushProgress);
  }

  void _flushProgress() {
    if (!_dirty) return;
    _dirty = false;
    _book = _book.copyWith(lastPage: _currentPage);
    EbookLibraryState.instance.saveProgress(_book);
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (_totalPages != document.pages.length) {
      setState(() => _totalPages = document.pages.length);
      _book = _book.copyWith(totalPages: _totalPages);
      EbookLibraryState.instance.saveProgress(_book);
    }
  }

  Future<void> _jumpToPage() async {
    final input = await showOverlay<int>(
      context,
      DialogConfiguration<int>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) {
          return AlertDialog(
            title: Text('跳转到页', style: NexusTypography.headlineSm),
            content: SizedBox(
              width: 280,
              child: NexusInput(
                labelText: '页码 (1-$_totalPages)',
                controller: _pageInput,
                autofocus: true,
                keyboardType: TextInputType.number,
              ),
            ),
            actions: [
              Button.text(
                onPressed: () => closeOverlay<int>(ctx, null),
                child: const Text('取消'),
              ),
              Button.primary(
                onPressed: () {
                  final page = int.tryParse(_pageInput.text.trim());
                  closeOverlay<int>(ctx, page);
                },
                child: const Text('跳转'),
              ),
            ],
          );
        },
      ),
    ).future;
    _pageInput.clear();
    if (input == null || !mounted) return;
    final target = input.clamp(1, _totalPages < 1 ? 1 : _totalPages);
    await _controller.goToPage(pageNumber: target);
    _onPageChanged(target);
  }

  void _zoom(double? Function() picker) {
    final zoom = picker();
    if (zoom == null) return;
    _controller.goToPosition(
      documentOffset: _controller.centerPosition,
      zoom: zoom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: colorScheme.background,
      child: Column(
        children: [
          _buildToolbar(context),
          Divider(height: 1, color: colorScheme.border),
          Expanded(
            child: PdfViewer.file(
              _book.filePath,
              controller: _controller,
              initialPageNumber: _currentPage,
              params: PdfViewerParams(
                onPageChanged: _onPageChanged,
                onViewerReady: _onViewerReady,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
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
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Text(
              _book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.foreground,
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Button.text(
            onPressed: _totalPages > 0 ? _jumpToPage : null,
            child: Text('$_currentPage / $_totalPages'),
          ),
          const SizedBox(width: NexusSpacing.xs),
          IconButton.ghost(
            icon: const Icon(LucideIcons.zoomOut, size: 18),
            onPressed: () => _zoom(_controller.getPreviousZoom),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.zoomIn, size: 18),
            onPressed: () => _zoom(_controller.getNextZoom),
          ),
        ],
      ),
    );
  }
}
