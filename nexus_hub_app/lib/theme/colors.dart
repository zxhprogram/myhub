import 'package:flutter/widgets.dart';

/// Semantic module colors that live outside the theme color scheme.
///
/// Everything else is resolved from the shadcn color scheme via
/// `Theme.of(context).colorScheme`.
abstract final class NexusColors {
  /// Positive market movement.
  static const Color stockUp = Color(0xFF10B981);

  /// Negative market movement.
  static const Color stockDown = Color(0xFFEF4444);
}
