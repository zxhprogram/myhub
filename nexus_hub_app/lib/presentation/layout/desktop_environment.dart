import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'package:signals_flutter/signals_flutter.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/wallpaper_picker_dialog.dart';
import '../pages/ai_chat_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/clipboard_history_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/dev_tools_page.dart';
import '../pages/mail_page.dart';
import '../pages/my_computer_page.dart';
import '../pages/rss_reader_page.dart';
import '../pages/stocks_page.dart';
import '../pages/tasks_page.dart';
import '../states/wallpaper_state.dart';

/// Navigation item descriptor for the desktop environment.
class _DesktopAppItem {
  final String label;
  final IconData icon;
  final String route;
  final WidgetBuilder pageBuilder;

  const _DesktopAppItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.pageBuilder,
  });
}

/// macOS-style desktop environment with a window manager.
///
/// Replaces the traditional sidebar navigation with a desktop metaphor:
/// application icons on the desktop that open into resizable, draggable
/// windows managed by the shadcn_flutter window system.
class DesktopEnvironment extends StatefulWidget {
  const DesktopEnvironment({super.key});

  @override
  State<DesktopEnvironment> createState() => _DesktopEnvironmentState();
}

class _DesktopEnvironmentState extends State<DesktopEnvironment> {
  /// All available applications shown as desktop icons.
  static final List<_DesktopAppItem> _appItems = [
    _DesktopAppItem(
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      route: '/',
      pageBuilder: (_) => const DashboardPage(),
    ),
    _DesktopAppItem(
      label: 'Bookmarks',
      icon: Icons.bookmark_outline,
      route: '/bookmarks',
      pageBuilder: (_) => const BookmarksPage(),
    ),
    _DesktopAppItem(
      label: 'Tasks',
      icon: Icons.check_circle_outline,
      route: '/tasks',
      pageBuilder: (_) => const TasksPage(),
    ),
    _DesktopAppItem(
      label: 'Clipboard',
      icon: Icons.content_paste,
      route: '/clipboard',
      pageBuilder: (_) => const ClipboardHistoryPage(),
    ),
    _DesktopAppItem(
      label: 'RSS Reader',
      icon: Icons.rss_feed,
      route: '/rss',
      pageBuilder: (_) => const RssReaderPage(),
    ),
    _DesktopAppItem(
      label: 'Mail',
      icon: Icons.mail_outlined,
      route: '/mail',
      pageBuilder: (_) => const MailPage(),
    ),
    _DesktopAppItem(
      label: 'AI Chat',
      icon: Icons.chat_bubble_outline,
      route: '/ai-chat',
      pageBuilder: (_) => const AiChatPage(),
    ),
    _DesktopAppItem(
      label: 'Stocks',
      icon: Icons.show_chart,
      route: '/stocks',
      pageBuilder: (_) => const StocksPage(),
    ),
    _DesktopAppItem(
      label: 'My Computer',
      icon: Icons.computer,
      route: '/my-computer',
      pageBuilder: (_) => const MyComputerPage(),
    ),
    _DesktopAppItem(
      label: 'DevTools',
      icon: Icons.construction,
      route: '/dev-tools',
      pageBuilder: (_) => const DevToolsPage(),
    ),
  ];

  /// Key to access the [WindowNavigatorHandle] for adding/removing windows.
  final GlobalKey _navigatorKey = GlobalKey();

  /// Map of open windows by route path, with their controllers.
  final Map<String, _WindowEntry> _openWindows = {};

  int _windowCounter = 0;

  @override
  void initState() {
    super.initState();
    // Load the persisted wallpaper and fetch the network wallpaper list.
    WallpaperState.instance.init();
  }

  @override
  void dispose() {
    for (final entry in _openWindows.values) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  shadcn.WindowNavigatorHandle? get _navigatorHandle {
    final state = _navigatorKey.currentState;
    if (state is shadcn.WindowNavigatorHandle) {
      return state;
    }
    return null;
  }

  void _openAppWindow(_DesktopAppItem appItem) {
    // If window already open, focus it instead of creating a new one
    if (_openWindows.containsKey(appItem.route)) {
      final entry = _openWindows[appItem.route]!;
      _navigatorHandle?.focusWindow(entry.window);
      if (entry.controller.minimized) {
        entry.controller.minimized = false;
      }
      return;
    }

    final controller = shadcn.WindowController(
      bounds: Rect.fromLTWH(
        60 + (_windowCounter % 5) * 40,
        40 + (_windowCounter % 5) * 40,
        900,
        600,
      ),
      resizable: true,
      draggable: true,
      closable: true,
      maximizable: true,
      minimizable: true,
      constraints: const BoxConstraints(
        minWidth: 400,
        minHeight: 300,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
      ),
    );
    _windowCounter++;

    final window = shadcn.Window.controlled(
      controller: controller,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(appItem.icon, size: 16, color: NexusColors.onSurface),
          const SizedBox(width: 8),
          Text(
            appItem.label,
            style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: ClipRect(child: appItem.pageBuilder(context)),
    );

    // Track window close to remove from our map
    window.closed.addListener(() {
      if (window.closed.value && _openWindows.containsKey(appItem.route)) {
        setState(() {
          _openWindows.remove(appItem.route);
        });
      }
    });

    // Listen for controller disposal (when window is fully removed)
    controller.addListener(() {
      if (!controller.mounted && _openWindows.containsKey(appItem.route)) {
        setState(() {
          _openWindows.remove(appItem.route);
        });
      }
    });

    setState(() {
      _openWindows[appItem.route] = _WindowEntry(
        window: window,
        controller: controller,
        appItem: appItem,
      );
    });

    // Add window to the navigator
    _navigatorHandle?.pushWindow(window);
  }

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    return shadcn.ShadcnLayer(
      theme: const shadcn.ThemeData(radius: 0.5, scaling: 1),
      child: Theme(
        data: materialTheme,
        child: Material(
          type: MaterialType.transparency,
          child: shadcn.WindowNavigator(
            key: _navigatorKey,
            initialWindows: const [],
            child: _buildDesktop(context),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return Watch((_) {
      final wallpaper = WallpaperState.instance.currentWallpaper.value;
      return shadcn.ContextMenu(
        items: [
          shadcn.MenuButton(
            leading: const Icon(Icons.wallpaper, size: 16),
            onPressed: (context) => WallpaperPickerDialog.show(context),
            child: const Text('更换壁纸'),
          ),
          if (wallpaper != null) ...[
            const shadcn.MenuDivider(),
            shadcn.MenuButton(
              leading: const Icon(Icons.restart_alt, size: 16),
              onPressed: (context) => WallpaperState.instance.clearWallpaper(),
              child: const Text('恢复默认壁纸'),
            ),
          ],
        ],
        child: Stack(
          children: [
            // Desktop background
            _buildBackground(),
            // Desktop icons area
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: NexusSpacing.lg,
                  top: NexusSpacing.lg,
                  bottom: 100,
                ),
                child: _buildDesktopIcons(context),
              ),
            ),
            // Dock at bottom
            Positioned(bottom: 8, left: 0, right: 0, child: _buildDock(context)),
          ],
        ),
      );
    });
  }

  Widget _buildBackground() {
    return Watch((_) {
      final wallpaper = WallpaperState.instance.currentWallpaper.value;
      if (wallpaper == null) {
        return _buildGradientBackground();
      }
      return Image.network(
        wallpaper.url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // Keep the gradient visible while the image is still loading.
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return _buildGradientBackground();
        },
        // Fall back to the gradient if the network image fails to load.
        errorBuilder: (context, error, stackTrace) =>
            _buildGradientBackground(),
      );
    });
  }

  Widget _buildGradientBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF16213E),
            Color(0xFF0F3460),
            Color(0xFF533483),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopIcons(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 24,
      direction: Axis.vertical,
      children: _appItems.map((appItem) {
        return _DesktopIcon(
          label: appItem.label,
          icon: appItem.icon,
          isOpen: _openWindows.containsKey(appItem.route),
          onTap: () => _openAppWindow(appItem),
        );
      }).toList(),
    );
  }

  Widget _buildDock(BuildContext context) {
    return Center(
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _appItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _DockIcon(
                icon: _appItems[i].icon,
                label: _appItems[i].label,
                isActive: _openWindows.containsKey(_appItems[i].route),
                onTap: () => _openAppWindow(_appItems[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Data class holding a window entry's state.
class _WindowEntry {
  final shadcn.Window window;
  final shadcn.WindowController controller;
  final _DesktopAppItem appItem;

  const _WindowEntry({
    required this.window,
    required this.controller,
    required this.appItem,
  });
}

/// A single desktop icon with label.
class _DesktopIcon extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isOpen;
  final VoidCallback onTap;

  const _DesktopIcon({
    required this.label,
    required this.icon,
    required this.isOpen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isOpen
                    ? Colors.white.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isOpen
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A dock icon at the bottom of the desktop.
class _DockIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _DockIcon({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            if (isActive)
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
