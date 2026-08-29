import 'package:flutter/widgets.dart';

/// Imperative page route used instead of MaterialPageRoute: a short
/// fade-through transition that matches the shadcn desktop shell without
/// pulling in any Material components.
class NexusPageRoute<T> extends PageRouteBuilder<T> {
  NexusPageRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 150),
          pageBuilder: (_, __, ___) => Builder(builder: builder),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          ),
        );
}
