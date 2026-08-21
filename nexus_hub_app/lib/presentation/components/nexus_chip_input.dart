import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

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

  @override
  void dispose() {
    _controller.dispose();
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
          Text(widget.labelText!, style: NexusTypography.labelMd),
          const SizedBox(height: NexusSpacing.xs),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...widget.values.map(
              (value) => _Chip(label: value, onDeleted: () => _removeChip(value)),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _controller,
                style: NexusTypography.bodyMd,
                hintText: widget.values.isEmpty ? widget.hintText : null,
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
          ],
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.secondary,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.secondaryForeground,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onDeleted,
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Icon(
                RadixIcons.cross2,
                size: 14,
                color: colorScheme.secondaryForeground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
