import 'package:go_router/go_router.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'desktop_environment.dart';
import 'top_app_bar.dart';

/// Adaptive shell: macOS desktop environment on desktop, bottom nav on mobile.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;

    if (isDesktop) {
      return const DesktopEnvironment();
    }

    // Mobile layout: keep the existing bottom navigation bar
    return Column(
      children: [
        const TopAppBar(),
        Expanded(child: child),
        _BottomNavBar(currentPath: currentPath),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border(top: BorderSide(color: colorScheme.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: RadixIcons.dashboard,
                label: 'Home',
                path: '/',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: LucideIcons.circleCheck,
                label: 'Tasks',
                path: '/tasks',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: RadixIcons.chatBubble,
                label: 'AI',
                path: '/ai-chat',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: LucideIcons.mail,
                label: 'Mail',
                path: '/mail',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: LucideIcons.menu,
                label: 'More',
                path: '/bookmarks',
                currentPath: currentPath,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.path,
    required this.currentPath,
  });

  final IconData icon;
  final String label;
  final String path;
  final String currentPath;

  bool get isActive =>
      path == '/' ? currentPath == '/' : currentPath.startsWith(path);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        isActive ? colorScheme.foreground : colorScheme.mutedForeground;

    return GestureDetector(
      onTap: () => context.go(path),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
