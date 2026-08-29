import 'dart:convert';
import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'nexus_card.dart';
import 'nexus_toast.dart';

/// JSON formatter with a syntax-highlighted editor on the left and a
/// recursively expandable grid ("GRID") on the right, in the style of
/// jsonformatter.net: object keys become columns, arrays become numbered
/// rows, and nested values expand in place as inner tables.
class NexusJsonFormatter extends StatefulWidget {
  const NexusJsonFormatter({super.key});

  @override
  State<NexusJsonFormatter> createState() => _NexusJsonFormatterState();
}

class _NexusJsonFormatterState extends State<NexusJsonFormatter> {
  static const _monoFont = 'Consolas';
  static const double _lineHeight = 20;
  static const int _defaultRowLimit = 200;
  static const int _maxColumns = 64;

  static const _colorKey = Color(0xFFA31515);
  static const _colorString = Color(0xFF986801);
  static const _colorNumber = Color(0xFFC7361B);
  static const _colorBoolean = Color(0xFFD7263D);
  static const _colorNull = Color(0xFF8B8B8B);
  static const _colorPunctuation = Color(0xFF6B7280);
  static const _colorHeaderBar = Color(0xFF2B3038);
  static const _colorValid = Color(0xFF16A34A);

  final _editorController = _JsonHighlightController();
  final _editorFocus = FocusNode();
  final _findController = TextEditingController();
  final _gridSearchController = TextEditingController();

  /// Decoded JSON rendered by the grid; null until Format / Validate runs.
  dynamic _root;

  String? _error;
  int? _errorLine;
  int? _errorColumn;
  bool _valid = false;

  // Left pane: find-in-editor state.
  bool _findVisible = false;
  List<int> _findMatches = const [];
  int _findIndex = -1;

  // Right pane: grid state.
  bool _gridSearchVisible = false;
  bool _advancedFilterOpen = false;
  String _gridQuery = '';
  bool _gridCaseSensitive = false;
  final Set<String> _expandedPaths = {};
  final Map<String, int> _rowLimits = {};
  final Set<String> _hiddenColumns = {};
  List<String> _rootColumns = const [];
  String? _lastExpandedPath;

  // Split layout.
  double _leftFraction = 0.46;

  @override
  void initState() {
    super.initState();
    _editorController.addListener(_onEditorChanged);
    _findController.addListener(_onFindChanged);
    _gridSearchController.addListener(_onGridSearchChanged);
  }

  @override
  void dispose() {
    _editorController.removeListener(_onEditorChanged);
    _findController.removeListener(_onFindChanged);
    _gridSearchController.removeListener(_onGridSearchChanged);
    _editorController.dispose();
    _editorFocus.dispose();
    _findController.dispose();
    _gridSearchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _onEditorChanged() {
    _recomputeFindMatches();
    setState(() {});
  }

  void _onFindChanged() {
    _recomputeFindMatches();
    setState(() {});
  }

  void _onGridSearchChanged() {
    setState(() => _gridQuery = _gridSearchController.text);
  }

  ({dynamic value, String? error, int? line, int? column}) _parseInput() {
    final text = _editorController.text.trim();
    if (text.isEmpty) {
      return (value: null, error: null, line: null, column: null);
    }
    try {
      return (value: jsonDecode(text), error: null, line: null, column: null);
    } on FormatException catch (e) {
      int? line;
      int? column;
      final offset = e.offset;
      final src = _editorController.text;
      if (offset != null && offset >= 0 && offset < src.length) {
        var currentLine = 1;
        var lastNewline = -1;
        for (var i = 0; i < offset; i++) {
          if (src.codeUnitAt(i) == 0x0A) {
            currentLine++;
            lastNewline = i;
          }
        }
        line = currentLine;
        column = offset - lastNewline;
      }
      return (value: null, error: e.message, line: line, column: column);
    }
  }

  void _applyParseResult({
    required String? error,
    required int? line,
    required int? column,
    required bool announce,
  }) {
    final parsed = _parseInput();
    setState(() {
      _error = error;
      _errorLine = line;
      _errorColumn = column;
      _valid = error == null && parsed.value != null;
      if (error == null && parsed.value != null) {
        _root = parsed.value;
        _rootColumns = _unionColumns(_unwrapNode(parsed.value));
        _hiddenColumns.clear();
        _lastExpandedPath = null;
      }
    });
    if (announce && _valid && mounted) {
      nexusToast(context, 'Valid JSON');
    }
  }

  void _format({bool minify = false}) {
    final text = _editorController.text.trim();
    if (text.isEmpty) return;
    final parsed = _parseInput();
    if (parsed.error != null) {
      _applyParseResult(
        error: parsed.error,
        line: parsed.line,
        column: parsed.column,
        announce: false,
      );
      return;
    }
    final encoder =
        minify ? const JsonEncoder() : const JsonEncoder.withIndent('  ');
    _setEditorText(encoder.convert(parsed.value));
    _applyParseResult(
      error: null,
      line: null,
      column: null,
      announce: false,
    );
  }

  void _validate() {
    final parsed = _parseInput();
    _applyParseResult(
      error: parsed.error,
      line: parsed.line,
      column: parsed.column,
      announce: true,
    );
  }

  void _setEditorText(String text) {
    _editorController.removeListener(_onEditorChanged);
    _editorController.text = text;
    _editorController.addListener(_onEditorChanged);
  }

  void _loadSample() {
    _setEditorText(_sampleJson);
    _recomputeFindMatches();
    _format();
  }

  void _clear() {
    _setEditorText('');
    _findController.clear();
    _gridSearchController.clear();
    setState(() {
      _error = null;
      _errorLine = null;
      _errorColumn = null;
      _valid = false;
      _root = null;
      _rootColumns = const [];
      _findVisible = false;
      _gridSearchVisible = false;
      _advancedFilterOpen = false;
      _findMatches = const [];
      _findIndex = -1;
      _expandedPaths.clear();
      _rowLimits.clear();
      _hiddenColumns.clear();
      _lastExpandedPath = null;
    });
  }

  // ---------------------------------------------------------------------------
  // Find in editor
  // ---------------------------------------------------------------------------

  void _recomputeFindMatches() {
    final query = _findController.text;
    final text = _editorController.text;
    if (!_findVisible || query.isEmpty || text.isEmpty) {
      _findMatches = const [];
      _findIndex = -1;
      return;
    }
    final matches = <int>[];
    final lowerQuery = query.toLowerCase();
    final lowerText = text.toLowerCase();
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) break;
      matches.add(index);
      start = index + lowerQuery.length;
    }
    _findMatches = matches;
    if (_findIndex >= matches.length) {
      _findIndex = matches.isEmpty ? -1 : 0;
    }
  }

  void _gotoFindMatch(int index) {
    if (_findMatches.isEmpty) return;
    final clamped =
        index < 0 ? _findMatches.length - 1 : index % _findMatches.length;
    setState(() => _findIndex = clamped);
    final start = _findMatches[clamped];
    _editorFocus.requestFocus();
    _editorController.selection = TextSelection(
      baseOffset: start,
      extentOffset: start + _findController.text.length,
    );
  }

  // ---------------------------------------------------------------------------
  // Grid helpers
  // ---------------------------------------------------------------------------

  List<String> _unionColumns(dynamic node) {
    if (node is! List) return const [];
    final columns = <String>[];
    for (final element in node) {
      if (element is Map) {
        for (final key in element.keys) {
          if (columns.length >= _maxColumns) return columns;
          if (!columns.contains(key.toString())) columns.add(key.toString());
        }
      }
    }
    return columns;
  }

  bool _textMatches(String text, String query) {
    if (_gridCaseSensitive) return text.contains(query);
    return text.toLowerCase().contains(query.toLowerCase());
  }

  bool _scalarMatches(dynamic value) {
    if (value is String) return _textMatches(value, _gridQuery);
    if (value is num || value is bool) {
      return _textMatches(value.toString(), _gridQuery);
    }
    return false;
  }

  /// Whether any key or scalar value in the subtree matches the grid query.
  bool _subtreeMatches(dynamic node) {
    if (_gridQuery.isEmpty) return true;
    return _visitMatch(node);
  }

  bool _visitMatch(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (_textMatches(entry.key.toString(), _gridQuery)) return true;
        if (_visitMatch(entry.value)) return true;
      }
      return false;
    }
    if (node is List) {
      for (final element in node) {
        if (_visitMatch(element)) return true;
      }
      return false;
    }
    return _scalarMatches(node);
  }

  void _toggleExpand(String path) {
    setState(() {
      if (!_expandedPaths.add(path)) {
        _expandedPaths.remove(path);
      } else {
        _lastExpandedPath = path;
      }
    });
  }

  void _expandAll() {
    var budget = 20000;
    void walk(dynamic node, String path) {
      if (budget <= 0) return;
      if (node is List) {
        budget--;
        _expandedPaths.add(path);
        for (var i = 0; i < node.length && budget > 0; i++) {
          walk(node[i], '$path/$i');
        }
      } else if (node is Map) {
        budget--;
        _expandedPaths.add(path);
        for (final key in node.keys) {
          if (budget <= 0) return;
          walk(node[key], '$path/${Uri.encodeComponent(key.toString())}');
        }
      }
    }

    setState(() {
      final node = _displayNode;
      if (node is List || node is Map) walk(node, '');
      _lastExpandedPath = null;
    });
  }

  void _collapseAll() {
    setState(() {
      _expandedPaths.clear();
      _rowLimits.clear();
      _lastExpandedPath = null;
    });
  }

  int _countMatches() {
    if (_gridQuery.isEmpty || _root == null) return 0;
    var count = 0;
    void visit(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (_textMatches(entry.key.toString(), _gridQuery)) count++;
          visit(entry.value);
        }
      } else if (node is List) {
        for (final element in node) {
          visit(element);
        }
      } else if (_scalarMatches(node)) {
        count++;
      }
    }

    visit(_root);
    return count;
  }

  // ---------------------------------------------------------------------------
  // Build: shell
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      padding: EdgeInsets.all(NexusSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split =
              (constraints.maxWidth * _leftFraction).clamp(300.0, 100000.0);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: split, child: _buildEditorPane(colorScheme)),
              _buildDivider(colorScheme),
              Expanded(child: _buildGridPane(colorScheme)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject()! as RenderBox;
        setState(() {
          _leftFraction =
              (_leftFraction + details.delta.dx / box.size.width)
                  .clamp(0.22, 0.78);
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 6,
              height: 52,
              decoration: BoxDecoration(
                color: colorScheme.muted,
                borderRadius: NexusRadii.fullRadius,
              ),
              child: Icon(
                LucideIcons.chevronsLeftRight,
                size: 10,
                color: colorScheme.mutedForeground,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paneHeader({
    required String title,
    required List<Widget> actions,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
      decoration: const BoxDecoration(
        color: _colorHeaderBar,
        borderRadius: NexusRadii.smRadius,
      ),
      child: Row(
        children: [
          Text(
            title,
            style: NexusTypography.labelMd.copyWith(
              color: const Color(0xFFFFFFFF),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          ...actions.expand(
            (action) sync* {
              yield action;
              yield const SizedBox(width: NexusSpacing.xs);
            },
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? color : color.withValues(alpha: 0.35),
          borderRadius: NexusRadii.smRadius,
        ),
        child: Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            color: const Color(0xFFFFFFFF),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build: editor pane
  // ---------------------------------------------------------------------------

  Widget _buildEditorPane(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.border),
        borderRadius: NexusRadii.mdRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paneHeader(
            title: 'JSON',
            actions: [
              _headerButton(
                label: 'Sample',
                color: const Color(0xFF6B7280),
                onPressed: _loadSample,
              ),
              _headerButton(
                label: 'Search',
                color: const Color(0xFF2563EB),
                onPressed: () {
                  setState(() => _findVisible = !_findVisible);
                  _recomputeFindMatches();
                },
              ),
              _headerButton(
                label: 'Format',
                color: const Color(0xFF7C3AED),
                onPressed: () => _format(),
              ),
              _headerButton(
                label: 'Minify',
                color: const Color(0xFF0EA5E9),
                onPressed: () => _format(minify: true),
              ),
              _headerButton(
                label: 'Validate',
                color: _colorValid,
                onPressed: _validate,
              ),
              _headerButton(
                label: 'Clear',
                color: const Color(0xFFD97706),
                onPressed: _clear,
              ),
            ],
          ),
          if (_findVisible) _buildFindBar(colorScheme),
          if (_error != null) _buildErrorBanner(colorScheme),
          Expanded(child: _buildEditor(colorScheme)),
          _buildEditorStatusBar(colorScheme),
        ],
      ),
    );
  }

  Widget _buildFindBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 14, color: colorScheme.mutedForeground),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: TextField(
              controller: _findController,
              border: const Border(),
              padding: const EdgeInsets.symmetric(vertical: 2),
              placeholder: Text(
                'Find in JSON...',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              style: NexusTypography.labelSm,
              onSubmitted: (_) => _gotoFindMatch(_findIndex + 1),
            ),
          ),
          Text(
            _findController.text.isEmpty
                ? ''
                : '${_findMatches.isEmpty ? 0 : _findIndex + 1}/${_findMatches.length}',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.chevronUp, size: 14),
            onPressed:
                _findMatches.isEmpty ? null : () => _gotoFindMatch(_findIndex - 1),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.chevronDown, size: 14),
            onPressed:
                _findMatches.isEmpty ? null : () => _gotoFindMatch(_findIndex + 1),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.x, size: 14),
            onPressed: () {
              setState(() {
                _findVisible = false;
                _findController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(ColorScheme colorScheme) {
    final location = (_errorLine != null && _errorColumn != null)
        ? ' (line $_errorLine, column $_errorColumn)'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.destructive.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 14,
            color: colorScheme.destructive,
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Text(
              'Invalid JSON$location: ${_error!}',
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.destructive,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditor(ColorScheme colorScheme) {
    final text = _editorController.text;
    final lineCount = math.max(1, text.split('\n').length);
    _editorController.highlightEnabled = text.length <= 200 * 1024;

    final monoBase = TextStyle(
      fontFamily: _monoFont,
      fontSize: 13,
      height: _lineHeight / 13,
      color: colorScheme.foreground,
    );

    final gutter = Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: NexusSpacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.3),
        border: Border(right: BorderSide(color: colorScheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 1; i <= lineCount; i++)
            SizedBox(
              height: _lineHeight,
              child: Padding(
                padding: const EdgeInsets.only(right: NexusSpacing.sm),
                child: Text(
                  '$i',
                  textAlign: TextAlign.right,
                  style: monoBase.copyWith(
                    fontSize: 12,
                    color: colorScheme.mutedForeground.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final field = TextField(
      controller: _editorController,
      focusNode: _editorFocus,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      style: monoBase,
      border: const Border(),
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.sm,
      ),
      placeholder: text.isEmpty
          ? Text(
              'Paste JSON here, then click Format or Validate...',
              style: monoBase.copyWith(color: colorScheme.mutedForeground),
            )
          : null,
    );

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gutter,
          Expanded(child: field),
        ],
      ),
    );
  }

  Widget _buildEditorStatusBar(ColorScheme colorScheme) {
    final text = _editorController.text;
    final lines = text.isEmpty ? 0 : text.split('\n').length;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.2),
        border: Border(top: BorderSide(color: colorScheme.border)),
      ),
      child: Row(
        children: [
          if (_valid) ...[
            const Icon(LucideIcons.circleCheck,
                size: 12, color: _colorValid),
            const SizedBox(width: NexusSpacing.xs),
            Text(
              'Valid JSON',
              style: NexusTypography.labelSm.copyWith(
                color: _colorValid,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
          ],
          Text(
            '$lines lines · ${text.length} chars',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build: grid pane
  // ---------------------------------------------------------------------------

  Widget _buildGridPane(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.border),
        borderRadius: NexusRadii.mdRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paneHeader(
            title: 'GRID',
            actions: [
              _headerButton(
                label: 'Advanced Filter',
                color: _colorValid,
                onPressed: () {
                  setState(() => _advancedFilterOpen = !_advancedFilterOpen);
                },
              ),
              _headerButton(
                label: 'Search',
                color: const Color(0xFF2563EB),
                onPressed: () {
                  setState(() => _gridSearchVisible = !_gridSearchVisible);
                },
              ),
              _headerButton(
                label: 'Expand All',
                color: const Color(0xFF2563EB),
                onPressed: _root == null ? null : _expandAll,
              ),
              _headerButton(
                label: 'Collapse All',
                color: const Color(0xFF2563EB),
                onPressed: _root == null ? null : _collapseAll,
              ),
            ],
          ),
          if (_gridSearchVisible) _buildGridSearchBar(colorScheme),
          if (_advancedFilterOpen) _buildAdvancedFilterPanel(colorScheme),
          _buildGridBreadcrumb(colorScheme),
          Expanded(child: _buildGridViewport(colorScheme)),
        ],
      ),
    );
  }

  Widget _buildGridSearchBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.search, size: 14, color: colorScheme.mutedForeground),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: TextField(
              controller: _gridSearchController,
              border: const Border(),
              padding: const EdgeInsets.symmetric(vertical: 2),
              placeholder: Text(
                'Filter rows by key or value...',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              style: NexusTypography.labelSm,
            ),
          ),
          Text(
            _gridQuery.isEmpty ? '' : '${_countMatches()} match(es)',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.x, size: 14),
            onPressed: () {
              setState(() {
                _gridSearchVisible = false;
                _gridSearchController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedFilterPanel(ColorScheme colorScheme) {
    final hasColumns = _rootColumns.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.2),
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Case sensitive',
                style:
                    NexusTypography.labelSm.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: NexusSpacing.sm),
              _FilterToggleChip(
                label: _gridCaseSensitive ? 'On' : 'Off',
                selected: _gridCaseSensitive,
                onTap: () {
                  setState(
                      () => _gridCaseSensitive = !_gridCaseSensitive);
                },
              ),
              const Spacer(),
              IconButton.ghost(
                icon: const Icon(LucideIcons.x, size: 14),
                onPressed: () {
                  setState(() => _advancedFilterOpen = false);
                },
              ),
            ],
          ),
          if (hasColumns) ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              'Columns',
              style:
                  NexusTypography.labelSm.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: NexusSpacing.xs),
            Wrap(
              spacing: NexusSpacing.xs,
              runSpacing: NexusSpacing.xs,
              children: [
                for (final column in _rootColumns)
                  _FilterToggleChip(
                    label: column,
                    selected: !_hiddenColumns.contains(column),
                    onTap: () {
                      setState(() {
                        if (!_hiddenColumns.add(column)) {
                          _hiddenColumns.remove(column);
                        }
                      });
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGridBreadcrumb(ColorScheme colorScheme) {
    final children = <Widget>[
      Icon(LucideIcons.braces, size: 12, color: colorScheme.mutedForeground),
      const SizedBox(width: NexusSpacing.xs),
      Text(
        _rootSummary(),
        style: NexusTypography.labelSm.copyWith(
          color: colorScheme.mutedForeground,
        ),
      ),
    ];
    if (_lastExpandedPath != null) {
      for (final label in _pathLabels(_lastExpandedPath!)) {
        children.addAll([
          const SizedBox(width: NexusSpacing.xs),
          Text(
            '›',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: NexusSpacing.xs),
          Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]);
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: children),
      ),
    );
  }

  String _rootSummary() {
    if (_root == null) return 'no data';
    final node = _displayNode;
    final name = _displayName;
    if (node is List) return '$name[${node.length}]';
    if (node is Map) return '$name{${node.length}}';
    return name;
  }

  /// Breadcrumb labels for a grid path, e.g. `completions`, `1`, `meta`.
  /// Consecutive key + index segments merge into `key[N]` style labels.
  List<String> _pathLabels(String path) {
    final labels = <String>[];
    for (final raw in path.split('/').skip(1)) {
      final segment = Uri.decodeComponent(raw);
      final index = int.tryParse(segment);
      if (index != null) {
        if (labels.isNotEmpty) {
          labels[labels.length - 1] = '${labels.last}[$index]';
        } else {
          labels.add('[$index]');
        }
      } else {
        labels.add(segment);
      }
    }
    return labels;
  }

  /// The node the grid renders: a single-entry object root whose value is a
  /// container is unwrapped so the grid starts at the meaningful table.
  static dynamic _unwrapNode(dynamic root) {
    if (root is Map && root.length == 1) {
      final value = root.values.first;
      if (value is List || value is Map) return value;
    }
    return root;
  }

  dynamic get _displayNode => _unwrapNode(_root);

  String get _displayName {
    final root = _root;
    if (root is Map && root.length == 1) {
      final value = root.values.first;
      if (value is List || value is Map) return root.keys.first.toString();
    }
    return 'root';
  }

  Widget _buildGridViewport(ColorScheme colorScheme) {
    if (_root == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.table,
              size: 40,
              color: colorScheme.mutedForeground,
            ),
            const SizedBox(height: NexusSpacing.md),
            Text(
              _error != null
                  ? 'Fix the JSON error, then click Format or Validate'
                  : 'Click Format or Validate to render the grid',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            child: Padding(
              padding: const EdgeInsets.all(NexusSpacing.sm),
              child: _buildNode(
                colorScheme,
                _displayNode,
                path: '',
                name: _displayName,
                depth: 0,
                forceExpanded: true,
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Build: recursive grid tables
  // ---------------------------------------------------------------------------

  /// Builds the widget for a JSON node. Containers render an expand chip and,
  /// when expanded, a nested table (arrays as numbered rows, objects as
  /// key/value rows). Scalars render as colored text.
  Widget _buildNode(
    ColorScheme colorScheme,
    dynamic node, {
    required String path,
    required String name,
    required int depth,
    bool forceExpanded = false,
  }) {
    if (node is! List && node is! Map) {
      return _scalarCell(colorScheme, node);
    }

    final suffix = node is List ? '[${node.length}]' : '{${node.length}}';
    final queryActive = _gridQuery.isNotEmpty && _subtreeMatches(node);
    final expanded =
        forceExpanded || _expandedPaths.contains(path) || queryActive;

    final chip = _ExpandChip(
      label: '$name$suffix',
      expanded: expanded,
      onTap: () => _toggleExpand(path),
    );

    if (!expanded) {
      return Align(alignment: Alignment.centerLeft, child: chip);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!forceExpanded) chip,
        if (!forceExpanded) const SizedBox(height: NexusSpacing.xs),
        if (node is List)
          _buildArrayTable(colorScheme, node,
              path: path, name: name, depth: depth)
        else
          _buildObjectTable(colorScheme, node as Map,
              path: path, depth: depth),
      ],
    );
  }

  Widget _buildArrayTable(
    ColorScheme colorScheme,
    List elements, {
    required String path,
    required String name,
    required int depth,
  }) {
    var mapCount = 0;
    for (final element in elements) {
      if (element is Map) mapCount++;
    }
    final useColumns = mapCount * 2 >= elements.length && elements.isNotEmpty;
    final columns = useColumns
        ? (depth == 0
                ? _rootColumns
                : _unionColumns(elements))
            .where((c) => !_hiddenColumns.contains(c))
            .toList()
        : const <String>[];

    final rows = <Widget>[];
    if (useColumns) {
      rows.add(_headerRow(colorScheme, columns));
    } else if (depth > 0 && elements.isNotEmpty) {
      rows.add(_headerRow(colorScheme, [name]));
    }

    final query = _gridQuery;
    final matchingIndices = <int>[];
    for (var i = 0; i < elements.length; i++) {
      if (_subtreeMatches(elements[i])) matchingIndices.add(i);
    }

    final limit = _rowLimits[path] ?? _defaultRowLimit;
    final renderedCount = math.min(matchingIndices.length, limit);
    for (var r = 0; r < renderedCount; r++) {
      final i = matchingIndices[r];
      final element = elements[i];
      final cells = useColumns
          ? [
              for (var c = 0; c < columns.length; c++)
                _buildCellContent(
                  colorScheme,
                  element is Map ? element[columns[c]] : (c == 0 ? element : null),
                  path: element is Map
                      ? '$path/$i/${Uri.encodeComponent(columns[c])}'
                      : '$path/$i',
                  name: columns[c],
                  depth: depth + 1,
                ),
            ]
          : [
              _buildCellContent(
                colorScheme,
                element,
                path: '$path/$i',
                name: '',
                depth: depth + 1,
              ),
            ];
      rows.add(
        _gridRow(
          colorScheme,
          index: i + 1,
          isLast: r == renderedCount - 1,
          cells: cells,
        ),
      );
    }

    final hiddenCount = matchingIndices.length - renderedCount;
    if (hiddenCount > 0) {
      rows.add(_moreRow(colorScheme, hiddenCount, () {
        setState(() => _rowLimits[path] = limit + _defaultRowLimit);
      }));
    }
    if (rows.isEmpty) {
      rows.add(
        _emptyRow(
          colorScheme,
          query.isNotEmpty ? 'No matching rows' : 'Empty array',
        ),
      );
    }

    return _tableContainer(colorScheme, rows);
  }

  Widget _buildObjectTable(
    ColorScheme colorScheme,
    Map entries, {
    required String path,
    required int depth,
  }) {
    final query = _gridQuery;
    final matchingKeys = <String>[];
    for (final key in entries.keys) {
      final value = entries[key];
      final matches = query.isEmpty ||
          _textMatches(key.toString(), query) ||
          _visitMatch(value);
      if (matches) matchingKeys.add(key.toString());
    }

    final rows = <Widget>[];
    final limit = _rowLimits[path] ?? _defaultRowLimit;
    final renderedCount = math.min(matchingKeys.length, limit);
    for (var r = 0; r < renderedCount; r++) {
      final key = matchingKeys[r];
      final value = entries[key];
      rows.add(
        _gridRow(
          colorScheme,
          index: r + 1,
          isLast: r == renderedCount - 1,
          leading: _keyCell(colorScheme, key),
          cells: [
            _buildCellContent(
              colorScheme,
              value,
              path: '$path/${Uri.encodeComponent(key)}',
              name: key,
              depth: depth + 1,
            ),
          ],
        ),
      );
    }

    final hiddenCount = matchingKeys.length - renderedCount;
    if (hiddenCount > 0) {
      rows.add(_moreRow(colorScheme, hiddenCount, () {
        setState(() => _rowLimits[path] = limit + _defaultRowLimit);
      }));
    }
    if (rows.isEmpty) {
      rows.add(
        _emptyRow(
          colorScheme,
          query.isNotEmpty ? 'No matching keys' : 'Empty object',
        ),
      );
    }

    return _tableContainer(colorScheme, rows);
  }

  Widget _tableContainer(ColorScheme colorScheme, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.border),
        borderRadius: NexusRadii.smRadius,
        color: colorScheme.background,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: rows,
      ),
    );
  }

  Widget _headerRow(ColorScheme colorScheme, List<String> columns) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 36),
          for (var i = 0; i < columns.length; i++)
            Expanded(
              child: Container(
                padding: EdgeInsets.only(left: i == 0 ? 0 : NexusSpacing.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        columns[i],
                        style: NexusTypography.labelSm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor:
                              colorScheme.primary.withValues(alpha: 0.4),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.xs),
                    Icon(
                      LucideIcons.listFilter,
                      size: 11,
                      color: colorScheme.mutedForeground,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gridRow(
    ColorScheme colorScheme, {
    required int index,
    required List<Widget> cells,
    Widget? leading,
    required bool isLast,
  }) {
    return Container(
      decoration: isLast
          ? null
          : BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: colorScheme.border))),
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Row(
              children: [
                Icon(
                  LucideIcons.gripVertical,
                  size: 10,
                  color: colorScheme.mutedForeground.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 2),
                Text(
                  '$index',
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          ?leading,
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Container(
                padding: EdgeInsets.only(left: i == 0 ? 0 : NexusSpacing.sm),
                child: cells[i],
              ),
            ),
        ],
      ),
    );
  }

  Widget _keyCell(ColorScheme colorScheme, String key) {
    return Text(
        '$key:',
        style: NexusTypography.labelSm.copyWith(
          fontFamily: _monoFont,
          fontWeight: FontWeight.w600,
          color: _colorKey,
        ),
        overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildCellContent(
    ColorScheme colorScheme,
    dynamic value, {
    required String path,
    required String name,
    required int depth,
  }) {
    if (value == null) return const SizedBox.shrink();
    if (value is List || value is Map) {
      return _buildNode(
        colorScheme,
        value,
        path: path,
        name: name,
        depth: depth,
      );
    }
    return _scalarCell(colorScheme, value);
  }

  Widget _scalarCell(ColorScheme colorScheme, dynamic value) {
    final text = value is String ? '"$value"' : value.toString();
    final spans = <TextSpan>[];
    for (final (start, end, type) in _tokenizeJson(text)) {
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(color: _tokenColor(type)),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: _monoFont,
            fontSize: 12.5,
            height: 1.35,
            color: colorScheme.foreground,
          ),
          children: spans.isEmpty ? [TextSpan(text: text)] : spans,
        ),
      ),
    );
  }

  Color _tokenColor(_JsonTokenType type) {
    return switch (type) {
      _JsonTokenType.key => _colorKey,
      _JsonTokenType.string => _colorString,
      _JsonTokenType.number => _colorNumber,
      _JsonTokenType.boolean => _colorBoolean,
      _JsonTokenType.nullValue => _colorNull,
      _JsonTokenType.punctuation => _colorPunctuation,
    };
  }

  Widget _moreRow(ColorScheme colorScheme, int hidden, VoidCallback onLoadMore) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.25),
        border: Border(top: BorderSide(color: colorScheme.border)),
      ),
      child: GestureDetector(
        onTap: onLoadMore,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.chevronDown,
              size: 12,
              color: colorScheme.primary,
            ),
            const SizedBox(width: NexusSpacing.xs),
            Text(
              'Show $hidden more rows',
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyRow(ColorScheme colorScheme, String message) {
    return Padding(
      padding: const EdgeInsets.all(NexusSpacing.sm),
      child: Text(
        message,
        style: NexusTypography.labelSm.copyWith(
          color: colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

enum _JsonTokenType { key, string, number, boolean, nullValue, punctuation }

Color _tokenColorOf(_JsonTokenType type) {
  return switch (type) {
    _JsonTokenType.key => const Color(0xFFA31515),
    _JsonTokenType.string => const Color(0xFF986801),
    _JsonTokenType.number => const Color(0xFFC7361B),
    _JsonTokenType.boolean => const Color(0xFFD7263D),
    _JsonTokenType.nullValue => const Color(0xFF8B8B8B),
    _JsonTokenType.punctuation => const Color(0xFF6B7280),
  };
}

/// A lightweight JSON tokenizer producing (start, end, type) segments used
/// for syntax highlighting in the editor and the grid cells.
List<(int, int, _JsonTokenType)> _tokenizeJson(String text) {
  final segments = <(int, int, _JsonTokenType)>[];
  final length = text.length;
  var i = 0;

  void flush(int start, int end, _JsonTokenType type) {
    if (end > start) segments.add((start, end, type));
  }

  while (i < length) {
    final ch = text[i];
    if (ch == '"') {
      final start = i;
      i++;
      while (i < length) {
        if (text[i] == r'\') {
          i += 2;
          continue;
        }
        if (text[i] == '"') {
          i++;
          break;
        }
        i++;
      }
      // A string followed by ':' is a property key.
      var j = i;
      while (j < length && (text[j] == ' ' || text[j] == '\t')) {
        j++;
      }
      final isKey = j < length && text[j] == ':';
      flush(start, i, isKey ? _JsonTokenType.key : _JsonTokenType.string);
      continue;
    }
    if (ch == '-' || (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39)) {
      final start = i;
      i++;
      while (i < length) {
        final code = text.codeUnitAt(i);
        final isDigit = code >= 0x30 && code <= 0x39;
        final isNumericChar = text[i] == '.' ||
            text[i] == 'e' ||
            text[i] == 'E' ||
            text[i] == '+' ||
            text[i] == '-';
        if (!isDigit && !isNumericChar) break;
        i++;
      }
      flush(start, i, _JsonTokenType.number);
      continue;
    }
    if (text.startsWith('true', i)) {
      flush(i, i + 4, _JsonTokenType.boolean);
      i += 4;
      continue;
    }
    if (text.startsWith('false', i)) {
      flush(i, i + 5, _JsonTokenType.boolean);
      i += 5;
      continue;
    }
    if (text.startsWith('null', i)) {
      flush(i, i + 4, _JsonTokenType.nullValue);
      i += 4;
      continue;
    }
    // Punctuation / whitespace run until the next token start.
    final start = i;
    while (i < length) {
      final c = text[i];
      if (c == '"' ||
          c == '-' ||
          text.startsWith('true', i) ||
          text.startsWith('false', i) ||
          text.startsWith('null', i) ||
          (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39)) {
        break;
      }
      i++;
    }
    flush(start, i, _JsonTokenType.punctuation);
    if (start == i) i++; // safety: never stall
  }
  return segments;
}

/// A [TextEditingController] that renders JSON with syntax highlighting
/// through [buildTextSpan].
class _JsonHighlightController extends TextEditingController {
  bool highlightEnabled = true;

  static const int _maxHighlightLength = 200 * 1024;

  String? _cacheKey;
  List<(int, int, _JsonTokenType)>? _cachedSegments;

  List<(int, int, _JsonTokenType)> _segments(String text) {
    if (_cacheKey == text && _cachedSegments != null) return _cachedSegments!;
    final segments = text.length <= _maxHighlightLength
        ? _tokenizeJson(text)
        : const <(int, int, _JsonTokenType)>[];
    _cacheKey = text;
    _cachedSegments = segments;
    return segments;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final segments = _segments(text);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final (start, end, type) in segments) {
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: TextStyle(color: _tokenColorOf(type)),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return TextSpan(style: style, children: spans);
  }
}

class _ExpandChip extends StatelessWidget {
  const _ExpandChip({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.45),
          ),
          borderRadius: NexusRadii.smRadius,
          color: colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(
                expanded ? LucideIcons.minus : LucideIcons.plus,
                size: 10,
                color: const Color(0xFFFFFFFF),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: NexusTypography.labelSm.copyWith(
                  fontFamily: 'Consolas',
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: colorScheme.primary.withValues(alpha: 0.4),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterToggleChip extends StatelessWidget {
  const _FilterToggleChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.border,
          ),
          borderRadius: NexusRadii.smRadius,
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            color: selected ? colorScheme.primary : colorScheme.foreground,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

const String _sampleJson = '''
{
  "completions": [
    {
      "match": [
        "has:",
        "-is:"
      ],
      "options": [
        "has:",
        "is:",
        "license:",
        "platform:",
        "sdk:",
        "show:",
        "topic:",
        "runtime:",
        "dependency:",
        "publisher:",
        "updated:"
      ],
      "terminal": false,
      "forcedOnly": true
    },
    {
      "match": [
        "is:",
        "-is:"
      ],
      "options": [
        "dart3-compatible",
        "flutter-favorite",
        "legacy",
        "null-safe",
        "plugin",
        "swiftpm-plugin",
        "unlisted",
        "was-ready"
      ],
      "terminal": true,
      "forcedOnly": false
    },
    {
      "match": [
        "has:",
        "-has:"
      ],
      "options": [
        "executable",
        "screenshot"
      ],
      "terminal": true,
      "forcedOnly": false
    },
    {
      "match": [
        "license:",
        "-license:"
      ],
      "options": [
        "osi-approved",
        "0bsd",
        "afl-1.1",
        "afl-1.2",
        "afl-2.0",
        "afl-2.1",
        "afl-3.0",
        "agpl-1.0",
        "agpl-3.0",
        "apache-1.0",
        "apache-2.0",
        "artistic-2.0",
        "bsd-2-clause",
        "bsd-3-clause",
        "mit",
        "mpl-2.0",
        "zlib"
      ],
      "terminal": false,
      "forcedOnly": true
    },
    {
      "match": [
        "runtime:",
        "-runtime:"
      ],
      "options": [
        "dart",
        "flutter",
        "flutter-web",
        "web"
      ],
      "terminal": true,
      "forcedOnly": false
    },
    {
      "match": [
        "topic:",
        "-topic:"
      ],
      "options": [
        "app",
        "backend",
        "cli",
        "database",
        "devtools",
        "gui",
        "http",
        "mobile",
        "network",
        "server",
        "testing",
        "ui",
        "web"
      ],
      "terminal": false,
      "forcedOnly": true
    },
    {
      "match": [
        "show:",
        "-show:"
      ],
      "options": [
        "deprecated",
        "discontinued",
        "unclassified",
        "unverified"
      ],
      "terminal": false,
      "forcedOnly": true
    },
    {
      "match": [
        "publisher:",
        "-publisher:"
      ],
      "options": [
        "dart.dev",
        "flutter.dev",
        "verified"
      ],
      "terminal": true,
      "forcedOnly": false
    },
    {
      "match": [
        "dependency:",
        "-dependency:"
      ],
      "options": [
        "direct main",
        "direct dev",
        "transitive"
      ],
      "terminal": false,
      "forcedOnly": true,
      "meta": {
        "counts": {
          "direct": 42,
          "dev": 7,
          "transitive": 318
        },
        "resolved": [
          "meta",
          "path",
          "http"
        ]
      }
    },
    {
      "match": [
        "updated:",
        "-updated:"
      ],
      "options": [
        "today",
        "last 7 days",
        "last 30 days",
        "this year"
      ],
      "terminal": true,
      "forcedOnly": false
    }
  ]
}
''';
