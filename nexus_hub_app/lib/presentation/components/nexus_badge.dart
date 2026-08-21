import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class NexusBadge extends StatelessWidget {
  const NexusBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (backgroundColor == null && foregroundColor == null) {
      return SecondaryBadge(child: Text(label));
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.muted,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: colorScheme.border.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: NexusTypography.labelSm.copyWith(
          color: foregroundColor ?? colorScheme.mutedForeground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
