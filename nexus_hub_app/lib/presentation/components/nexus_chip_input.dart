import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// A chip-based tag input. The user types text and presses Enter or comma
/// to add it as a removable chip.
class NexusChipInput extends StatefulWidget {
  const NexusChipInput({
    super.key,
    this.labelText,
    this.hintText = 'Type and press Enter…',
    this.values = const [],
    this.onChanged,
  });

  final String? labelText;
  final String? hintText;
  final List<String> values;
  final ValueChanged<List<String>>? onChanged;

  @override
  State<NexusChipInput> createState() => _NexusChipInputState();
}

class _NexusChipInputState extends State<NexusChipInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addChip() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (widget.values.contains(text)) {
      _controller.clear();
      return;
    }
    widget.onChanged?.call([...widget.values, text]);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _removeChip(String value) {
    widget.onChanged?.call(widget.values.where((v) => v != value).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(
            widget.labelText!,
            style: NexusTypography.labelMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: NexusSpacing.xs),
        ],
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: NexusColors.surfaceContainerLowest,
            borderRadius: NexusRadii.mdRadius,
            border: Border.all(color: NexusColors.outline),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...widget.values.map(
                (value) =>
                    _Chip(label: value, onDeleted: () => _removeChip(value)),
              ),
              SizedBox(
                width: 120,
                child: KeyboardListener(
                  focusNode: _focusNode,
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter) {
                      _addChip();
                    }
                  },
                  child: TextField(
                    controller: _controller,
                    style: NexusTypography.bodyMd,
                    decoration: InputDecoration(
                      hintText: widget.values.isEmpty ? widget.hintText : '',
                      hintStyle: NexusTypography.bodyMd.copyWith(
                        color: NexusColors.onSurfaceVariant,
                      ),
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: (_) => _addChip(),
                    onChanged: (value) {
                      if (value.endsWith(',')) {
                        _controller.text = value.substring(0, value.length - 1);
                        _controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: _controller.text.length),
                        );
                        _addChip();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NexusColors.secondaryContainer,
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: NexusTypography.labelMd.copyWith(
              color: NexusColors.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Icon(
                Icons.close,
                size: 14,
                color: NexusColors.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
