import 'dart:io';
import 'dart:math' as math;

import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' as fw;
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'nexus_button.dart';
import 'nexus_card.dart';
import 'nexus_toast.dart';

enum _DiffViewMode { sideBySide, inline }

enum _ViewFilter { all, differences, same }

/// A Beyond Compare style diff viewer: aligned side-by-side panes with
/// synchronized scrolling, difference section navigation, view filters with
/// context lines, change bars, hatched placeholders and an overview strip.
class NexusDiffViewer extends StatefulWidget {
  const NexusDiffViewer({super.key});

  @override
  State<NexusDiffViewer> createState() => _NexusDiffViewerState();
}

class _NexusDiffViewerState extends State<NexusDiffViewer> {
  static const double _rowHeight = 22;
  static const double _lineNoWidth = 52;
  static const double _gutterWidth = 26;

  final _oldController = TextEditingController();
  final _newController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  String? _oldFileName;
  String? _newFileName;

  _DiffViewMode _mode = _DiffViewMode.sideBySide;
  _ViewFilter _filter = _ViewFilter.all;
  int _contextLines = 2;
  bool _ignoreWhitespace = false;
  String _language = 'Plain Text';

  List<_DiffRow> _rows = [];
  List<int> _visibleIndices = [];
  List<_InlineLine> _inlineLines = [];
  List<bool> _unitIsDiff = [];
  List<_Section> _sections = [];
  int _currentSection = -1;
  bool _hasComparison = false;
  int _compareMs = 0;

  static const _languages = [
    'Plain Text',
    'JSON',
    'Dart',
    'JavaScript',
    'Python',
    'Java',
    'HTML',
    'CSS',
    'SQL',
    'YAML',
    'Markdown',
  ];

  int _lastRenderedRow = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Diff engine
  // ---------------------------------------------------------------------------

  void _onScroll() {
    final row = _currentRow;
    final topUnit = _scrollController.hasClients
        ? (_scrollController.offset / _rowHeight).floor()
        : 0;
    final section = _sections
        .indexWhere((s) => topUnit >= s.start && topUnit <= s.end);
    if (row != _lastRenderedRow ||
        (section != -1 && section != _currentSection)) {
      setState(() {
        _lastRenderedRow = row;
        if (section != -1) _currentSection = section;
      });
    }
  }


  void _compare() {
    final oldLines = _oldController.text.split('\n');
    final newLines = _newController.text.split('\n');
    var oldText = _oldController.text;
    var newText = _newController.text;
    if (_ignoreWhitespace) {
      oldText = _normalizeLines(oldLines);
      newText = _normalizeLines(newLines);
    }

    final stopwatch = Stopwatch()..start();
    final lineDiffs = oldText.isEmpty && newText.isEmpty
        ? <Diff>[]
        : _diffLines(oldText, newText);
    _rows = _buildRows(lineDiffs, oldLines, newLines);
    stopwatch.stop();
    _compareMs = stopwatch.elapsedMilliseconds;

    _rebuildView(resetScroll: true);
    setState(() => _hasComparison = true);
  }

  /// Line mode diff: each unique line is encoded as a single character, the
  /// character diff runs on the encoded strings and the results are decoded
  /// back to whole lines.
  List<Diff> _diffLines(String oldText, String newText) {
    final lineArray = <String>[''];
    final lineHash = <String, int>{};

    bool encode(String text, StringBuffer out) {
      for (final line in _splitKeepNewlines(text)) {
        var index = lineHash[line];
        if (index == null) {
          // Char encoding caps at 65k unique lines; fall back to a plain
          // character diff beyond that.
          if (lineArray.length > 0xFFFF) return false;
          index = lineArray.length;
          lineArray.add(line);
          lineHash[line] = index;
        }
        out.writeCharCode(index);
      }
      return true;
    }

    final oldChars = StringBuffer();
    final newChars = StringBuffer();
    if (!encode(oldText, oldChars) || !encode(newText, newChars)) {
      return diff(oldText, newText);
    }
    final encoded = diff(oldChars.toString(), newChars.toString());
    for (final d in encoded) {
      final buf = StringBuffer();
      for (final codeUnit in d.text.codeUnits) {
        buf.write(lineArray[codeUnit]);
      }
      d.text = buf.toString();
    }
    return encoded;
  }

  List<String> _splitKeepNewlines(String text) {
    if (text.isEmpty) return const [];
    final lines = <String>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        lines.add(text.substring(start, i + 1));
        start = i + 1;
      }
    }
    if (start < text.length) lines.add(text.substring(start));
    return lines;
  }

  /// Rebuilds the visible units (rows or inline lines), sections and scroll
  /// position after the filter / mode / context changes or a new comparison.
  void _rebuildView({bool resetScroll = false}) {
    _visibleIndices = _computeVisibleIndices();
    _inlineLines = [for (final i in _visibleIndices) ..._rows[i].inlineLines];
    _unitIsDiff = _mode == _DiffViewMode.sideBySide
        ? [for (final i in _visibleIndices) _rows[i].isDiff]
        : [for (final line in _inlineLines) line.isDiff];
    _sections = _computeSections();
    _currentSection = _sections.isEmpty ? -1 : 0;
    if (resetScroll && _scrollController.hasClients) {
      _scrollController.jumpTo(
        math.min(
          _scrollController.offset,
          math.max(0, _unitIsDiff.length * _rowHeight - _scrollController.position.viewportDimension),
        ),
      );
    }
  }

  String _normalizeLines(List<String> lines) {
    return lines
        .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
        .join('\n');
  }

  List<_DiffRow> _buildRows(
    List<Diff> lineDiffs,
    List<String> oldLines,
    List<String> newLines,
  ) {
    final rows = <_DiffRow>[];
    final deletes = <String>[];
    final inserts = <String>[];
    var oldLineNo = 0;
    var newLineNo = 0;

    void flushBlock() {
      var i = 0;
      var j = 0;
      while (i < deletes.length && j < inserts.length) {
        final oldText = deletes[i++];
        final newText = inserts[j++];
        final (leftSpans, rightSpans) = _changedSpans(oldText, newText);
        rows.add(_DiffRow(
          left: _DiffCell(
            lineNumber: ++oldLineNo,
            text: oldText,
            spans: leftSpans,
            kind: _CellKind.changed,
          ),
          right: _DiffCell(
            lineNumber: ++newLineNo,
            text: newText,
            spans: rightSpans,
            kind: _CellKind.changed,
          ),
        ));
      }
      while (i < deletes.length) {
        final text = deletes[i++];
        rows.add(_DiffRow(
          left: _DiffCell(
            lineNumber: ++oldLineNo,
            text: text,
            spans: _decorate(text, fg: _deleteFg, bg: _deleteBg),
            kind: _CellKind.deleted,
          ),
        ));
      }
      while (j < inserts.length) {
        final text = inserts[j++];
        rows.add(_DiffRow(
          right: _DiffCell(
            lineNumber: ++newLineNo,
            text: text,
            spans: _decorate(text, fg: _insertFg, bg: _insertBg),
            kind: _CellKind.inserted,
          ),
        ));
      }
      deletes.clear();
      inserts.clear();
    }

    for (final diff in lineDiffs) {
      for (final line in _splitDiffLines(diff.text)) {
        switch (diff.operation) {
          case DIFF_EQUAL:
            flushBlock();
            final spans = _decorate(line);
            rows.add(_DiffRow(
              left: _DiffCell(
                lineNumber: ++oldLineNo,
                text: line,
                spans: spans,
                kind: _CellKind.equal,
              ),
              right: _DiffCell(
                lineNumber: ++newLineNo,
                text: line,
                spans: spans,
                kind: _CellKind.equal,
              ),
            ));
          case DIFF_DELETE:
            deletes.add(line);
          case DIFF_INSERT:
            inserts.add(line);
        }
      }
    }
    flushBlock();

    // When whitespace is ignored the diff runs on normalized text, but line
    // counts are preserved so the originals map back by line number.
    if (_ignoreWhitespace) {
      for (final row in rows) {
        if (row.left != null) {
          row.left!.text = oldLines[row.left!.lineNumber - 1];
        }
        if (row.right != null) {
          row.right!.text = newLines[row.right!.lineNumber - 1];
        }
      }
    }
    return rows;
  }

  List<String> _splitDiffLines(String text) {
    if (text.isEmpty) return const [];
    final lines = text.split('\n');
    if (text.endsWith('\n')) lines.removeLast();
    return lines;
  }

  /// Character level intra-line diff for a changed line pair, returning spans
  /// for the old (left) and new (right) cells.
  (List<TextSpan>, List<TextSpan>) _changedSpans(
    String oldText,
    String newText,
  ) {
    final segs = diff(oldText, newText);
    cleanupSemantic(segs);
    final leftSpans = <TextSpan>[];
    final rightSpans = <TextSpan>[];
    for (final seg in segs) {
      switch (seg.operation) {
        case DIFF_EQUAL:
          final spans = _decorate(seg.text);
          leftSpans.addAll(spans);
          rightSpans.addAll(spans);
        case DIFF_DELETE:
          leftSpans.addAll(
            _decorate(
              seg.text,
              fg: _deleteFg,
              bg: _deleteBg.withValues(alpha: 0.35),
            ),
          );
        case DIFF_INSERT:
          rightSpans.addAll(
            _decorate(
              seg.text,
              fg: _insertFg,
              bg: _insertBg.withValues(alpha: 0.35),
            ),
          );
      }
    }
    return (leftSpans, rightSpans);
  }

  List<int> _computeVisibleIndices() {
    final total = _rows.length;
    switch (_filter) {
      case _ViewFilter.all:
        return List.generate(total, (i) => i);
      case _ViewFilter.same:
        return [
          for (var i = 0; i < total; i++)
            if (!_rows[i].isDiff) i,
        ];
      case _ViewFilter.differences:
        final mask = List<bool>.filled(total, false);
        var start = -1;
        for (var i = 0; i <= total; i++) {
          final isDiff = i < total && _rows[i].isDiff;
          if (isDiff && start == -1) start = i;
          if (!isDiff && start != -1) {
            final from = math.max(0, start - _contextLines);
            final to = math.min(total - 1, (i - 1) + _contextLines);
            for (var k = from; k <= to; k++) {
              mask[k] = true;
            }
            start = -1;
          }
        }
        return [for (var i = 0; i < total; i++) if (mask[i]) i];
    }
  }

  List<_Section> _computeSections() {
    final sections = <_Section>[];
    int? start;
    for (var i = 0; i < _unitIsDiff.length; i++) {
      if (_unitIsDiff[i]) {
        start ??= i;
      } else if (start != null) {
        sections.add(_Section(start, i - 1));
        start = null;
      }
    }
    if (start != null) {
      sections.add(_Section(start, _unitIsDiff.length - 1));
    }
    return sections;
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _gotoSection(int index) {
    if (_sections.isEmpty) return;
    final clamped = index.clamp(0, _sections.length - 1);
    setState(() => _currentSection = clamped);
    _scrollController.animateTo(
      _sections[clamped].start * _rowHeight,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _jumpSection(int direction) {
    if (_sections.isEmpty) return;
    final topUnit = _scrollController.hasClients
        ? (_scrollController.offset / _rowHeight).round()
        : 0;
    final current = _sections
        .indexWhere((s) => topUnit >= s.start && topUnit <= s.end);
    int target;
    if (current == -1) {
      target = direction > 0
          ? _sections.indexWhere((s) => s.start > topUnit)
          : _sections.lastIndexWhere((s) => s.end < topUnit);
      if (target == -1) {
        target = direction > 0 ? 0 : _sections.length - 1;
      }
    } else {
      target = current + direction;
      if (target < 0) target = _sections.length - 1;
      if (target >= _sections.length) target = 0;
    }
    _gotoSection(target);
  }

  void _swapSides() {
    setState(() {
      final text = _oldController.text;
      _oldController.text = _newController.text;
      _newController.text = text;
      final name = _oldFileName;
      _oldFileName = _newFileName;
      _newFileName = name;
    });
    if (_hasComparison) _compare();
  }

  Future<void> _openFile({required bool isOld}) async {
    try {
      final file = await openFile();
      if (file == null) return;
      final text = await File(file.path).readAsString();
      setState(() {
        if (isOld) {
          _oldController.text = text;
          _oldFileName = file.name;
        } else {
          _newController.text = text;
          _newFileName = file.name;
        }
      });
      _compare();
    } catch (e) {
      if (mounted) nexusToast(context, 'Failed to open file: $e');
    }
  }

  Future<void> _copyResult() async {
    final buffer = StringBuffer();
    for (final row in _rows) {
      if (row.isEqual) {
        buffer.writeln('  ${row.left!.text}');
      } else {
        if (row.left != null) buffer.writeln('- ${row.left!.text}');
        if (row.right != null) buffer.writeln('+ ${row.right!.text}');
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) nexusToast(context, 'Diff copied to clipboard');
  }

  void _clear() {
    _oldController.clear();
    _newController.clear();
    setState(() {
      _oldFileName = null;
      _newFileName = null;
      _rows = [];
      _visibleIndices = [];
      _inlineLines = [];
      _unitIsDiff = [];
      _sections = [];
      _currentSection = -1;
      _hasComparison = false;
    });
  }

  void _loadSample() {
    _oldController.text = '''XDebugger.RemoveAllWatches
XDebugger.RemoveWatch
XDebugger.Settings
XDebugger.SetValue
XDebugger.Show.Breakpoints.Over.Line.Numbers
XDebugger.Threads.View.Popup
XDebugger.ToolWindow.LeftToolbar
XDebugger.UnmuteOnStop
XDebugger.ValueGroup
XMLRefactoringMenu
XPathView.Actions.Evaluate
XPathView.Actions.FindByExpression
ZoomInIdeAction
ZoomOutIdeAction''';
    _newController.text = '''XDebugger.RemoveAllWatches
XDebugger.RemoveWatch
XDebugger.Settings
<F2>
XDebugger.Show.Breakpoints.Over.Line.Numbers
XDebugger.Threads.View.Popup
XDebugger.ToolWindow.LeftToolbar
XDebugger.ToolWindow.TopToolbar
XDebugger.UnmuteOnStop
XMLRefactoringMenu
XPathView.Actions.Evaluate
XPathView.Actions.FindByExpression
XPathView.Actions.ShowPath
ZoomInIdeAction
ZoomOutIdeAction''';
    setState(() {
      _oldFileName = null;
      _newFileName = null;
      _language = 'Plain Text';
    });
    _compare();
  }

  // ---------------------------------------------------------------------------
  // Colors
  // ---------------------------------------------------------------------------

  Color get _deleteFg => colorScheme.destructive;
  Color get _insertFg => const Color(0xFF10B981);
  Color get _deleteBg => colorScheme.destructive.withValues(alpha: 0.15);
  Color get _insertBg => const Color(0xFF10B981).withValues(alpha: 0.15);

  TextStyle get _baseTextStyle => NexusTypography.bodyMd.copyWith(height: 1.2);

  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  List<TextSpan> _decorate(String text, {Color? fg, Color? bg}) {
    if (text.isEmpty) return const [];
    return _highlight(
      text,
      _language,
      _baseTextStyle.copyWith(color: fg, backgroundColor: bg),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      padding: EdgeInsets.all(NexusSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFileBars(),
          const SizedBox(height: NexusSpacing.sm),
          _buildToolbar(),
          const SizedBox(height: NexusSpacing.sm),
          Expanded(child: _buildViewer()),
          const SizedBox(height: NexusSpacing.xs),
          _buildOverview(),
          const SizedBox(height: NexusSpacing.xs),
          _buildStatusBar(),
        ],
      ),
    );
  }

  Widget _buildFileBars() {
    return Row(
      children: [
        Expanded(
          child: _FileBar(
            name: _oldFileName,
            onOpen: () => _openFile(isOld: true),
          ),
        ),
        const SizedBox(width: _gutterWidth),
        Expanded(
          child: _FileBar(
            name: _newFileName,
            onOpen: () => _openFile(isOld: false),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    return Wrap(
      spacing: NexusSpacing.sm,
      runSpacing: NexusSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        NexusButton(label: 'Compare', onPressed: _compare),
        NexusButton(
          label: _mode == _DiffViewMode.sideBySide ? 'Inline' : 'Side by Side',
          variant: NexusButtonVariant.outlined,
          onPressed: () {
            setState(() {
              _mode = _mode == _DiffViewMode.sideBySide
                  ? _DiffViewMode.inline
                  : _DiffViewMode.sideBySide;
            });
            if (_hasComparison) _rebuildView();
            setState(() {});
          },
        ),
        _ToolbarDivider(),
        _FilterChip(
          label: 'All',
          selected: _filter == _ViewFilter.all,
          onTap: () => _setFilter(_ViewFilter.all),
        ),
        _FilterChip(
          label: 'Differences',
          selected: _filter == _ViewFilter.differences,
          onTap: () => _setFilter(_ViewFilter.differences),
        ),
        _FilterChip(
          label: 'Same',
          selected: _filter == _ViewFilter.same,
          onTap: () => _setFilter(_ViewFilter.same),
        ),
        _ContextSelector(
          value: _contextLines,
          enabled: _filter == _ViewFilter.differences,
          onChanged: (value) {
            setState(() => _contextLines = value);
            if (_hasComparison) _rebuildView();
            setState(() {});
          },
        ),
        _ToolbarDivider(),
        IconButton.ghost(
          icon: const Icon(LucideIcons.chevronUp, size: 18),
          onPressed: _sections.isEmpty ? null : () => _jumpSection(-1),
        ),
        IconButton.ghost(
          icon: const Icon(LucideIcons.chevronDown, size: 18),
          onPressed: _sections.isEmpty ? null : () => _jumpSection(1),
        ),
        NexusButton(
          label: 'Swap',
          variant: NexusButtonVariant.outlined,
          onPressed: _swapSides,
        ),
        NexusButton(
          label: 'Copy',
          variant: NexusButtonVariant.text,
          onPressed: _hasComparison ? _copyResult : null,
        ),
        NexusButton(
          label: 'Reload',
          variant: NexusButtonVariant.text,
          onPressed: _hasComparison ? _compare : null,
        ),
        _ToolbarDivider(),
        _IgnoreWhitespaceChip(
          value: _ignoreWhitespace,
          onChanged: (value) {
            setState(() => _ignoreWhitespace = value);
            if (_hasComparison) _compare();
          },
        ),
        _LanguageDropdown(
          value: _language,
          languages: _languages,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _language = value);
            if (_hasComparison) _compare();
          },
        ),
        NexusButton(
          label: 'Sample',
          variant: NexusButtonVariant.text,
          onPressed: _loadSample,
        ),
        NexusButton(
          label: 'Clear',
          variant: NexusButtonVariant.text,
          onPressed: _clear,
        ),
      ],
    );
  }

  void _setFilter(_ViewFilter filter) {
    setState(() => _filter = filter);
    if (_hasComparison) _rebuildView();
    setState(() {});
  }

  Widget _buildViewer() {
    if (!_hasComparison) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.border),
          borderRadius: NexusRadii.mdRadius,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.gitCompare,
                size: 40,
                color: colorScheme.mutedForeground,
              ),
              const SizedBox(height: NexusSpacing.md),
              Text(
                'Paste two texts or open files, then click Compare',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final list = _mode == _DiffViewMode.sideBySide
        ? ListView.builder(
            controller: _scrollController,
            itemExtent: _rowHeight,
            itemCount: _visibleIndices.length,
            itemBuilder: (context, index) =>
                _buildDiffRow(_rows[_visibleIndices[index]]),
          )
        : ListView.builder(
            controller: _scrollController,
            itemExtent: _rowHeight,
            itemCount: _inlineLines.length,
            itemBuilder: (context, index) => _buildInlineRow(_inlineLines[index]),
          );

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: fw.SelectionArea(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.border),
            borderRadius: NexusRadii.mdRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: list,
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.f8 &&
        _sections.isNotEmpty) {
      _jumpSection(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------------------------------------------------------------------
  // Row builders
  // ---------------------------------------------------------------------------

  Widget _buildDiffRow(_DiffRow row) {
    return Row(
      children: [
        Expanded(
          child: row.left == null
              ? _HatchedPlaceholder()
              : _SideCell(
                  cell: row.left!,
                  barSide: _BarSide.left,
                  showLineNo: true,
                ),
        ),
        SizedBox(
          width: _gutterWidth,
          child: Center(
            child: row.left == null
                ? Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: colorScheme.mutedForeground,
                  )
                : row.right == null
                    ? Icon(
                        LucideIcons.chevronLeft,
                        size: 14,
                        color: colorScheme.mutedForeground,
                      )
                    : null,
          ),
        ),
        Expanded(
          child: row.right == null
              ? _HatchedPlaceholder()
              : _SideCell(
                  cell: row.right!,
                  barSide: _BarSide.right,
                  showLineNo: true,
                ),
        ),
      ],
    );
  }

  Widget _buildInlineRow(_InlineLine line) {
    final bg = switch (line.kind) {
      _CellKind.deleted => _deleteBg,
      _CellKind.inserted => _insertBg,
      _CellKind.changed => _deleteBg,
      _CellKind.equal => null,
    };
    final prefixColor = switch (line.kind) {
      _CellKind.deleted => _deleteFg,
      _CellKind.inserted => _insertFg,
      _CellKind.changed => _deleteFg,
      _CellKind.equal => colorScheme.mutedForeground,
    };
    return Container(
      height: _rowHeight,
      color: bg,
      child: Row(
        children: [
          _ChangeBar(active: line.isDiff, side: _BarSide.left),
          SizedBox(
            width: _lineNoWidth + 14,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    line.prefix,
                    style: _baseTextStyle.copyWith(
                      color: prefixColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  Text(
                    line.oldNumber != null && line.newNumber != null
                        ? '${line.oldNumber}/${line.newNumber}'
                        : (line.oldNumber ?? line.newNumber ?? '').toString(),
                    style: NexusTypography.labelSm.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: NexusSpacing.sm),
              child: _LineText(spans: line.spans),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status bar & overview
  // ---------------------------------------------------------------------------

  Widget _buildOverview() {
    if (!_hasComparison || _unitIsDiff.isEmpty) {
      return const SizedBox(height: 10);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final unit = ((details.localPosition.dx / width) * _unitIsDiff.length)
                .floor()
                .clamp(0, _unitIsDiff.length - 1);
            final index = _sections
                .indexWhere((s) => unit >= s.start && unit <= s.end);
            if (index != -1) {
              _gotoSection(index);
            } else {
              _scrollController.jumpTo(unit * _rowHeight);
            }
          },
          child: CustomPaint(
            size: Size(width, 10),
            painter: _OverviewPainter(
              sections: _sections,
              total: _unitIsDiff.length,
              currentIndex: _currentSection,
              trackColor: colorScheme.muted.withValues(alpha: 0.6),
              markColor: colorScheme.destructive,
              activeColor: colorScheme.primary,
              borderColor: colorScheme.border,
            ),
          ),
        );
      },
    );
  }


  Widget _buildStatusBar() {
    final sectionLabel = _hasComparison
        ? _sections.isEmpty
            ? 'No differences'
            : '${_sections.length} difference section${_sections.length == 1 ? '' : 's'}'
        : 'Not compared';
    final positionLabel = _hasComparison
        ? 'Row $_currentRow / ${_unitIsDiff.length}'
        : '';
    return Row(
      children: [
        Icon(
          LucideIcons.gitCompare,
          size: 14,
          color: colorScheme.mutedForeground,
        ),
        const SizedBox(width: NexusSpacing.xs),
        Text(
          sectionLabel,
          style: NexusTypography.labelMd.copyWith(
            color: _hasComparison && _sections.isEmpty
                ? _insertFg
                : colorScheme.foreground,
          ),
        ),
        if (_sections.isNotEmpty) ...[
          const SizedBox(width: NexusSpacing.sm),
          Text(
            '${_currentSection + 1} / ${_sections.length}',
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
        const SizedBox(width: NexusSpacing.md),
        Text(
          positionLabel,
          style: NexusTypography.labelMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
        const Spacer(),
        if (_hasComparison)
          Text(
            'Computed in ${(_compareMs / 1000).toStringAsFixed(2)} s',
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
      ],
    );
  }

  int get _currentRow {
    if (!_scrollController.hasClients || _unitIsDiff.isEmpty) return 1;
    return math.min(
      (_scrollController.offset / _rowHeight).floor() + 1,
      _unitIsDiff.length,
    );
  }
}

// -----------------------------------------------------------------------------
// Data model
// -----------------------------------------------------------------------------

enum _CellKind { equal, deleted, inserted, changed }

class _DiffCell {
  _DiffCell({
    required this.lineNumber,
    required this.text,
    required this.spans,
    required this.kind,
  });

  final int lineNumber;
  final List<TextSpan> spans;
  final _CellKind kind;
  String text;
}

class _DiffRow {
  const _DiffRow({this.left, this.right});

  final _DiffCell? left;
  final _DiffCell? right;

  bool get isEqual => left != null && right != null && left!.text == right!.text;

  bool get isDiff => !isEqual;

  List<_InlineLine> get inlineLines {
    if (isEqual) {
      return [
        _InlineLine(
          prefix: ' ',
          kind: _CellKind.equal,
          oldNumber: left!.lineNumber,
          newNumber: right!.lineNumber,
          spans: left!.spans,
        ),
      ];
    }
    final lines = <_InlineLine>[];
    if (left != null) {
      lines.add(
        _InlineLine(
          prefix: '-',
          kind: left!.kind == _CellKind.changed
              ? _CellKind.deleted
              : left!.kind,
          oldNumber: left!.lineNumber,
          spans: left!.spans,
        ),
      );
    }
    if (right != null) {
      lines.add(
        _InlineLine(
          prefix: '+',
          kind: right!.kind == _CellKind.changed
              ? _CellKind.inserted
              : right!.kind,
          newNumber: right!.lineNumber,
          spans: right!.spans,
        ),
      );
    }
    return lines;
  }
}

class _InlineLine {
  const _InlineLine({
    required this.prefix,
    required this.kind,
    required this.spans,
    this.oldNumber,
    this.newNumber,
  });

  final String prefix;
  final _CellKind kind;
  final List<TextSpan> spans;
  final int? oldNumber;
  final int? newNumber;

  bool get isDiff => kind != _CellKind.equal;
}

class _Section {
  const _Section(this.start, this.end);

  final int start;
  final int end;
}

class _OverviewPainter extends CustomPainter {
  const _OverviewPainter({
    required this.sections,
    required this.total,
    required this.currentIndex,
    required this.trackColor,
    required this.markColor,
    required this.activeColor,
    required this.borderColor,
  });

  final List<_Section> sections;
  final int total;
  final int currentIndex;
  final Color trackColor;
  final Color markColor;
  final Color activeColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);
    canvas.drawRRect(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );

    if (total == 0) return;
    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      final left = section.start / total * size.width;
      final right = (section.end + 1) / total * size.width;
      final rect = Rect.fromLTRB(left, 1, math.max(right, left + 2), size.height - 1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = i == currentIndex ? activeColor : markColor,
      );
    }
  }

  @override
  bool shouldRepaint(_OverviewPainter oldDelegate) =>
      oldDelegate.currentIndex != currentIndex ||
      oldDelegate.total != total ||
      oldDelegate.sections != sections;
}


// -----------------------------------------------------------------------------
// Widgets
// -----------------------------------------------------------------------------

enum _BarSide { left, right }

class _SideCell extends StatelessWidget {
  const _SideCell({
    required this.cell,
    required this.barSide,
    required this.showLineNo,
  });

  final _DiffCell cell;
  final _BarSide barSide;
  final bool showLineNo;

  static const double _rowHeight = 22;
  static const double _lineNoWidth = 52;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = switch (cell.kind) {
      _CellKind.equal => null,
      _CellKind.deleted => colorScheme.destructive.withValues(alpha: 0.15),
      _CellKind.inserted => const Color(0xFF10B981).withValues(alpha: 0.15),
      _CellKind.changed => colorScheme.destructive.withValues(alpha: 0.08),
    };
    final barColor = cell.kind == _CellKind.equal
        ? null
        : const Color(0xFFEAB308);

    return Container(
      height: _rowHeight,
      color: bg,
      child: Row(
        children: [
          _ChangeBar(active: barColor != null, side: barSide, color: barColor),
          if (showLineNo)
            Container(
              width: _lineNoWidth,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: colorScheme.muted.withValues(alpha: 0.5),
                border: Border(
                  right: BorderSide(color: colorScheme.border),
                ),
              ),
              alignment: Alignment.centerRight,
              child: Text(
                cell.lineNumber.toString(),
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
                maxLines: 1,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: _LineText(spans: cell.spans),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangeBar extends StatelessWidget {
  const _ChangeBar({
    required this.active,
    required this.side,
    this.color,
  });

  final bool active;
  final _BarSide side;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: double.infinity,
      color: active ? (color ?? const Color(0xFFEAB308)) : null,
    );
  }
}

class _HatchedPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: const Size(double.infinity, 22),
      painter: _HatchPainter(color: colorScheme.border.withValues(alpha: 0.6)),
    );
  }
}

class _HatchPainter extends CustomPainter {
  const _HatchPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const spacing = 7.0;
    for (var x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
  }

  @override
  bool shouldRepaint(_HatchPainter oldDelegate) => oldDelegate.color != color;
}

class _LineText extends StatelessWidget {
  const _LineText({required this.spans});

  final List<TextSpan> spans;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: spans.isEmpty
            ? [TextSpan(text: ' ', style: NexusTypography.bodyMd)]
            : spans,
        style: NexusTypography.bodyMd,
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.clip,
    );
  }
}

class _FileBar extends StatelessWidget {
  const _FileBar({required this.name, required this.onOpen});

  final String? name;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.border),
        borderRadius: NexusRadii.smRadius,
        color: colorScheme.muted.withValues(alpha: 0.3),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.file,
            size: 14,
            color: colorScheme.mutedForeground,
          ),
          const SizedBox(width: NexusSpacing.xs),
          Expanded(
            child: Text(
              name ?? 'Untitled',
              style: NexusTypography.labelMd.copyWith(
                color: name == null
                    ? colorScheme.mutedForeground
                    : colorScheme.foreground,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          GestureDetector(
            onTap: onOpen,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.folderOpen,
                  size: 14,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Open',
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 1,
      height: 20,
      color: colorScheme.border,
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary.withValues(alpha: 0.12) : null,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.border,
          ),
          borderRadius: NexusRadii.smRadius,
        ),
        child: Text(
          label,
          style: NexusTypography.labelMd.copyWith(
            color: selected ? colorScheme.primary : colorScheme.foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _ContextSelector extends StatelessWidget {
  const _ContextSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Context:',
          style: NexusTypography.labelMd.copyWith(
            color: enabled ? colorScheme.foreground : colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(width: NexusSpacing.xs),
        for (var i = 0; i <= 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          GestureDetector(
            onTap: enabled && i != value ? () => onChanged(i) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: i == value && enabled
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : null,
                border: Border.all(
                  color: i == value && enabled
                      ? colorScheme.primary
                      : colorScheme.border,
                ),
                borderRadius: NexusRadii.smRadius,
              ),
              child: Text(
                '$i',
                style: NexusTypography.labelMd.copyWith(
                  color: !enabled
                      ? colorScheme.mutedForeground
                      : i == value
                          ? colorScheme.primary
                          : colorScheme.foreground,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _IgnoreWhitespaceChip extends StatelessWidget {
  const _IgnoreWhitespaceChip({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: NexusSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: value ? colorScheme.accent : null,
          border: Border.all(
            color: value ? colorScheme.primary : colorScheme.border,
          ),
          borderRadius: NexusRadii.mdRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? LucideIcons.squareCheck : LucideIcons.square,
              size: 18,
              color: value ? colorScheme.primary : colorScheme.foreground,
            ),
            const SizedBox(width: NexusSpacing.xs),
            Text(
              'Ignore Whitespace',
              style: NexusTypography.bodyMd.copyWith(
                color: value ? colorScheme.primary : colorScheme.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageDropdown extends StatelessWidget {
  const _LanguageDropdown({
    required this.value,
    required this.languages,
    required this.onChanged,
  });

  final String value;
  final List<String> languages;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Select<String>(
      value: value,
      onChanged: onChanged,
      itemBuilder: (context, value) => Text(
        value,
        style: NexusTypography.bodyMd,
      ),
      popup: SelectPopup(
        items: SelectItemList(
          children: [
            for (final lang in languages)
              SelectItem(
                value: lang,
                builder: (context) => Text(lang),
              ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Syntax highlighting
// -----------------------------------------------------------------------------

List<TextSpan> _highlight(String text, String language, TextStyle baseStyle) {
  if (text.isEmpty) return [TextSpan(text: text, style: baseStyle)];
  if (language == 'Plain Text') {
    return [TextSpan(text: text, style: baseStyle)];
  }

  final patterns = _syntaxPatterns[language];
  if (patterns == null || patterns.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  final spans = <TextSpan>[];
  var remaining = text;

  while (remaining.isNotEmpty) {
    _SyntaxMatch? best;
    for (final pattern in patterns) {
      final match = pattern.regex.matchAsPrefix(remaining) as RegExpMatch?;
      if (match != null) {
        if (best == null || match.start < best.match.start) {
          best = _SyntaxMatch(match: match, pattern: pattern);
        }
      }
    }

    if (best == null) {
      spans.add(TextSpan(text: remaining[0], style: baseStyle));
      remaining = remaining.substring(1);
    } else {
      if (best.match.start > 0) {
        spans.add(
          TextSpan(
            text: remaining.substring(0, best.match.start),
            style: baseStyle,
          ),
        );
      }
      spans.add(
        TextSpan(
          text: best.match.group(0),
          style: baseStyle.copyWith(color: best.pattern.color),
        ),
      );
      remaining = remaining.substring(best.match.end);
    }
  }

  return spans;
}

class _SyntaxMatch {
  _SyntaxMatch({required this.match, required this.pattern});

  final RegExpMatch match;
  final _SyntaxPattern pattern;
}

class _SyntaxPattern {
  _SyntaxPattern(this.regex, this.color);

  final RegExp regex;
  final Color color;
}

final Map<String, List<_SyntaxPattern>> _syntaxPatterns = {
  'JSON': [
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r'\b(true|false|null)\b'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(
      RegExp(r'-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?'),
      const Color(0xFF1565C0),
    ),
  ],
  'Dart': _cLikePatterns(
    const Color(0xFF7B1FA2),
    const Color(0xFF2E7D32),
    const Color(0xFF1565C0),
  ),
  'JavaScript': _cLikePatterns(
    const Color(0xFF7B1FA2),
    const Color(0xFF2E7D32),
    const Color(0xFF1565C0),
  ),
  'Java': _cLikePatterns(
    const Color(0xFF7B1FA2),
    const Color(0xFF2E7D32),
    const Color(0xFF1565C0),
  ),
  'Python': [
    _SyntaxPattern(RegExp(r'#[^\n]*'), const Color(0xFF9E9E9E)),
    _SyntaxPattern(RegExp(r'"""[\s\S]*?"""'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r"'''[\s\S]*?'''"), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), const Color(0xFF2E7D32)),
    _SyntaxPattern(
      RegExp(
        r'\b(def|class|if|else|elif|for|while|return|import|from|as|try|except|finally|with|lambda|and|or|not|in|is|True|False|None|pass|break|continue|raise|yield|global|nonlocal|assert|del)\b',
      ),
      const Color(0xFF7B1FA2),
    ),
    _SyntaxPattern(RegExp(r'\b\d+(?:\.\d+)?\b'), const Color(0xFF1565C0)),
  ],
  'HTML': [
    _SyntaxPattern(RegExp(r'<!--[\s\S]*?-->'), const Color(0xFF9E9E9E)),
    _SyntaxPattern(RegExp(r'<\?[^>]*\?>'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r'<[!/]?[\w-]+'), const Color(0xFF1565C0)),
    _SyntaxPattern(RegExp(r'\s[\w-]+(?==)'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), const Color(0xFF2E7D32)),
  ],
  'CSS': [
    _SyntaxPattern(RegExp(r'/\*[\s\S]*?\*/'), const Color(0xFF9E9E9E)),
    _SyntaxPattern(RegExp(r'[.#]?[\w-]+\s*(?=\{)'), const Color(0xFF1565C0)),
    _SyntaxPattern(RegExp(r'\b[\w-]+(?=\s*:)'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r':\s*[^;]+'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r'#[0-9a-fA-F]{3,8}'), const Color(0xFF1565C0)),
  ],
  'SQL': [
    _SyntaxPattern(RegExp(r'--[^\n]*|/\*[\s\S]*?\*/'), const Color(0xFF9E9E9E)),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), const Color(0xFF2E7D32)),
    _SyntaxPattern(
      RegExp(
        r'\b(SELECT|INSERT|UPDATE|DELETE|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|OUTER|ON|GROUP|ORDER|BY|HAVING|LIMIT|OFFSET|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL|TRUE|FALSE|CREATE|TABLE|ALTER|DROP|INDEX|VALUES|AS|DISTINCT|ALL|UNION|CASE|WHEN|THEN|ELSE|END|IF|WHILE|FOR|RETURN)\b',
      ),
      const Color(0xFF7B1FA2),
    ),
    _SyntaxPattern(RegExp(r'\b\d+(?:\.\d+)?\b'), const Color(0xFF1565C0)),
  ],
  'YAML': [
    _SyntaxPattern(RegExp(r'#[^\n]*'), const Color(0xFF9E9E9E)),
    _SyntaxPattern(RegExp(r'^[\w-]+(?=\s*:)'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), const Color(0xFF2E7D32)),
    _SyntaxPattern(
      RegExp(r'\b(true|false|null|yes|no)\b'),
      const Color(0xFF1565C0),
    ),
    _SyntaxPattern(RegExp(r'\b\d+(?:\.\d+)?\b'), const Color(0xFF1565C0)),
  ],
  'Markdown': [
    _SyntaxPattern(RegExp(r'^#{1,6}\s'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r'\*\*|__'), const Color(0xFF1565C0)),
    _SyntaxPattern(RegExp(r'`[^`]+`'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r'!?\[[^\]]*\]\([^)]+\)'), const Color(0xFF1565C0)),
  ],
};

List<_SyntaxPattern> _cLikePatterns(
  Color keywordColor,
  Color stringColor,
  Color numberColor,
) {
  return [
    _SyntaxPattern(RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'), const Color(0xFF9E9E9E)),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), stringColor),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), stringColor),
    _SyntaxPattern(
      RegExp(
        r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|default|do|else|enum|export|extends|external|factory|false|final|finally|for|Function|get|if|implements|import|in|interface|is|late|library|mixin|new|null|on|operator|override|part|private|protected|public|rethrow|return|set|static|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield|let|function|typeof|instanceof|undefined|delete|of|synchronized|volatile|transient|native|strictfp|goto|package|throws)\b',
      ),
      keywordColor,
    ),
    _SyntaxPattern(RegExp(r'\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b'), numberColor),
  ];
}
