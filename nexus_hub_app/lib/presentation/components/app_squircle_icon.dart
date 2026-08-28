import 'package:shadcn_flutter/shadcn_flutter.dart';

/// macOS Big Sur style squircle — a heavily rounded square filled with a
/// diagonal gradient that mimics the vibrant pastel app icons of recent
/// macOS. Shared by desktop icons, dock icons and folder previews.
class AppSquircleIcon extends StatelessWidget {
  const AppSquircleIcon({
    super.key,
    required this.gradientStart,
    required this.gradientEnd,
    this.child,
    this.size = 48,
  });

  /// Top color of the macOS-style squircle gradient.
  final Color gradientStart;

  /// Bottom color of the macOS-style squircle gradient.
  final Color gradientEnd;

  final Widget? child;

  final double size;

  @override
  Widget build(BuildContext context) {
    // macOS icons are rounded ~22.3% (approximately 4:1 of 60pt squircle).
    final radius = size * 0.23;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFFFFFFFF).withValues(alpha: 0.4),
                    const Color(0xFFFFFFFF).withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.45],
                ),
              ),
            ),
            if (child != null)
              Center(
                child: IconTheme(
                  data: const IconThemeData(
                    color: Color(0xFFFFFFFF),
                  ),
                  child: child!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
