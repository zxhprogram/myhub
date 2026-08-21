import 'package:shadcn_flutter/shadcn_flutter.dart';

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
    final effectiveColor = color ?? colorScheme.primary;

    final background = selected
        ? effectiveColor.withValues(alpha: 0.15)
        : effectiveColor.withValues(alpha: 0.08);
    final foreground = effectiveColor;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: NexusRadii.fullRadius,
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
                child: Icon(RadixIcons.cross2, size: 14, color: foreground),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
