import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';

class NexusIcon extends StatelessWidget {
  const NexusIcon({
    super.key,
    required this.icon,
    this.size = 20,
    this.color = NexusColors.onSurfaceVariant,
    this.backgroundColor,
  });

  final IconData icon;
  final double size;
  final Color color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: backgroundColor ?? NexusColors.surfaceContainer,
        borderRadius: NexusRadii.mdRadius,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size, color: color),
    );
  }
}
