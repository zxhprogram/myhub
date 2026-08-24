import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/typography.dart';

/// Maximum number of characters allowed in a folder name.
const int kMaxFolderNameLength = 40;

/// macOS Finder style dialog for creating or renaming a desktop folder.
///
/// Provides desktop-grade interactions:
/// - Opens with the default name pre-filled and fully selected, so typing
///   replaces it immediately (Finder behaviour).
/// - Live validation: trims whitespace, blocks duplicates (case-insensitive),
///   enforces a maximum length, with inline feedback under the field.
/// - Enter confirms, Esc cancels; the confirm button reflects validity.
Future<String?> showDesktopFolderNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required Set<String> existingNames,
  String? initialName,
}) {
  return showOverlay<String>(
    context,
    DialogConfiguration<String>(
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
      builder: (ctx) => DesktopFolderNameDialog(
        title: title,
        confirmLabel: confirmLabel,
        initialName: initialName,
        existingNames: existingNames,
      ),
    ),
  ).future;
}

class DesktopFolderNameDialog extends StatefulWidget {
  const DesktopFolderNameDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.existingNames,
    this.initialName,
  });

  /// Dialog heading, e.g. 新建文件夹 / 重命名文件夹.
  final String title;

  /// Label of the confirming action, e.g. 创建 / 确认.
  final String confirmLabel;

  /// Name the field starts with (pre-selected so typing replaces it).
  final String? initialName;

  /// Existing folder names used for duplicate detection.
  final Set<String> existingNames;

  @override
  State<DesktopFolderNameDialog> createState() =>
      _DesktopFolderNameDialogState();
}

class _DesktopFolderNameDialogState extends State<DesktopFolderNameDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName ?? '');
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      // Select the whole default name so the first keystroke replaces it.
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  bool get _isDuplicate => widget.existingNames.contains(_name.toLowerCase());

  bool get _canSubmit => _name.isNotEmpty && !_isDuplicate;

  /// Returns the validation message to display, or null when the current
  /// input is acceptable. Empty input stays quiet (the button simply stays
  /// disabled) until the user has actually cleared the prefilled text.
  String? get _errorText {
    if (_controller.text.isNotEmpty && _name.isEmpty) {
      return '文件夹名称不能只有空白字符';
    }
    if (_isDuplicate) {
      return '已存在同名文件夹，请换一个名称';
    }
    return null;
  }

  void _submit(BuildContext overlayContext) {
    if (!_canSubmit) return;
    closeOverlay<String>(overlayContext, _name);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AlertDialog(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.folderPlus, size: 18),
            const SizedBox(width: 8),
            Text(widget.title),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFolderPreview(colorScheme),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: true,
                maxLength: kMaxFolderNameLength,
                hintText: '文件夹名称',
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(context),
              ),
              const SizedBox(height: 6),
              _buildFeedbackRow(),
            ],
          ),
        ),
        actions: [
          Button.text(
            onPressed: _cancel,
            child: const Text('取消'),
          ),
          Button.primary(
            onPressed: _canSubmit ? () => _submit(context) : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }

  void _cancel() {
    if (mounted) {
      closeOverlay<String>(context);
    }
  }

  /// Large folder glyph that previews the outcome: an outlined "add" folder
  /// while the name is invalid, a filled accent folder once it is usable.
  Widget _buildFolderPreview(ColorScheme colorScheme) {
    final valid = _canSubmit;
    final accent = valid ? colorScheme.primary : colorScheme.mutedForeground;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 84,
        height: 68,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: valid
                ? [
                    colorScheme.primary.withValues(alpha: 0.22),
                    colorScheme.primary.withValues(alpha: 0.08),
                  ]
                : [
                    colorScheme.muted.withValues(alpha: 0.6),
                    colorScheme.muted.withValues(alpha: 0.25),
                  ],
          ),
          border: Border.all(
            color: valid
                ? colorScheme.primary.withValues(alpha: 0.35)
                : colorScheme.border.withValues(alpha: 0.5),
          ),
        ),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              valid ? LucideIcons.folder : LucideIcons.folderPlus,
              key: ValueKey(valid),
              size: 34,
              color: accent,
            ),
          ),
        ),
      ),
    );
  }

  /// Inline validation message or a character counter near the limit.
  Widget _buildFeedbackRow() {
    final colorScheme = Theme.of(context).colorScheme;
    final error = _errorText;
    if (error != null) {
      return Row(
        children: [
          Icon(LucideIcons.circleAlert,
              size: 14, color: colorScheme.destructive),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              style: TextStyle(fontSize: 12, color: colorScheme.destructive),
            ),
          ),
        ],
      );
    }
    final length = _controller.text.length;
    if (length >= kMaxFolderNameLength - 10) {
      return Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$length/$kMaxFolderNameLength',
          style: NexusTypography.labelSm.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }
    // Keep vertical layout stable when neither message is shown.
    return const SizedBox(height: 16);
  }
}
