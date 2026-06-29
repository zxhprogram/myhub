import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class NexusChip extends StatelessWidget {
  const NexusChip({
    super.key,
    required this.label,
    this.color = NexusColors.secondary,
    this.onDeleted,
  });

  final String label;
  final Color color;
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: NexusRadii.mdRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: NexusTypography.labelMd.copyWith(color: color)),
          if (onDeleted != null)
            GestureDetector(
              onTap: onDeleted,
              child: Icon(Icons.close, size: 14, color: color),
            ),
        ],
      ),
    );
  }
}
