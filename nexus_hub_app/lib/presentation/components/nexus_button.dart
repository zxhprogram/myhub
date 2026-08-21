import 'package:shadcn_flutter/shadcn_flutter.dart';

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
    final leading = isLoading
        ? const CircularProgressIndicator(size: 16)
        : (icon != null ? Icon(icon, size: 16) : null);

    final child = label.isEmpty ? const SizedBox.shrink() : Text(label);

    return switch (variant) {
      NexusButtonVariant.filled => Button.primary(
          onPressed: isLoading ? null : onPressed,
          leading: leading,
          child: child,
        ),
      NexusButtonVariant.tonal => Button.secondary(
          onPressed: isLoading ? null : onPressed,
          leading: leading,
          child: child,
        ),
      NexusButtonVariant.outlined => Button.outline(
          onPressed: isLoading ? null : onPressed,
          leading: leading,
          child: child,
        ),
      NexusButtonVariant.text => Button.text(
          onPressed: isLoading ? null : onPressed,
          leading: leading,
          child: child,
        ),
    };
  }
}
