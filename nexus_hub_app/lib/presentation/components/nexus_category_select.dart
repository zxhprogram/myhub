import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// An editable category selector. The user can either pick an existing
/// category from the dropdown or type a new one — pressing Enter or
/// clicking "Create" adds it inline.
///
/// Unlike a true Overlay menu, the options list renders inline below the
/// text field so it never escapes a parent dialog.
class NexusCategorySelect extends StatefulWidget {
  const NexusCategorySelect({
    super.key,
    this.labelText,
    required this.categories,
    this.initialValue,
    required this.onChanged,
  });

  final String? labelText;
  final List<String> categories;
  final String? initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<NexusCategorySelect> createState() => _NexusCategorySelectState();
}

class _NexusCategorySelectState extends State<NexusCategorySelect> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant NexusCategorySelect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != null &&
        _controller.text != widget.initialValue) {
      _controller.text = widget.initialValue!;
    }
  }

  void _onFocusChanged() {
    setState(() => _expanded = _focusNode.hasFocus);
  }

  void _select(String value) {
    _controller.text = value;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: value.length),
    );
    widget.onChanged(value);
    _focusNode.unfocus();
  }

  List<String> get _filtered {
    final query = _controller.text.toLowerCase().trim();
    return widget.categories
        .where((c) => c.toLowerCase().contains(query))
        .toList();
  }

  bool get _canCreate {
    final query = _controller.text.trim();
    return query.isNotEmpty &&
        !widget.categories.any((c) => c.toLowerCase() == query.toLowerCase());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final canCreate = _canCreate;
    final hasOptions = filtered.isNotEmpty || canCreate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.labelText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
            child: Text(
              widget.labelText!,
              style: NexusTypography.labelMd.copyWith(
                color: NexusColors.onSurface,
              ),
            ),
          ),
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: NexusTypography.bodyMd,
          decoration: InputDecoration(
            hintText: 'Select or type a new category',
            hintStyle: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
            filled: true,
            fillColor: NexusColors.surfaceContainerLow,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
              vertical: NexusSpacing.sm,
            ),
            border: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: NexusRadii.mdRadius,
              borderSide: const BorderSide(color: NexusColors.outline),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                color: NexusColors.onSurfaceVariant,
              ),
              onPressed: () {
                if (_expanded) {
                  _focusNode.unfocus();
                } else {
                  _focusNode.requestFocus();
                }
              },
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) _select(trimmed);
          },
        ),
        if (_expanded && hasOptions)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainerLowest,
              borderRadius: NexusRadii.mdRadius,
              border: Border.all(
                color: NexusColors.outlineVariant.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: NexusColors.onSurface.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: filtered.isEmpty && !canCreate
                  ? Padding(
                      padding: const EdgeInsets.all(NexusSpacing.md),
                      child: Text(
                        'No categories yet — type to create one.',
                        style: NexusTypography.bodyMd.copyWith(
                          color: NexusColors.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [
                        ...filtered.map(
                          (c) => _OptionTile(label: c, onTap: () => _select(c)),
                        ),
                        if (canCreate) ...[
                          if (filtered.isNotEmpty)
                            const Divider(height: 1, indent: 8, endIndent: 8),
                          _OptionTile(
                            label: 'Create "${_controller.text.trim()}"',
                            icon: Icons.add_circle_outline,
                            highlighted: true,
                            onTap: () => _select(_controller.text.trim()),
                          ),
                        ],
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.onTap,
    this.icon,
    this.highlighted = false,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: NexusRadii.smRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm + 2,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: highlighted
                    ? NexusColors.primary
                    : NexusColors.onSurfaceVariant,
              ),
              const SizedBox(width: NexusSpacing.sm),
            ],
            Expanded(
              child: Text(
                label,
                style: NexusTypography.bodyMd.copyWith(
                  color: highlighted ? NexusColors.primary : null,
                  fontWeight: highlighted ? FontWeight.w500 : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
