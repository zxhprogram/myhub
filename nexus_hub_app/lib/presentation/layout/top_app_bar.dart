import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';

class TopAppBar extends StatelessWidget implements PreferredSizeWidget {
  const TopAppBar({super.key, this.title});

  final Widget? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      decoration: BoxDecoration(
        color: NexusColors.background,
        border: Border(
          bottom: BorderSide(
            color: NexusColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (title != null) Expanded(child: title!),
          if (title == null) const Spacer(),
          _ActionButton(icon: Icons.search, onTap: () {}),
          const SizedBox(width: NexusSpacing.sm),
          _ActionButton(icon: Icons.notifications_outlined, onTap: () {}),
          const SizedBox(width: NexusSpacing.sm),
          _ActionButton(icon: Icons.help_outline, onTap: () {}),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64);
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        hoverColor: NexusColors.surfaceContainerHigh.withValues(alpha: 0.5),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: NexusColors.onSurfaceVariant),
        ),
      ),
    );
  }
}
