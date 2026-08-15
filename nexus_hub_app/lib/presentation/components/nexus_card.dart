import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';

/// Surface container card with optional interactivity.
class NexusCard extends StatelessWidget {
  const NexusCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(NexusSpacing.md),
    this.borderRadius = NexusRadii.xl,
    this.onTap,
    this.highlight = false,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: highlight
            ? colorScheme.primary.withValues(alpha: 0.06)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: highlight
              ? colorScheme.primary.withValues(alpha: 0.7)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
        hoverColor: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        child: card,
      ),
    );
  }
}
