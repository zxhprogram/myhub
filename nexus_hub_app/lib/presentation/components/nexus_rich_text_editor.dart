import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Reusable rich text editor backed by flutter_quill.
///
/// [initialDeltaJson] is a serialized Quill Delta JSON object.
/// [onChanged] is called with the updated Delta JSON string whenever the
/// document changes.
class NexusRichTextEditor extends StatefulWidget {
  const NexusRichTextEditor({
    super.key,
    this.initialDeltaJson,
    required this.onChanged,
    this.readOnly = false,
  });

  final String? initialDeltaJson;
  final ValueChanged<String> onChanged;
  final bool readOnly;

  @override
  State<NexusRichTextEditor> createState() => _NexusRichTextEditorState();
}

class _NexusRichTextEditorState extends State<NexusRichTextEditor> {
  late final QuillController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.initialDeltaJson);
    _controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant NexusRichTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final readOnlyChanged = oldWidget.readOnly != widget.readOnly;
    final deltaChanged =
        oldWidget.initialDeltaJson != widget.initialDeltaJson &&
        widget.initialDeltaJson != null &&
        _deltaJson(_controller.document) != widget.initialDeltaJson;
    if (readOnlyChanged || deltaChanged) {
      _controller.removeListener(_onChanged);
      _controller.dispose();
      _controller = _createController(widget.initialDeltaJson);
      _controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  QuillController _createController(String? deltaJson) {
    try {
      final json = deltaJson != null && deltaJson.isNotEmpty
          ? jsonDecode(deltaJson) as List<dynamic>
          : <dynamic>[];
      return QuillController(
        document: Document.fromJson(json),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: widget.readOnly,
      );
    } catch (_) {
      return QuillController(
        document: Document(),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: widget.readOnly,
      );
    }
  }

  String _deltaJson(Document document) {
    return jsonEncode(document.toDelta().toJson());
  }

  void _onChanged() {
    widget.onChanged(_deltaJson(_controller.document));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.readOnly)
          Container(
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainer,
              borderRadius: NexusRadii.mdRadius,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.sm,
              vertical: NexusSpacing.xs,
            ),
            child: QuillSimpleToolbar(
              controller: _controller,
              config: const QuillSimpleToolbarConfig(
                showBoldButton: true,
                showItalicButton: true,
                showUnderLineButton: true,
                showListBullets: true,
                showListNumbers: true,
                showLink: true,
                showFontFamily: false,
                showFontSize: false,
                showStrikeThrough: false,
                showInlineCode: false,
                showColorButton: false,
                showBackgroundColorButton: false,
                showClearFormat: false,
                showHeaderStyle: false,
                showListCheck: false,
                showCodeBlock: false,
                showQuote: false,
                showIndent: false,
                showUndo: false,
                showRedo: false,
                showSearchButton: false,
                showSubscript: false,
                showSuperscript: false,
                showAlignmentButtons: false,
                showDirection: false,
              ),
            ),
          ),
        if (!widget.readOnly) const SizedBox(height: NexusSpacing.sm),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainerLowest,
              border: Border.all(color: NexusColors.outlineVariant),
              borderRadius: NexusRadii.mdRadius,
            ),
            padding: const EdgeInsets.all(NexusSpacing.sm),
            child: QuillEditor(
              controller: _controller,
              focusNode: _focusNode,
              scrollController: ScrollController(),
              config: const QuillEditorConfig(padding: EdgeInsets.zero),
            ),
          ),
        ),
      ],
    );
  }
}
