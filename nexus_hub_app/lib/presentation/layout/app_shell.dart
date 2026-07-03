import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/colors.dart';
import 'side_navigation.dart';
import 'top_app_bar.dart';

/// Adaptive shell: sidebar on desktop, bottom nav on mobile.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = width >= 900;

    return Scaffold(
      body: isDesktop
          ? Row(
              children: [
                SideNavigation(currentPath: currentPath),
                Expanded(
                  child: Column(
                    children: [
                      const TopAppBar(),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                const TopAppBar(),
                Expanded(child: child),
              ],
            ),
      bottomNavigationBar: isDesktop
          ? null
          : _BottomNavBar(currentPath: currentPath),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: NexusColors.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: Icons.dashboard_outlined,
                label: 'Home',
                path: '/',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: Icons.check_circle_outline,
                label: 'Tasks',
                path: '/tasks',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: Icons.chat_bubble_outline,
                label: 'AI',
                path: '/ai-chat',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: Icons.mail_outlined,
                label: 'Mail',
                path: '/mail',
                currentPath: currentPath,
              ),
              _BottomNavItem(
                icon: Icons.menu,
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
    final color = isActive ? NexusColors.primary : NexusColors.onSurfaceVariant;
    return InkWell(
      onTap: () => context.go(path),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}
