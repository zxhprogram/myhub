import 'package:diff_match_patch/diff_match_patch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'nexus_button.dart';
import 'nexus_card.dart';
import 'nexus_input.dart';

enum _DiffMode { sideBySide, inline }

enum _DiffGranularity { line, character }

class NexusDiffViewer extends StatefulWidget {
  const NexusDiffViewer({super.key});

  @override
  State<NexusDiffViewer> createState() => _NexusDiffViewerState();
}

class _NexusDiffViewerState extends State<NexusDiffViewer> {
  final _oldController = TextEditingController();
  final _newController = TextEditingController();

  _DiffMode _mode = _DiffMode.sideBySide;
  _DiffGranularity _granularity = _DiffGranularity.character;
  bool _ignoreWhitespace = false;
  String _language = 'Plain Text';

  List<Diff> _rawDiffs = [];
  List<_DiffLine> _diffLines = [];

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

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    super.dispose();
  }

  void _compare() {
    var oldText = _oldController.text;
    var newText = _newController.text;

    if (_ignoreWhitespace) {
      oldText = _normalizeWhitespace(oldText);
      newText = _normalizeWhitespace(newText);
    }

    final dmp = DiffMatchPatch();
    _rawDiffs = dmp.diff(oldText, newText);

    if (_granularity == _DiffGranularity.line) {
      _diffLines = _buildLineDiffs(_rawDiffs, highlightChanges: false);
    } else {
      _diffLines = _buildLineDiffs(_rawDiffs, highlightChanges: true);
    }

    setState(() {});
  }

  String _normalizeWhitespace(String text) {
    return text
        .split('\n')
        .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
        .join('\n');
  }

  List<_DiffLine> _buildLineDiffs(
    List<Diff> diffs, {
    required bool highlightChanges,
  }) {
    final lines = <_DiffLine>[];
    var oldLine = 1;
    var newLine = 1;

    final oldBuffer = StringBuffer();
    final newBuffer = StringBuffer();
    final oldSpans = <TextSpan>[];
    final newSpans = <TextSpan>[];

    void flush() {
      final oldText = oldBuffer.toString();
      final newText = newBuffer.toString();
      final hasOld = oldSpans.isNotEmpty || oldText.isNotEmpty;
      final hasNew = newSpans.isNotEmpty || newText.isNotEmpty;

      if (!hasOld && !hasNew) return;

      _DiffLine line;
      if (hasOld && !hasNew) {
        line = _DiffLine(
          type: _DiffType.delete,
          oldLineNumber: oldLine,
          newLineNumber: null,
          oldSpans: oldSpans.isEmpty
              ? [TextSpan(text: oldText)]
              : [...oldSpans],
          newSpans: const [TextSpan(text: '')],
          rawText: oldText,
        );
        oldLine++;
      } else if (!hasOld && hasNew) {
        line = _DiffLine(
          type: _DiffType.insert,
          oldLineNumber: null,
          newLineNumber: newLine,
          oldSpans: const [TextSpan(text: '')],
          newSpans: newSpans.isEmpty
              ? [TextSpan(text: newText)]
              : [...newSpans],
          rawText: newText,
        );
        newLine++;
      } else {
        final isEqual = oldText == newText;
        line = _DiffLine(
          type: isEqual ? _DiffType.equal : _DiffType.modify,
          oldLineNumber: oldLine,
          newLineNumber: newLine,
          oldSpans: oldSpans.isEmpty
              ? [TextSpan(text: oldText)]
              : [...oldSpans],
          newSpans: newSpans.isEmpty
              ? [TextSpan(text: newText)]
              : [...newSpans],
          rawText: isEqual ? oldText : '- $oldText\n+ $newText',
        );
        oldLine++;
        newLine++;
      }

      lines.add(line);
      oldBuffer.clear();
      newBuffer.clear();
      oldSpans.clear();
      newSpans.clear();
    }

    for (final diff in diffs) {
      final text = diff.text;
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        final part = parts[i];
        final isLast = i == parts.length - 1;

        if (diff.operation == DIFF_EQUAL) {
          oldBuffer.write(part);
          newBuffer.write(part);
          oldSpans.add(_span(part, _DiffType.equal));
          newSpans.add(_span(part, _DiffType.equal));
        } else if (diff.operation == DIFF_DELETE) {
          oldBuffer.write(part);
          oldSpans.add(
            _span(part, _DiffType.delete, highlight: highlightChanges),
          );
        } else if (diff.operation == DIFF_INSERT) {
          newBuffer.write(part);
          newSpans.add(
            _span(part, _DiffType.insert, highlight: highlightChanges),
          );
        }

        if (!isLast) {
          flush();
        }
      }
    }
    flush();
    return lines;
  }

  TextSpan _span(String text, _DiffType type, {bool highlight = false}) {
    final baseStyle = NexusTypography.bodyMd;
    Color? backgroundColor;
    Color? foregroundColor;

    switch (type) {
      case _DiffType.delete:
        backgroundColor = NexusColors.errorContainer;
        foregroundColor = NexusColors.error;
      case _DiffType.insert:
        backgroundColor = NexusColors.tertiaryContainer;
        foregroundColor = NexusColors.tertiary;
      case _DiffType.equal || _DiffType.modify:
        backgroundColor = null;
        foregroundColor = NexusColors.onSurface;
    }

    if (!highlight) {
      backgroundColor = null;
      if (type != _DiffType.equal) {
        foregroundColor = type == _DiffType.delete
            ? NexusColors.error
            : NexusColors.tertiary;
      }
    }

    final spans = _highlight(
      text,
      _language,
      baseStyle.copyWith(
        color: foregroundColor,
        backgroundColor: backgroundColor,
      ),
    );

    if (spans.length == 1 &&
        spans.first.style?.color == foregroundColor &&
        spans.first.style?.backgroundColor == backgroundColor) {
      return spans.first;
    }

    return TextSpan(
      children: spans
          .map(
            (s) => TextSpan(
              text: s.text,
              style: (s.style ?? baseStyle).copyWith(
                backgroundColor: backgroundColor,
              ),
            ),
          )
          .toList(),
    );
  }

  Future<void> _copyResult() async {
    final buffer = StringBuffer();
    for (final line in _diffLines) {
      switch (line.type) {
        case _DiffType.equal:
          buffer.writeln('  ${line.rawText}');
        case _DiffType.insert:
          buffer.writeln('+ ${line.rawText}');
        case _DiffType.delete:
          buffer.writeln('- ${line.rawText}');
        case _DiffType.modify:
          buffer.writeln(line.rawText);
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Diff copied to clipboard')));
    }
  }

  void _clear() {
    _oldController.clear();
    _newController.clear();
    setState(() {
      _rawDiffs = [];
      _diffLines = [];
    });
  }

  void _loadSample() {
    _oldController.text = '''{
  "name": "Alice",
  "age": 30,
  "city": "New York"
}''';
    _newController.text = '''{
  "name": "Alice",
  "age": 31,
  "city": "San Francisco"
}''';
    _language = 'JSON';
    _compare();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputArea(),
        const SizedBox(height: NexusSpacing.md),
        _buildToolbar(),
        const SizedBox(height: NexusSpacing.md),
        _buildOutput(),
      ],
    );
  }

  Widget _buildInputArea() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 700;
        final oldInput = NexusInput(
          controller: _oldController,
          labelText: 'Original Text',
          hintText: 'Paste original text here...',
          maxLines: 5,
        );
        final newInput = NexusInput(
          controller: _newController,
          labelText: 'Modified Text',
          hintText: 'Paste modified text here...',
          maxLines: 5,
        );
        return isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: oldInput),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(child: newInput),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 150, child: oldInput),
                  const SizedBox(height: NexusSpacing.md),
                  SizedBox(height: 150, child: newInput),
                ],
              );
      },
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
          label: _mode == _DiffMode.sideBySide ? 'Inline' : 'Side by Side',
          variant: NexusButtonVariant.outlined,
          onPressed: () => setState(
            () => _mode = _mode == _DiffMode.sideBySide
                ? _DiffMode.inline
                : _DiffMode.sideBySide,
          ),
        ),
        NexusButton(
          label: _granularity == _DiffGranularity.line
              ? 'Character Level'
              : 'Line Level',
          variant: NexusButtonVariant.outlined,
          onPressed: () => setState(() {
            _granularity = _granularity == _DiffGranularity.line
                ? _DiffGranularity.character
                : _DiffGranularity.line;
            if (_diffLines.isNotEmpty) _compare();
          }),
        ),
        _IgnoreWhitespaceChip(
          value: _ignoreWhitespace,
          onChanged: (value) => setState(() {
            _ignoreWhitespace = value;
            if (_diffLines.isNotEmpty) _compare();
          }),
        ),
        _LanguageDropdown(
          value: _language,
          languages: _languages,
          onChanged: (value) {
            if (value == null) return;
            setState(() => _language = value);
          },
        ),
        NexusButton(
          label: 'Copy',
          variant: NexusButtonVariant.text,
          onPressed: _diffLines.isEmpty ? null : _copyResult,
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

  Widget _buildOutput() {
    if (_diffLines.isEmpty) {
      return NexusCard(
        child: SizedBox(
          height: 300,
          child: Center(
            child: Text(
              'Enter two texts and click Compare',
              style: NexusTypography.bodyMd.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return NexusCard(
      padding: EdgeInsets.zero,
      child: Container(
        height: 500,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(NexusRadii.md),
        ),
        clipBehavior: Clip.antiAlias,
        child: _mode == _DiffMode.sideBySide
            ? _SideBySideDiff(lines: _diffLines, language: _language)
            : _InlineDiff(lines: _diffLines, language: _language),
      ),
    );
  }
}

class _DiffLine {
  const _DiffLine({
    required this.type,
    required this.oldLineNumber,
    required this.newLineNumber,
    required this.oldSpans,
    required this.newSpans,
    required this.rawText,
  });

  final _DiffType type;
  final int? oldLineNumber;
  final int? newLineNumber;
  final List<TextSpan> oldSpans;
  final List<TextSpan> newSpans;
  final String rawText;
}

enum _DiffType { equal, insert, delete, modify }

class _SideBySideDiff extends StatelessWidget {
  const _SideBySideDiff({required this.lines, required this.language});

  final List<_DiffLine> lines;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DiffColumn(
            title: 'Original',
            lines: lines,
            isOld: true,
            language: language,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _DiffColumn(
            title: 'Modified',
            lines: lines,
            isOld: false,
            language: language,
          ),
        ),
      ],
    );
  }
}

class _DiffColumn extends StatelessWidget {
  const _DiffColumn({
    required this.title,
    required this.lines,
    required this.isOld,
    required this.language,
  });

  final String title;
  final List<_DiffLine> lines;
  final bool isOld;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(NexusSpacing.sm),
          decoration: BoxDecoration(
            color: NexusColors.surfaceContainer,
            border: Border(
              bottom: BorderSide(color: NexusColors.outlineVariant),
            ),
          ),
          child: Text(
            title,
            style: NexusTypography.labelMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final lineNumber = isOld
                  ? line.oldLineNumber
                  : line.newLineNumber;
              final spans = isOld ? line.oldSpans : line.newSpans;

              final backgroundColor = switch (line.type) {
                _DiffType.equal => Colors.transparent,
                _DiffType.delete =>
                  isOld ? NexusColors.errorContainer : Colors.transparent,
                _DiffType.insert =>
                  isOld ? Colors.transparent : NexusColors.tertiaryContainer,
                _DiffType.modify => Colors.transparent,
              };

              return Container(
                color: backgroundColor,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexusSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: NexusColors.surfaceContainerLow,
                        border: Border(
                          right: BorderSide(color: NexusColors.outlineVariant),
                        ),
                      ),
                      child: Text(
                        lineNumber?.toString() ?? '',
                        style: NexusTypography.labelSm.copyWith(
                          color: NexusColors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexusSpacing.sm,
                          vertical: 2,
                        ),
                        child: RichText(
                          text: TextSpan(
                            children: _visibleSpans(spans),
                            style: NexusTypography.bodyMd,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<TextSpan> _visibleSpans(List<TextSpan> spans) {
    final hasVisible = spans.any(
      (s) => (s.text?.isNotEmpty ?? false) || (s.children?.isNotEmpty ?? false),
    );
    if (hasVisible) return spans;
    return [TextSpan(text: ' ', style: NexusTypography.bodyMd)];
  }
}

class _InlineDiff extends StatelessWidget {
  const _InlineDiff({required this.lines, required this.language});

  final List<_DiffLine> lines;
  final String language;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final prefix = switch (line.type) {
          _DiffType.equal => ' ',
          _DiffType.insert => '+',
          _DiffType.delete => '-',
          _DiffType.modify => '~',
        };
        final spans = switch (line.type) {
          _DiffType.delete => line.oldSpans,
          _DiffType.equal || _DiffType.insert => line.newSpans,
          _DiffType.modify => [
            ...line.oldSpans,
            TextSpan(text: ' → ', style: NexusTypography.bodyMd),
            ...line.newSpans,
          ],
        };

        final backgroundColor = switch (line.type) {
          _DiffType.equal => Colors.transparent,
          _DiffType.delete => NexusColors.errorContainer,
          _DiffType.insert => NexusColors.tertiaryContainer,
          _DiffType.modify => Colors.transparent,
        };

        final prefixColor = switch (line.type) {
          _DiffType.equal => NexusColors.onSurfaceVariant,
          _DiffType.delete => NexusColors.error,
          _DiffType.insert => NexusColors.tertiary,
          _DiffType.modify => NexusColors.primary,
        };

        return Container(
          color: backgroundColor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: NexusColors.surfaceContainerLow,
                  border: Border(
                    right: BorderSide(color: NexusColors.outlineVariant),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      prefix,
                      style: NexusTypography.bodyMd.copyWith(
                        color: prefixColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.sm),
                    Text(
                      _lineNumberText(line),
                      style: NexusTypography.labelSm.copyWith(
                        color: NexusColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.sm,
                    vertical: 2,
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: spans,
                      style: NexusTypography.bodyMd,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _lineNumberText(_DiffLine line) {
    if (line.oldLineNumber != null && line.newLineNumber != null) {
      return '${line.oldLineNumber}/${line.newLineNumber}';
    }
    return (line.oldLineNumber ?? line.newLineNumber ?? '').toString();
  }
}

class _IgnoreWhitespaceChip extends StatelessWidget {
  const _IgnoreWhitespaceChip({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? NexusColors.primaryContainer : Colors.transparent,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: NexusRadii.mdRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: NexusSpacing.xs,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: value ? NexusColors.primary : NexusColors.outlineVariant,
            ),
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value ? Icons.check_box : Icons.check_box_outline_blank,
                size: 18,
                color: value ? NexusColors.primary : NexusColors.onSurface,
              ),
              const SizedBox(width: NexusSpacing.xs),
              Text(
                'Ignore Whitespace',
                style: NexusTypography.bodyMd.copyWith(
                  color: value ? NexusColors.primary : NexusColors.onSurface,
                ),
              ),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLow,
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(color: NexusColors.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          items: languages
              .map((lang) => DropdownMenuItem(value: lang, child: Text(lang)))
              .toList(),
          onChanged: onChanged,
          style: NexusTypography.bodyMd,
          dropdownColor: NexusColors.surfaceContainerLowest,
        ),
      ),
    );
  }
}

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
    _SyntaxPattern(RegExp(r'#[^\n]*'), Colors.grey),
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
    _SyntaxPattern(RegExp(r'<!--[\s\S]*?-->'), Colors.grey),
    _SyntaxPattern(RegExp(r'<\?[^>]*\?>'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r'<[!/]?[\w-]+'), const Color(0xFF1565C0)),
    _SyntaxPattern(RegExp(r'\s[\w-]+(?==)'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), const Color(0xFF2E7D32)),
  ],
  'CSS': [
    _SyntaxPattern(RegExp(r'/\*[\s\S]*?\*/'), Colors.grey),
    _SyntaxPattern(RegExp(r'[.#]?[\w-]+\s*(?=\{)'), const Color(0xFF1565C0)),
    _SyntaxPattern(RegExp(r'\b[\w-]+(?=\s*:)'), const Color(0xFF7B1FA2)),
    _SyntaxPattern(RegExp(r':\s*[^;]+'), const Color(0xFF2E7D32)),
    _SyntaxPattern(RegExp(r'#[0-9a-fA-F]{3,8}'), const Color(0xFF1565C0)),
  ],
  'SQL': [
    _SyntaxPattern(RegExp(r'--[^\n]*|/\*[\s\S]*?\*/'), Colors.grey),
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
    _SyntaxPattern(RegExp(r'#[^\n]*'), Colors.grey),
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
    _SyntaxPattern(RegExp(r'//[^\n]*|/\*[\s\S]*?\*/'), Colors.grey),
    _SyntaxPattern(RegExp(r'"(?:\\.|[^"\\])*"'), stringColor),
    _SyntaxPattern(RegExp(r"'(?:\\.|[^'\\])*'"), stringColor),
    _SyntaxPattern(
      RegExp(
        r'\b(abstract|as|assert|async|await|break|case|catch|class|const|continue|default|do|else|enum|export|extends|external|factory|false|final|finally|for|Function|get|if|implements|import|in|interface|is|late|library|mixin|new|null|on|operator|override|part|private|protected|public|rethrow|return|set|static|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield|let|const|function|return|typeof|instanceof|undefined|true|false|null|class|extends|super|import|export|from|default|await|async|try|catch|finally|throw|new|delete|void|in|of|static|public|private|protected|final|abstract|interface|implements|extends|super|return|if|else|while|do|for|switch|case|break|continue|default|synchronized|volatile|transient|native|strictfp|goto|package|import|throws)\b',
      ),
      keywordColor,
    ),
    _SyntaxPattern(RegExp(r'\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b'), numberColor),
  ];
}
