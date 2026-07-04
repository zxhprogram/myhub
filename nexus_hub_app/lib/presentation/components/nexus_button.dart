import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

enum NexusButtonVariant { filled, tonal, outlined, text }

class NexusButton extends StatelessWidget {
  const NexusButton({
    super.key,
    required this.label,
    this.variant = NexusButtonVariant.filled,
    this.icon,
    this.isLoading = false,
    this.onPressed,
  });

  final String label;
  final NexusButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = switch (variant) {
      NexusButtonVariant.filled => NexusColors.onPrimary,
      NexusButtonVariant.tonal => NexusColors.onSecondaryContainer,
      NexusButtonVariant.outlined ||
      NexusButtonVariant.text => NexusColors.primary,
    };

    final backgroundColor = switch (variant) {
      NexusButtonVariant.filled => NexusColors.primary,
      NexusButtonVariant.tonal => NexusColors.secondaryContainer,
      NexusButtonVariant.outlined ||
      NexusButtonVariant.text => Colors.transparent,
    };

    final border = variant == NexusButtonVariant.outlined
        ? Border.all(color: NexusColors.outlineVariant)
        : null;

    return Material(
      color: backgroundColor,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: NexusRadii.mdRadius,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.md,
            vertical: NexusSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: border,
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 18, color: foregroundColor),
              if ((isLoading || icon != null) && label.isNotEmpty)
                const SizedBox(width: NexusSpacing.sm),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: NexusTypography.labelMd.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
