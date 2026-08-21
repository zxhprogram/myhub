import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/spacing.dart';

class TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TopAppBar({super.key, this.title});

  final Widget? title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.background,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.border.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (title != null) Expanded(child: title!),
          if (title == null) const Spacer(),
          IconButton.ghost(icon: Icon(RadixIcons.magnifyingGlass, size: 18)),
          const SizedBox(width: NexusSpacing.sm),
          IconButton.ghost(icon: Icon(LucideIcons.bell, size: 18)),
          const SizedBox(width: NexusSpacing.sm),
          IconButton.ghost(icon: Icon(LucideIcons.circleHelp, size: 18)),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}
