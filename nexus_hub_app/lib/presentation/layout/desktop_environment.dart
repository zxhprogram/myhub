import 'dart:async';
import 'dart:ui';


import 'package:flutter_reorderable_grid_view/entities/reorder_update_entity.dart';
import 'package:flutter_reorderable_grid_view/widgets/reorderable_builder.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/desktop_item.dart';
import '../../data/models/weather_model.dart';
import '../../data/services/weather_service.dart';

import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/desktop_folder.dart';
import '../components/wallpaper_picker_dialog.dart';
import '../pages/ai_chat_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/calendar_page.dart';
import '../pages/camera_page.dart';
import '../pages/clipboard_history_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/dev_tools_page.dart';
import '../pages/ebook/ebook_library_page.dart';
import '../pages/google_news_page.dart';
import '../pages/java_decompiler_page.dart';
import '../pages/mail_page.dart';
import '../pages/music_player_page.dart';
import '../pages/my_computer_page.dart';
import '../pages/pomodoro_page.dart';
import '../pages/rss_reader_page.dart';
import '../pages/stocks_page.dart';
import '../pages/tasks_page.dart';
import '../pages/terminal/terminal_page.dart';
import '../pages/trending_page.dart';
import '../pages/video/video_player_page.dart';
import '../pages/zhihu/zhihu_hot_page.dart';
import '../states/desktop_state.dart';
import '../states/pomodoro_state.dart';
import '../states/terminal_state.dart';
import '../states/theme_state.dart';
import '../states/wallpaper_state.dart';

/// Navigation item descriptor for the desktop environment.
class DesktopAppItem {
  final String label;
  final IconData icon;
  final String route;
  final WidgetBuilder pageBuilder;

  /// Top color of the macOS-style squircle gradient.
  final Color gradientStart;

  /// Bottom color of the macOS-style squircle gradient.
  final Color gradientEnd;

  const DesktopAppItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.pageBuilder,
    required this.gradientStart,
    required this.gradientEnd,
  });
}

/// A macOS Big Sur style squircle — a heavily rounded square filled with a
/// diagonal gradient that mimics the vibrant pastel app icons of recent macOS.
class _MacOsSquircle extends StatelessWidget {
  final Color gradientStart;
  final Color gradientEnd;
  final Widget? child;
  final double size;

  const _MacOsSquircle({
    required this.gradientStart,
    required this.gradientEnd,
    this.child,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    // macOS icons are rounded ~22.3% (approximately 4:1 of 60pt squircle).
    final radius = size * 0.23;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _SquircleShine(size: size),
            if (child != null)
              Center(
                child: IconTheme(
                  data: const IconThemeData(color: const Color(0xFFFFFFFF)),
                  child: child!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Top glass highlight that gives the squircle the glossy macOS finish.
class _SquircleShine extends StatelessWidget {
  final double size;

  const _SquircleShine({required this.size});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.23;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFFFFF).withValues(alpha: 0.4),
            const Color(0xFFFFFFFF).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45],
        ),
      ),
    );
  }
}

/// Height of the overlay menu bar at the top of the desktop.
///
/// Windows are maximized below it (see [WindowNavigator.maximizedInsets]) so
/// their title bar is never covered by the menu bar.
const double _kMenuBarHeight = 32.0;

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
  static final List<DesktopAppItem> _appItems = [
    DesktopAppItem(
      label: 'Dashboard',
      icon: RadixIcons.dashboard,
      route: '/',
      pageBuilder: (_) => const DashboardPage(),
      gradientStart: const Color(0xFF5AC8FA),
      gradientEnd: const Color(0xFF007AFF),
    ),
    DesktopAppItem(
      label: 'Bookmarks',
      icon: LucideIcons.bookmark,
      route: '/bookmarks',
      pageBuilder: (_) => const BookmarksPage(),
      gradientStart: const Color(0xFFFF9F0A),
      gradientEnd: const Color(0xFFFF3B30),
    ),
    DesktopAppItem(
      label: 'Tasks',
      icon: LucideIcons.circleCheck,
      route: '/tasks',
      pageBuilder: (_) => const TasksPage(),
      gradientStart: const Color(0xFF34C759),
      gradientEnd: const Color(0xFF30D158),
    ),
    DesktopAppItem(
      label: 'Clipboard',
      icon: RadixIcons.clipboard,
      route: '/clipboard',
      pageBuilder: (_) => const ClipboardHistoryPage(),
      gradientStart: const Color(0xFFAF52DE),
      gradientEnd: const Color(0xFFBF5AF2),
    ),
    DesktopAppItem(
      label: 'RSS Reader',
      icon: LucideIcons.rss,
      route: '/rss',
      pageBuilder: (_) => const RssReaderPage(),
      gradientStart: const Color(0xFFFF2D55),
      gradientEnd: const Color(0xFFFF6B6B),
    ),
    DesktopAppItem(
      label: 'Google News',
      icon: LucideIcons.newspaper,
      route: '/news',
      pageBuilder: (_) => const GoogleNewsPage(),
      gradientStart: const Color(0xFF4285F4),
      gradientEnd: const Color(0xFF34A853),
    ),
    DesktopAppItem(
      label: 'Mail',
      icon: LucideIcons.mail,
      route: '/mail',
      pageBuilder: (_) => const MailPage(),
      gradientStart: const Color(0xFF64D2FF),
      gradientEnd: const Color(0xFF0096E6),
    ),
    DesktopAppItem(
      label: 'AI Chat',
      icon: RadixIcons.chatBubble,
      route: '/ai-chat',
      pageBuilder: (_) => const AiChatPage(),
      gradientStart: const Color(0xFF32D74B),
      gradientEnd: const Color(0xFF0A84FF),
    ),
    DesktopAppItem(
      label: 'Stocks',
      icon: LucideIcons.chartLine,
      route: '/stocks',
      pageBuilder: (_) => const StocksPage(),
      gradientStart: const Color(0xFF30D158),
      gradientEnd: const Color(0xFF248A3D),
    ),
    DesktopAppItem(
      label: 'My Computer',
      icon: LucideIcons.monitor,
      route: '/my-computer',
      pageBuilder: (_) => const MyComputerPage(),
      gradientStart: const Color(0xFF9AA0A6),
      gradientEnd: const Color(0xFF5F6368),
    ),
    DesktopAppItem(
      label: 'DevTools',
      icon: LucideIcons.hammer,
      route: '/dev-tools',
      pageBuilder: (_) => const DevToolsPage(),
      gradientStart: const Color(0xFFFF9500),
      gradientEnd: const Color(0xFFFF3B30),
    ),
    DesktopAppItem(
      label: 'GitHub Trending',
      icon: LucideIcons.trendingUp,
      route: '/github-trending',
      pageBuilder: (_) => const TrendingPage(),
      gradientStart: const Color(0xFF4078C0),
      gradientEnd: const Color(0xFF24292E),
    ),
    DesktopAppItem(
      label: 'Terminal',
      icon: LucideIcons.terminal,
      route: '/terminal',
      pageBuilder: (_) => const TerminalPage(),
      gradientStart: const Color(0xFF2E2E2E),
      gradientEnd: const Color(0xFF000000),
    ),
    DesktopAppItem(
      label: 'Pomodoro',
      icon: LucideIcons.timer,
      route: '/pomodoro',
      pageBuilder: (_) => const PomodoroPage(),
      gradientStart: const Color(0xFFFF5F6D),
      gradientEnd: const Color(0xFFFFC371),
    ),
    DesktopAppItem(
      label: 'Camera',
      icon: LucideIcons.camera,
      route: '/camera',
      pageBuilder: (_) => const CameraCapturePage(),
      gradientStart: const Color(0xFF5AC8FA),
      gradientEnd: const Color(0xFF0A84FF),
    ),
    DesktopAppItem(
      label: 'Calendar',
      icon: LucideIcons.calendarDays,
      route: '/calendar',
      pageBuilder: (_) => const CalendarPage(),
      gradientStart: const Color(0xFFFF453A),
      gradientEnd: const Color(0xFFC60E0E),
    ),
    DesktopAppItem(
      label: 'Music',
      icon: LucideIcons.music,
      route: '/music',
      pageBuilder: (_) => const MusicPlayerPage(),
      gradientStart: const Color(0xFFFB5C74),
      gradientEnd: const Color(0xFFFA233B),
    ),
    DesktopAppItem(
      label: 'Java Decompiler',
      icon: LucideIcons.coffee,
      route: '/java-decompiler',
      pageBuilder: (_) => const JavaDecompilerPage(),
      gradientStart: const Color(0xFFC89060),
      gradientEnd: const Color(0xFF6F4E37),
    ),
    DesktopAppItem(
      label: 'Video',
      icon: LucideIcons.monitorPlay,
      route: '/video',
      pageBuilder: (_) => const VideoPlayerPage(),
      gradientStart: const Color(0xFFE50914),
      gradientEnd: const Color(0xFF7A0005),
    ),
    DesktopAppItem(
      label: '知乎',
      icon: LucideIcons.flame,
      route: '/zhihu',
      pageBuilder: (_) => const ZhihuHotPage(),
      gradientStart: const Color(0xFF38A3FF),
      gradientEnd: const Color(0xFF0066FF),
    ),
    DesktopAppItem(
      label: 'Ebook Reader',
      icon: LucideIcons.bookOpenText,
      route: '/ebooks',
      pageBuilder: (_) => const EbookLibraryPage(),
      gradientStart: const Color(0xFF64D2FF),
      gradientEnd: const Color(0xFF1E5AF0),
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
    // Load persisted theme, wallpaper and desktop state.
    ThemeState.instance.init();
    WallpaperState.instance.init();
    PomodoroState.instance.init();
    TerminalState.instance.init();
    DesktopState.instance.init(
      defaults: _appItems
          .map(
            (a) => DesktopItem(
              id: a.route,
              type: DesktopItemType.app,
              label: a.label,
              appRoute: a.route,
            ),
          )
          .toList(),
    );
  }

  @override
  void dispose() {
    for (final entry in _openWindows.values) {
      entry.controller.dispose();
    }
    super.dispose();
  }

  WindowNavigatorHandle? get _navigatorHandle {
    final state = _navigatorKey.currentState;
    if (state is WindowNavigatorHandle) {
      return state;
    }
    return null;
  }

  void _openAppWindow(DesktopAppItem appItem) {
    // If window already open, focus or toggle minimize
    if (_openWindows.containsKey(appItem.route)) {
      final entry = _openWindows[appItem.route]!;
      if (entry.controller.minimized) {
        // Restore minimized window
        entry.controller.minimized = false;
        _navigatorHandle?.focusWindow(entry.window);
      } else if (entry.window.handle.focused) {
        // Minimize if already focused (macOS behavior)
        entry.controller.minimized = true;
      } else {
        // Focus if not focused
        _navigatorHandle?.focusWindow(entry.window);
      }
      return;
    }

    final controller = WindowController(
      bounds: Rect.fromLTWH(
        60 + (_windowCounter % 5) * 40,
        40 + _kMenuBarHeight + (_windowCounter % 5) * 40, // below menu bar
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

    final window = Window.controlled(
      controller: controller,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            appItem.icon,
            size: 16,
            color: Theme.of(context).colorScheme.foreground,
          ),
          const SizedBox(width: 8),
          Text(
            appItem.label,
            style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      // Each window gets its own local Navigator so in-page navigation
      // (e.g. Google News article details) stays inside the window instead
      // of being pushed onto the app's root navigator, which would cover
      // the whole desktop and break back navigation.
      content: ClipRect(
        child: Navigator(
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (context, animation, secondaryAnimation) =>
                appItem.pageBuilder(context),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
      ),
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

  /// Handles reorder events from [ReorderableBuilder].
  ///
  /// If the drag target is a folder and the dragged item is an app, the item is
  /// moved into the folder instead of reordering the desktop list.
  void _onDesktopReorder(List<ReorderUpdateEntity> entities) {
    if (entities.isEmpty) return;
    final entity = entities.first;
    final oldIndex = entity.oldIndex;
    final newIndex = entity.newIndex;

    final state = DesktopState.instance;
    final items = state.items.value;

    // Compute the effective target index (ReorderableBuilder's newIndex
    // accounts for the removed item when newIndex > oldIndex).
    final targetIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (targetIndex >= 0 && targetIndex < items.length) {
      final targetItem = items[targetIndex];
      if (targetItem.type == DesktopItemType.folder) {
        final draggedItem = items[oldIndex];
        if (draggedItem.type == DesktopItemType.app) {
          state.moveItemToFolder(draggedItem.id, targetItem.id);
          return;
        }
      }
    }

    state.reorder(oldIndex, newIndex);
  }

  /// Shows a dialog to create a new folder on the desktop.
  Future<void> _showNewFolderDialog(BuildContext context) async {
    final name = await _showPromptDialog(
      context,
      title: '新建文件夹',
      confirmLabel: '创建',
    );
    if (name != null && name.isNotEmpty) {
      DesktopState.instance.createFolder(name);
    }
  }

  /// Shows a dialog to rename a folder.
  Future<void> _renameFolderDialog(
    BuildContext context,
    String folderId,
    String currentName,
  ) async {
    final name = await _showPromptDialog(
      context,
      title: '重命名文件夹',
      confirmLabel: '确认',
      initialText: currentName,
    );
    if (name != null && name.isNotEmpty) {
      DesktopState.instance.renameFolder(folderId, name);
    }
  }

  /// Shows a confirmation dialog before deleting a folder.
  Future<void> _confirmDeleteFolder(
    BuildContext context,
    String folderId,
  ) async {
    final confirmed = await showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) => AlertDialog(
          title: const Text('删除文件夹'),
          content: const Text('确定要删除此文件夹吗？文件夹内的图标不会被删除。'),
          actions: [
            Button.text(
              onPressed: () => closeOverlay<bool>(ctx, false),
              child: const Text('取消'),
            ),
            Button.destructive(
              onPressed: () => closeOverlay<bool>(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    ).future;
    if (confirmed == true) {
      DesktopState.instance.deleteFolder(folderId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WindowNavigator(
          key: _navigatorKey,
          initialWindows: const [],
          // Maximized windows stop below the overlay menu bar so their
          // title bar stays visible and draggable.
          maximizedInsets: const EdgeInsets.only(top: _kMenuBarHeight),
          child: _buildDesktopContent(context),
        ),
        // Menu bar on top of everything, including windows (like macOS).
        const Positioned(top: 0, left: 0, right: 0, child: _MenuBar()),
      ],
    );
  }

  Widget _buildDesktopContent(BuildContext context) {
    return Watch((_) {
      final wallpaper = WallpaperState.instance.currentWallpaper.value;
      return ContextMenu(
        items: [
          MenuButton(
            leading: const Icon(LucideIcons.image, size: 16),
            onPressed: (context) => WallpaperPickerDialog.show(context),
            child: const Text('更换壁纸'),
          ),
          if (wallpaper != null) ...[
            const MenuDivider(),
            MenuButton(
              leading: const Icon(LucideIcons.rotateCcw, size: 16),
              onPressed: (context) => WallpaperState.instance.clearWallpaper(),
              child: const Text('恢复默认壁纸'),
            ),
          ],
          const MenuDivider(),
          MenuButton(
            leading: const Icon(LucideIcons.folderPlus, size: 16),
            onPressed: (context) => _showNewFolderDialog(context),
            child: const Text('新建文件夹'),
          ),
        ],
        child: Stack(
          children: [
            // Desktop background
            _buildBackground(context),
            // Desktop icons area
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: NexusSpacing.lg,
                  top: 48, // Leave room for the menu bar
                  bottom: 100,
                ),
                child: _buildDesktopIcons(context),
              ),
            ),
            // Dock at bottom
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: _buildDock(context),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildBackground(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final wallpaper = WallpaperState.instance.currentWallpaper.value;
      Widget base;
      if (wallpaper == null) {
        base = _buildGradientBackground(context);
      } else {
        base = Image.network(
          wallpaper.url,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }
            return _buildGradientBackground(context);
          },
          errorBuilder: (context, error, stackTrace) =>
              _buildGradientBackground(context),
        );
      }

      return Stack(
        fit: StackFit.expand,
        children: [
          base,
          Container(color: colorScheme.background.withValues(alpha: 0.35)),
        ],
      );
    });
  }

  Widget _buildGradientBackground(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF1A1A2E),
                  Color(0xFF16213E),
                  Color(0xFF0F3460),
                  Color(0xFF533483),
                ]
              : const [
                  Color(0xFFF0F4FF),
                  Color(0xFFE5EEFF),
                  Color(0xFFDCE9FF),
                  Color(0xFFD3E4FE),
                ],
        ),
      ),
    );
  }

  Widget _buildDesktopIcons(BuildContext context) {
    return Watch((_) {
      final desktopItems = DesktopState.instance.items.value;
      return ReorderableBuilder(
        onReorderPositions: _onDesktopReorder,
        builder: (children) {
          return Wrap(
            spacing: 16,
            runSpacing: 24,
            direction: Axis.vertical,
            children: children,
          );
        },
        children: desktopItems.map((item) {
          final isOpen =
              item.type == DesktopItemType.app &&
              _openWindows.containsKey(item.appRoute);
          return _DesktopIcon(
            key: ValueKey(item.id),
            item: item,
            isOpen: isOpen,
            onTap: () {
              if (item.type == DesktopItemType.app) {
                final appItem = _appItems.cast<DesktopAppItem?>().firstWhere(
                  (a) => a!.route == item.appRoute,
                  orElse: () => null,
                );
                if (appItem != null) _openAppWindow(appItem);
              }
            },
            onFolderDoubleTap: item.type == DesktopItemType.folder
                ? () => DesktopFolderContent.show(context, item.id)
                : null,
            onRename: item.type == DesktopItemType.folder
                ? () => _renameFolderDialog(
                    context,
                    item.id,
                    item.folderName ?? '',
                  )
                : null,
            onDelete: item.type == DesktopItemType.folder
                ? () => _confirmDeleteFolder(context, item.id)
                : null,
          );
        }).toList(),
      );
    });
  }

  Widget _buildDock(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            height: 80,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.card.withValues(alpha: 0.18),
              border: Border.all(
                color: colorScheme.border.withValues(alpha: 0.2),
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _appItems.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  _DockIcon(
                    icon: _appItems[i].icon,
                    gradientStart: _appItems[i].gradientStart,
                    gradientEnd: _appItems[i].gradientEnd,
                    label: _appItems[i].label,
                    isActive: _openWindows.containsKey(_appItems[i].route),
                    onTap: () => _openAppWindow(_appItems[i]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// macOS-style menu bar at the top of the desktop with a live clock.
class _MenuBar extends StatelessWidget {
  const _MenuBar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      height: _kMenuBarHeight,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF000000).withValues(alpha: 0.25)
            : const Color(0xFFFFFFFF).withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.border.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          // Left: app name (like macOS Apple menu area)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.apple,
                size: 16,
                color: isDark
                    ? const Color(0xFFFFFFFF).withValues(alpha: 0.9)
                    : const Color(0xFF000000).withValues(alpha: 0.85),
              ),
              const SizedBox(width: 8),
              Text(
                'Nexus Hub',
                style: TextStyle(
                  color: isDark
                      ? const Color(0xFFFFFFFF).withValues(alpha: 0.9)
                      : const Color(0xFF000000).withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Right: weather + theme toggle + live clock
          const _WeatherWidget(),
          const SizedBox(width: 8),
          _MenuIconButton(
            icon: isDark ? LucideIcons.moon : LucideIcons.sun,
            onTap: () => ThemeState.instance.toggle(),
          ),
          const SizedBox(width: 8),
          const _ClockWidget(),
        ],
      ),
    );
  }
}

class _MenuIconButton extends StatelessWidget {
  const _MenuIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return IconButton.ghost(
      icon: Icon(
        icon,
        size: 16,
        color: isDark
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.9)
            : const Color(0xFF000000).withValues(alpha: 0.85),
      ),
      onPressed: onTap,
    );
  }
}

/// Live clock that updates every second, displaying HH:mm:ss.
class _ClockWidget extends StatefulWidget {
  const _ClockWidget();

  @override
  State<_ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<_ClockWidget> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Sync to the next whole second so the update is aligned.
    final now = DateTime.now();
    final nextSecond = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second + 1,
    );
    final delay = nextSecond.difference(now).inMilliseconds;
    _timer = Timer(Duration(milliseconds: delay), _tick);
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _now = DateTime.now();
    });
    _timer = Timer(const Duration(seconds: 1), _tick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm:ss').format(_now);
    final date = DateFormat('M/d (EEE)').format(_now);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          date,
          style: TextStyle(
            color: isDark
                ? const Color(0xFFFFFFFF).withValues(alpha: 0.8)
                : const Color(0xFF000000).withValues(alpha: 0.75),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          time,
          style: TextStyle(
            color: isDark
                ? const Color(0xFFFFFFFF).withValues(alpha: 0.95)
                : const Color(0xFF000000).withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Weather summary for the menu bar: condition icon + description +
/// temperature, followed by today's sunrise and sunset times. Data comes
/// from [WeatherService] (cached; refreshes silently every 10 minutes).
class _WeatherWidget extends StatefulWidget {
  const _WeatherWidget();

  @override
  State<_WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<_WeatherWidget> {
  final WeatherService _service = WeatherService();
  WeatherInfo? _weather;

  @override
  void initState() {
    super.initState();
    _service.fetchWeather().then((weather) {
      if (mounted) {
        setState(() => _weather = weather);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    // Stay invisible until data arrives so the menu bar keeps its layout
    // while loading or when the network is unavailable.
    if (weather == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final Color foreground = isDark
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.8)
        : const Color(0xFF000000).withValues(alpha: 0.75);

    final timeStyle = TextStyle(
      color: foreground,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _iconForCode(weather.weatherCode),
          size: 14,
          color: foreground,
        ),
        const SizedBox(width: 4),
        Text(
          '${_descriptionForCode(weather.weatherCode)} '
          '${weather.temperature.round()}°',
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 10),
        Icon(LucideIcons.sunrise, size: 13, color: foreground),
        const SizedBox(width: 3),
        Text(DateFormat('HH:mm').format(weather.sunrise), style: timeStyle),
        const SizedBox(width: 8),
        Icon(LucideIcons.sunset, size: 13, color: foreground),
        const SizedBox(width: 3),
        Text(DateFormat('HH:mm').format(weather.sunset), style: timeStyle),
      ],
    );
  }

  /// Maps a WMO weather interpretation code to a menu bar icon.
  static IconData _iconForCode(int code) {
    if (code == 0 || code == 1) return LucideIcons.sun;
    if (code == 2) return LucideIcons.cloudSun;
    if (code == 3) return LucideIcons.cloud;
    if (code == 45 || code == 48) return LucideIcons.cloudFog;
    if (code >= 51 && code <= 57) return LucideIcons.cloudDrizzle;
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) {
      return LucideIcons.cloudRain;
    }
    if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
      return LucideIcons.cloudSnow;
    }
    if (code >= 95) return LucideIcons.cloudLightning;
    return LucideIcons.cloud;
  }

  /// Maps a WMO weather interpretation code to a short Chinese description.
  static String _descriptionForCode(int code) {
    if (code == 0 || code == 1) return '晴';
    if (code == 2) return '多云';
    if (code == 3) return '阴';
    if (code == 45 || code == 48) return '雾';
    if (code >= 51 && code <= 57) return '毛毛雨';
    if (code == 61 || code == 80) return '小雨';
    if (code == 63 || code == 81) return '中雨';
    if (code == 65 || code == 82 || code == 66 || code == 67) return '大雨';
    if (code >= 71 && code <= 77) return '雪';
    if (code == 85 || code == 86) return '阵雪';
    if (code >= 95) return '雷阵雨';
    return '多云';
  }
}

/// Data class holding a window entry's state.
class _WindowEntry {
  final Window window;
  final WindowController controller;
  final DesktopAppItem appItem;

  const _WindowEntry({
    required this.window,
    required this.controller,
    required this.appItem,
  });
}

/// A single desktop icon with label.
class _DesktopIcon extends StatelessWidget {
  const _DesktopIcon({
    super.key,
    required this.item,
    required this.isOpen,
    required this.onTap,
    this.onFolderDoubleTap,
    this.onRename,
    this.onDelete,
  });

  final DesktopItem item;
  final bool isOpen;
  final VoidCallback onTap;
  final VoidCallback? onFolderDoubleTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  /// Resolves the matching [DesktopAppItem] from the static app list by route.
  DesktopAppItem? get _appItem {
    if (item.type != DesktopItemType.app || item.appRoute == null) return null;
    return _resolveAppItem(item.appRoute!);
  }

  @override
  Widget build(BuildContext context) {
    if (item.type == DesktopItemType.folder) {
      return _buildFolderIcon(context);
    }
    return _buildAppIcon(context);
  }

  Widget _buildAppIcon(BuildContext context) {
    final appItem = _appItem;
    if (appItem == null) return const SizedBox.shrink();

    return SizedBox(
      width: 72,
      child: GestureDetector(
        onTap: onTap,
        onDoubleTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: isOpen ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Container(
                decoration: isOpen
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: appItem.gradientEnd.withValues(alpha: 0.5),
                            blurRadius: 14,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      )
                    : null,
                child: _MacOsSquircle(
                  gradientStart: appItem.gradientStart,
                  gradientEnd: appItem.gradientEnd,
                  child: Icon(appItem.icon, size: 26),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _DesktopIconLabel(label: appItem.label),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderIcon(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final folderName = item.label ?? item.folderName ?? '文件夹';
    return DragTarget<DesktopItem>(
      onWillAcceptWithDetails: (details) =>
          details.data.type == DesktopItemType.app,
      onAcceptWithDetails: (details) {
        DesktopState.instance.moveItemToFolder(details.data.id, item.id);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return SizedBox(
          width: 72,
          child: ContextMenu(
            items: [
              MenuButton(
                onPressed: (context) => onFolderDoubleTap?.call(),
                child: const Text('打开'),
              ),
              MenuButton(
                onPressed: (context) => onRename?.call(),
                child: const Text('重命名'),
              ),
              MenuButton(
                onPressed: (context) => onDelete?.call(),
                child: const Text('删除'),
              ),
            ],
            child: GestureDetector(
              onTap: onFolderDoubleTap,
              onDoubleTap: onFolderDoubleTap,
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: isHovering ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(48 * 0.23),
                      color: isHovering
                          ? colorScheme.muted.withValues(
                              alpha: isDark ? 0.5 : 0.6,
                            )
                          : colorScheme.muted.withValues(
                              alpha: isDark ? 0.25 : 0.35,
                            ),
                      border: Border.all(
                        color: isHovering
                            ? colorScheme.border.withValues(
                                alpha: isDark ? 0.6 : 0.7,
                              )
                            : colorScheme.border.withValues(
                                alpha: isDark ? 0.3 : 0.4,
                              ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48 * 0.23),
                      child: DesktopFolderPreview(folderId: item.id),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _DesktopIconLabel(label: folderName),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  /// Theme-aware label used by both app and folder desktop icons.
  Widget _DesktopIconLabel({required String label}) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final isDark = colorScheme.brightness == Brightness.dark;
        return Text(
          label,
          style: TextStyle(
            color: isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000).withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.2,
            shadows: [
              Shadow(
                color: isDark ? const Color(0x73000000) : const Color(0x89FFFFFF),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

/// Resolves a [DesktopAppItem] by route from the static app items list.
DesktopAppItem? _resolveAppItem(String route) {
  try {
    return _DesktopEnvironmentState._appItems.firstWhere(
      (a) => a.route == route,
    );
  } catch (_) {
    return null;
  }
}

/// shadcn text-prompt dialog returning the entered value (trimmed).
Future<String?> _showPromptDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? initialText,
}) async {
  final controller = TextEditingController(text: initialText ?? '');
  return showOverlay<String>(
    context,
    DialogConfiguration<String>(
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
      builder: (ctx) => _PromptDialog(
        controller: controller,
        title: title,
        confirmLabel: confirmLabel,
      ),
    ),
  ).future;
}

class _PromptDialog extends StatelessWidget {
  const _PromptDialog({
    required this.controller,
    required this.title,
    required this.confirmLabel,
  });

  final TextEditingController controller;
  final String title;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        hintText: '文件夹名称',
        onSubmitted: (value) => closeOverlay<String>(context, value.trim()),
      ),
      actions: [
        Button.text(
          onPressed: () => closeOverlay<String>(context),
          child: const Text('取消'),
        ),
        Button.primary(
          onPressed: () =>
              closeOverlay<String>(context, controller.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// A dock icon at the bottom of the desktop, with macOS-style hover
/// magnification, app label preview, and window preview for active apps.
class _DockIcon extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color gradientStart;
  final Color gradientEnd;
  final bool isActive;
  final VoidCallback onTap;

  const _DockIcon({
    required this.icon,
    required this.label,
    required this.gradientStart,
    required this.gradientEnd,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_DockIcon> createState() => _DockIconState();
}

class _DockIconState extends State<_DockIcon> {
  bool _isHovering = false;
  bool _showPreview = false;

  @override
  Widget build(BuildContext context) {
    final iconSize = _isHovering ? 56.0 : 48.0;
    final iconRadius = iconSize * 0.23;

    return SizedBox(
      width: _isHovering ? 68 : 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main layout: icon + active indicator (fits within dock height)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Dock icon with magnification
              ContextMenu(
                items: [
                  if (widget.isActive) ...[
                    MenuButton(
                      onPressed: (context) => widget.onTap(),
                      child: const Text('隐藏'),
                    ),
                    MenuButton(
                      onPressed: (context) => widget.onTap(),
                      child: const Text('退出'),
                    ),
                  ] else
                    MenuButton(
                      onPressed: (context) => widget.onTap(),
                      child: const Text('打开'),
                    ),
                  const MenuDivider(),
                  MenuButton(
                    onPressed: (context) {},
                    child: const Text('选项'),
                  ),
                ],
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: MouseRegion(
                  onEnter: (_) => setState(() {
                    _isHovering = true;
                    if (widget.isActive) {
                      _showPreview = true;
                    }
                  }),
                  onExit: (_) => setState(() {
                    _isHovering = false;
                    _showPreview = false;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOut,
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(iconRadius),
                      boxShadow: [
                        BoxShadow(
                          color: widget.gradientEnd.withValues(
                            alpha: _isHovering ? 0.5 : 0.3,
                          ),
                          blurRadius: _isHovering ? 12 : 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _MacOsSquircle(
                      gradientStart: widget.gradientStart,
                      gradientEnd: widget.gradientEnd,
                      size: iconSize,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        child: Icon(widget.icon, size: _isHovering ? 26 : 22),
                      ),
                    ),
                  ),
                ),
              ),
              ),
              // Active indicator dot (macOS style)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: widget.isActive ? 4 : 0,
                height: 4,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF).withValues(
                    alpha: widget.isActive ? (_isHovering ? 0.9 : 0.6) : 0.0,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),

          // App label - positioned above the icon (overflow outside dock)
          if (_isHovering)
            Positioned(
              bottom: iconSize + 12, // icon height + dot area + gap
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF000000).withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.label,
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          // Window preview - positioned above label
          if (_showPreview && widget.isActive)
            Positioned(
              bottom: iconSize + 12 + 22 + 4,
              // icon + dot area + label height + gap
              left: 0,
              right: 0,
              child: Center(child: _buildWindowPreview()),
            ),
        ],
      ),
    );
  }

  /// Builds a small macOS-style window preview card that appears above the
  /// dock icon when hovering over an active (open) application.
  Widget _buildWindowPreview() {
    return Container(
      width: 130,
      height: 90,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF2C2C2E),
        border: Border.all(color: const Color(0xFFFFFFFF).withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          children: [
            // macOS traffic light title bar
            Container(
              height: 20,
              color: const Color(0xFF3A3A3C),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Red
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFF5F57),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Yellow
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFEBC2E),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Green
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF28C840),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.label,
                      style: const TextStyle(
                        color: const Color(0x89FFFFFF),
                        fontSize: 8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Preview content area
            Expanded(
              child: Center(
                child: Opacity(
                  opacity: 0.2,
                  child: Icon(widget.icon, size: 28),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
