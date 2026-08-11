import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class NexusChip extends StatelessWidget {
  const NexusChip({
    super.key,
    required this.label,
    this.color,
    this.selected = false,
    this.onTap,
    this.onDeleted,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.secondary;

    final background = selected
        ? effectiveColor.withValues(alpha: 0.15)
        : effectiveColor.withValues(alpha: 0.08);
    final foreground = effectiveColor;

    return Material(
      color: background,
      borderRadius: NexusRadii.fullRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.fullRadius,
        hoverColor: effectiveColor.withValues(alpha: 0.12),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: NexusTypography.labelMd.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (onDeleted != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDeleted,
                  child: Icon(Icons.close, size: 14, color: foreground),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
