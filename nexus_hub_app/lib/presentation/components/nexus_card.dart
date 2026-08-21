import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Surface container card with optional interactivity.
class NexusCard extends StatelessWidget {
  const NexusCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 16,
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

    final card = Card(
      padding: padding,
      borderRadius: BorderRadius.circular(borderRadius),
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
  }
}
