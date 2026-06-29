import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Surface container card with optional interactivity.
class NexusCard extends StatelessWidget {
  const NexusCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(NexusSpacing.md),
    this.borderRadius = NexusRadii.md,
    this.onTap,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: NexusColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        hoverColor: NexusColors.surfaceContainerLow.withValues(alpha: 0.3),
        child: card,
      ),
    );
  }
}
