import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/radii.dart';

enum NexusIconSize { small, medium, large }

class NexusIcon extends StatelessWidget {
  const NexusIcon({
    super.key,
    required this.icon,
    this.size = NexusIconSize.medium,
    this.color,
    this.backgroundColor,
    this.active = false,
  });

  final IconData icon;
  final NexusIconSize size;
  final Color? color;
  final Color? backgroundColor;
  final bool active;

  double get _size => switch (size) {
        NexusIconSize.small => 16,
        NexusIconSize.medium => 20,
        NexusIconSize.large => 24,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ??
        (active ? colorScheme.foreground : colorScheme.mutedForeground);

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.muted,
        borderRadius: NexusRadii.mdRadius,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: _size, color: effectiveColor),
    );
  }
}
