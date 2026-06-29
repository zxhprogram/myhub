import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
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
    final bg = backgroundColor ?? NexusColors.surfaceContainerHigh;
    final fg = foregroundColor ?? NexusColors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(NexusRadii.full),
        border: Border.all(color: fg.withValues(alpha: 0.1)),
      ),
      child: Text(label, style: NexusTypography.labelSm.copyWith(color: fg)),
    );
  }
}
