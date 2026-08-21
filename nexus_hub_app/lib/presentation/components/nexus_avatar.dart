import 'package:shadcn_flutter/shadcn_flutter.dart';

class NexusAvatar extends StatelessWidget {
  const NexusAvatar({super.key, this.size = 36, this.label, this.imageUrl});

  final double size;
  final String? label;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallback =
        label?.isNotEmpty == true ? label![0].toUpperCase() : '?';

    return Avatar(
      initials: fallback,
      size: size,
      provider: imageUrl != null ? NetworkImage(imageUrl!) : null,
      backgroundColor: colorScheme.primary,
    );
  }
}
