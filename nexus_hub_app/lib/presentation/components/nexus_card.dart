import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../theme/density.dart';

/// Surface container card with optional interactivity.
///
/// Padding and radius default to the current density mode
/// (see [NexusDensityController]); explicit values still win.
class NexusCard extends StatelessWidget {
  const NexusCard({
    super.key,
    this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.highlight = false,
  });

  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final colorScheme = Theme.of(context).colorScheme;

      final card = Card(
        padding: padding ?? EdgeInsets.all(NexusDensityController.cardPadding),
        borderRadius:
            BorderRadius.circular(borderRadius ?? NexusDensityController.cardRadius),
        fillColor: highlight
            ? colorScheme.primary.withValues(alpha: 0.06)
            : colorScheme.card,
        borderColor: highlight
            ? colorScheme.primary.withValues(alpha: 0.7)
            : colorScheme.border,
        borderWidth: highlight ? 1.5 : 1,
        child: child ?? const SizedBox.shrink(),
      );

      if (onTap == null) return card;

      return GestureDetector(onTap: onTap, child: card);
    });
  }
}
