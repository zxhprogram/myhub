import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

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
  late QuillController _controller;
  final _focusNode = FocusNode();
  late final Future<bool> Function() _handleClipboardPaste;

  @override
  void initState() {
    super.initState();
    _handleClipboardPaste = () => _pasteImageFromClipboard();
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
    // ignore: experimental_member_use
    final config = QuillControllerConfig(
      // ignore: experimental_member_use
      clipboardConfig: QuillClipboardConfig(
        // ignore: experimental_member_use
        onClipboardPaste: widget.readOnly ? null : _handleClipboardPaste,
      ),
    );
    try {
      final json = deltaJson != null && deltaJson.isNotEmpty
          ? jsonDecode(deltaJson) as List<dynamic>
          : <dynamic>[];
      return QuillController(
        document: Document.fromJson(json),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: widget.readOnly,
        config: config,
      );
    } catch (_) {
      final text = deltaJson ?? '';
      return QuillController(
        document: Document.fromJson([
          {'insert': text.endsWith('\n') ? text : '$text\n'},
        ]),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: widget.readOnly,
        config: config,
      );
    }
  }

  Future<bool> _pasteImageFromClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;

    final reader = await clipboard.read();

    final formats = <(SimpleFileFormat, String)>[
      (Formats.png, 'image/png'),
      (Formats.jpeg, 'image/jpeg'),
      (Formats.gif, 'image/gif'),
      (Formats.webp, 'image/webp'),
      (Formats.bmp, 'image/bmp'),
    ];

    for (final (format, mimeType) in formats) {
      if (!reader.canProvide(format)) continue;
      final bytes = await _readClipboardImage(reader, format);
      if (bytes != null && bytes.isNotEmpty) {
        final base64 = base64Encode(bytes);
        final imageUrl = 'data:$mimeType;base64,$base64';
        final index = _controller.selection.start;
        _controller.replaceText(
          index,
          _controller.selection.end - index,
          BlockEmbed.image(imageUrl),
          const TextSelection.collapsed(offset: -1),
        );
        return true;
      }
    }

    return false;
  }

  Future<Uint8List?> _readClipboardImage(
    ClipboardReader reader,
    SimpleFileFormat format,
  ) async {
    final completer = Completer<Uint8List?>();
    reader.getFile(format, (file) async {
      try {
        final bytes = await file.readAll();
        completer.complete(bytes);
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
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
              config: QuillEditorConfig(
                padding: EdgeInsets.zero,
                embedBuilders: const [_ImageEmbedBuilder()],
                unknownEmbedBuilder: const _UnknownEmbedBuilder(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImageEmbedBuilder extends EmbedBuilder {
  const _ImageEmbedBuilder();

  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final source = embedContext.node.value.data as String?;
    if (source == null || source.isEmpty) {
      return _embedPlaceholder('No image source');
    }

    final Widget image;
    if (source.startsWith('data:image')) {
      final bytes = _decodeBase64Image(source);
      if (bytes == null) {
        return _embedPlaceholder('Invalid image data');
      }
      image = Image.memory(bytes, fit: BoxFit.contain);
    } else if (source.startsWith('http://') || source.startsWith('https://')) {
      image = Image.network(source, fit: BoxFit.contain);
    } else {
      final file = File(source);
      if (!file.existsSync()) {
        return _embedPlaceholder('Image not found');
      }
      image = Image.file(file, fit: BoxFit.contain);
    }

    return ClipRRect(
      borderRadius: NexusRadii.mdRadius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: image,
      ),
    );
  }

  Uint8List? _decodeBase64Image(String source) {
    final commaIndex = source.indexOf(',');
    if (commaIndex == -1) return null;
    try {
      return base64Decode(source.substring(commaIndex + 1));
    } on FormatException {
      return null;
    }
  }
}

class _UnknownEmbedBuilder extends EmbedBuilder {
  const _UnknownEmbedBuilder();

  @override
  String get key => 'unknown';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return _embedPlaceholder('Unsupported embed');
  }
}

Widget _embedPlaceholder(String message) {
  return Container(
    padding: const EdgeInsets.all(NexusSpacing.sm),
    decoration: BoxDecoration(
      color: NexusColors.surfaceContainer,
      borderRadius: NexusRadii.mdRadius,
      border: Border.all(color: NexusColors.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.image_not_supported_outlined,
          size: 16,
          color: NexusColors.onSurfaceVariant,
        ),
        const SizedBox(width: NexusSpacing.xs),
        Text(
          message,
          style: NexusTypography.labelSm.copyWith(
            color: NexusColors.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
