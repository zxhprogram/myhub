import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/typography.dart';

class NexusAvatar extends StatelessWidget {
  const NexusAvatar({super.key, this.size = 36, this.label, this.imageUrl});

  final double size;
  final String? label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback = label?.isNotEmpty == true ? label![0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: NexusRadii.fullRadius,
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      alignment: Alignment.center,
      child: imageUrl == null
          ? Text(
              fallback,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }
}
