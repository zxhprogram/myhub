import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_avatar.dart';

class SideNavigation extends StatelessWidget {
  const SideNavigation({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: NexusSpacing.sidebarWidth,
      color: NexusColors.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NavGroup(
                    title: 'Overview',
                    items: [
                      _NavItem(
                        label: 'Dashboard',
                        icon: Icons.dashboard_outlined,
                        path: '/',
                        currentPath: currentPath,
                      ),
                    ],
                  ),
                  _NavGroup(
                    title: 'Productivity',
                    items: [
                      _NavItem(
                        label: 'Bookmarks',
                        icon: Icons.bookmark_outline,
                        path: '/bookmarks',
                        currentPath: currentPath,
                      ),
                      _NavItem(
                        label: 'Tasks',
                        icon: Icons.check_circle_outline,
                        path: '/tasks',
                        currentPath: currentPath,
                      ),
                      _NavItem(
                        label: 'Clipboard',
                        icon: Icons.content_paste,
                        path: '/clipboard',
                        currentPath: currentPath,
                      ),
                      _NavItem(
                        label: 'RSS Reader',
                        icon: Icons.rss_feed,
                        path: '/rss',
                        currentPath: currentPath,
                      ),
                      _NavItem(
                        label: 'Mail',
                        icon: Icons.mail_outlined,
                        path: '/mail',
                        currentPath: currentPath,
                      ),
                    ],
                  ),
                  _NavGroup(
                    title: 'AI & Data',
                    items: [
                      _NavItem(
                        label: 'AI Chat',
                        icon: Icons.chat_bubble_outline,
                        path: '/ai-chat',
                        currentPath: currentPath,
                      ),
                      _NavItem(
                        label: 'Stocks',
                        icon: Icons.show_chart,
                        path: '/stocks',
                        currentPath: currentPath,
                      ),
                      _NavItem(
                        label: 'My Computer',
                        icon: Icons.computer,
                        path: '/my-computer',
                        currentPath: currentPath,
                      ),
                    ],
                  ),
                  _NavGroup(
                    title: 'Developer',
                    items: [
                      _NavItem(
                        label: 'DevTools',
                        icon: Icons.construction,
                        path: '/dev-tools',
                        currentPath: currentPath,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: NexusColors.primary,
              borderRadius: NexusRadii.mdRadius,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.hub,
              color: NexusColors.onPrimary,
              size: 20,
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Text(
            'Nexus Hub',
            style: NexusTypography.headlineSm.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.all(NexusSpacing.md),
      child: Row(
        children: [
          const NexusAvatar(label: 'User'),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current User',
                  style: NexusTypography.labelMd.copyWith(
                    color: NexusColors.onSurface,
                  ),
                ),
                Text('user@nexus.dev', style: NexusTypography.labelSm),
              ],
            ),
          ),
          InkWell(
            onTap: () {},
            borderRadius: NexusRadii.mdRadius,
            hoverColor: NexusColors.surfaceContainerHigh.withValues(alpha: 0.5),
            child: const Padding(
              padding: EdgeInsets.all(NexusSpacing.sm),
              child: Icon(
                Icons.settings_outlined,
                size: 20,
                color: NexusColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavGroup extends StatelessWidget {
  const _NavGroup({required this.title, required this.items});

  final String title;
  final List<_NavItem> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: NexusSpacing.sm,
              bottom: NexusSpacing.xs,
            ),
            child: Text(title.toUpperCase(), style: NexusTypography.labelSm),
          ),
          ...items,
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.path,
    required this.currentPath,
  });

  final String label;
  final IconData icon;
  final String path;
  final String currentPath;

  bool get isActive {
    if (path == '/') return currentPath == '/';
    return currentPath.startsWith(path);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isActive
            ? NexusColors.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: NexusRadii.mdRadius,
        child: InkWell(
          onTap: () => context.go(path),
          borderRadius: NexusRadii.mdRadius,
          hoverColor: isActive
              ? null
              : NexusColors.surfaceContainerHigh.withValues(alpha: 0.5),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.sm,
              vertical: 10,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? NexusColors.onSurface
                      : NexusColors.onSurfaceVariant,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Text(
                  label,
                  style: NexusTypography.bodyMd.copyWith(
                    color: isActive
                        ? NexusColors.onSurface
                        : NexusColors.onSurfaceVariant,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
