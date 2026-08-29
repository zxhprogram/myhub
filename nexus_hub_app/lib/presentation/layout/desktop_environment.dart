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

import '../../theme/density.dart';
import '../../data/services/clash_system_proxy.dart';
import '../../data/services/network_monitor_service.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/desktop_folder.dart';
import '../components/desktop_folder_name_dialog.dart';
import '../components/wallpaper_picker_dialog.dart';
import 'controlled_window.dart';
import '../pages/ai_chat_page.dart';
import '../pages/bookmarks_page.dart';
import '../pages/calendar_page.dart';
import '../pages/camera_page.dart';
import '../pages/clash/clash_app_page.dart';
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
import '../pages/pub_dev_page.dart';
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
/// The window navigator is padded below it so maximized windows never have
/// their title bar covered by the menu bar.
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
      label: 'Pub Packages',
      icon: LucideIcons.package,
      route: '/pub-dev',
      pageBuilder: (_) => const PubDevPage(),
      gradientStart: const Color(0xFF01579B),
      gradientEnd: const Color(0xFF0175C2),
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
    DesktopAppItem(
      label: 'Clash',
      icon: LucideIcons.shield,
      route: '/clash',
      pageBuilder: (_) => const ClashAppPage(),
      gradientStart: const Color(0xFF60A5FA),
      gradientEnd: const Color(0xFF4338CA),
    ),
  ];

  /// Apps always shown in the dock regardless of running state. The full
  /// app list stays on the desktop icons; the dock keeps only these
  /// favorites plus any other currently-running apps.
  static const List<String> _dockPinnedRoutes = [
    '/',
    '/tasks',
    '/ai-chat',
    '/mail',
    '/terminal',
    '/clash',
    '/music',
    '/ebooks',
  ];

  /// Key to access the [WindowNavigatorHandle] for adding/removing windows.
  final GlobalKey _navigatorKey = GlobalKey();

  /// Map of open windows by route path, with their controllers.
  final Map<String, _WindowEntry> _openWindows = {};

  int _windowCounter = 0;

  /// Element contexts of folder icons, used for drop-target hit tests.
  ///
  /// Registered by [_FolderHitTarget]; never uses GlobalKeys because the
  /// reorderable grid duplicates the child into the drag feedback, which
  /// would collide a GlobalKey across two widget subtrees.
  final Map<String, BuildContext> _folderHitContexts = {};

  /// Id of the desktop item currently being dragged (null when idle).
  String? _draggingDesktopItemId;

  /// Global pointer position while a desktop icon drag is active.
  Offset? _desktopDragPointer;

  /// Set when the dragged app was released over a folder; the next reorder
  /// event is skipped so positions stay put (the app goes into the folder).
  bool _skipNextDesktopReorder = false;

  /// Indices locked from live-swapping, mutated in place at drag start.
  ///
  /// While an app is dragged, folders are locked so the drag never displaces
  /// them — the folder stays under the pointer until drop, which makes
  /// dropping the app into the folder reliable.
  final List<int> _desktopLockedIndices = <int>[];

  @override
  void initState() {
    super.initState();
    // Load persisted theme, wallpaper, desktop state and density.
    ThemeState.instance.init();
    WallpaperState.instance.init();
    PomodoroState.instance.init();
    TerminalState.instance.init();
    NexusDensityController.init();
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
      // Restore bounds used when the user un-maximizes; windows open
      // maximized (relative full-viewport rect resolved by the navigator,
      // whose viewport already starts below the menu bar).
      bounds: Rect.fromLTWH(
        60 + (_windowCounter % 5) * 40,
        40 + (_windowCounter % 5) * 40, // below menu bar (padded viewport)
        900,
        600,
      ),
      maximized: const Rect.fromLTWH(0, 0, 1, 1),
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

    // ControlledWindow pins `alwaysOnTop` to a non-null value so windows
    // don't vanish after the first drag (published shadcn_flutter 0.0.53
    // bug). See controlled_window.dart and test/window_drag_test.dart.
    final window = ControlledWindow(
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
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) =>
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

  /// Opens an app window by route (used by menu bar status widgets).
  void _openAppByRoute(String route) {
    final appItem = _appItems.cast<DesktopAppItem?>().firstWhere(
      (a) => a!.route == route,
      orElse: () => null,
    );
    if (appItem != null) _openAppWindow(appItem);
  }

  /// Handles reorder events from [ReorderableBuilder].
  ///
  /// If the dragged app was released over a folder, the reorder is skipped
  /// (positions stay put) — the app was already moved into the folder in
  /// [_onDesktopIconDragEnd].
  void _onDesktopReorder(List<ReorderUpdateEntity> entities) {
    if (entities.isEmpty) return;
    if (_skipNextDesktopReorder) {
      _skipNextDesktopReorder = false;
      return;
    }
    final entity = entities.first;
    DesktopState.instance.reorderVisible(entity.oldIndex, entity.newIndex);
  }

  /// Tracks drag start of a desktop icon.
  ///
  /// While an app is dragged, folder indices are locked so the live swap
  /// skips folders (they never move out from under the pointer). Dragging a
  /// folder keeps everything swappable.
  void _onDesktopIconDragStarted(int index, List<DesktopItem> items) {
    _skipNextDesktopReorder = false;
    if (index < 0 || index >= items.length) return;
    final dragged = items[index];
    _draggingDesktopItemId = dragged.id;
    _desktopDragPointer = null;
    _desktopLockedIndices.clear();
    if (dragged.type == DesktopItemType.app) {
      for (var i = 0; i < items.length; i++) {
        if (items[i].type == DesktopItemType.folder) {
          _desktopLockedIndices.add(i);
        }
      }
    }
  }

  /// Finishes a desktop icon drag.
  ///
  /// If the pointer was released over a folder and the dragged item is an
  /// app, the app is moved into that folder without swapping positions.
  void _onDesktopIconDragEnd(List<DesktopItem> items) {
    _desktopLockedIndices.clear();
    final pointer = _desktopDragPointer;
    final draggedId = _draggingDesktopItemId;
    _draggingDesktopItemId = null;
    _desktopDragPointer = null;
    if (pointer == null || draggedId == null) return;

    final isApp = items.any(
      (item) => item.id == draggedId && item.type == DesktopItemType.app,
    );
    if (!isApp) return;

    final folderId = _folderIdAtGlobalPosition(pointer, items);
    if (folderId != null) {
      _skipNextDesktopReorder = true;
      DesktopState.instance.moveItemToFolder(draggedId, folderId);
    }
  }

  /// Returns the id of the folder whose icon contains [position], or null.
  String? _folderIdAtGlobalPosition(Offset position, List<DesktopItem> items) {
    for (final item in items) {
      if (item.type != DesktopItemType.folder) continue;
      final context = _folderHitContexts[item.id];
      if (context == null || !context.mounted) continue;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final bounds = box.localToGlobal(Offset.zero) & box.size;
      if (bounds.contains(position)) return item.id;
    }
    return null;
  }

  /// Shows a dialog to create a new folder on the desktop.
  Future<void> _showNewFolderDialog(BuildContext context) async {
    final existingNames = DesktopState.instance.items.value
        .where((item) => item.type == DesktopItemType.folder)
        .map((item) => item.folderName?.toLowerCase())
        .whereType<String>()
        .toSet();
    final name = await showDesktopFolderNameDialog(
      context,
      title: '新建文件夹',
      confirmLabel: '创建',
      existingNames: existingNames,
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
    // Exclude the folder itself so keeping its own name is not flagged
    // as a duplicate.
    final existingNames = DesktopState.instance.items.value
        .where(
          (item) =>
              item.type == DesktopItemType.folder &&
              item.folderName?.toLowerCase() != currentName.toLowerCase(),
        )
        .map((item) => item.folderName?.toLowerCase())
        .whereType<String>()
        .toSet();
    final name = await showDesktopFolderNameDialog(
      context,
      title: '重命名文件夹',
      confirmLabel: '确认',
      initialName: currentName,
      existingNames: existingNames,
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
        // Desktop content fills the whole screen so the wallpaper extends
        // behind the translucent menu bar (like the real macOS menu bar).
        _buildDesktopContent(context),
        Padding(
          // The navigator's viewport starts below the menu bar, so
          // maximized/snapped windows stop below it and their title bar
          // stays visible and draggable.
          padding: const EdgeInsets.only(top: _kMenuBarHeight),
          child: WindowNavigator(key: _navigatorKey, initialWindows: const []),
        ),
        // Menu bar on top of everything, including windows (like macOS).
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _MenuBar(onOpenApp: _openAppByRoute),
        ),
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

    return Container();
  }

  Widget _buildDesktopIcons(BuildContext context) {
    return Watch((_) {
      // Items inside folders are hidden from the desktop grid.
      final desktopItems = DesktopState.instance.visibleItems;
      return Listener(
        // Track the pointer while dragging so the drop target folder can be
        // resolved at release time (folders are locked and never swap).
        onPointerMove: (event) {
          if (_draggingDesktopItemId != null) {
            _desktopDragPointer = event.position;
          }
        },
        child: ReorderableBuilder(
          onReorderPositions: _onDesktopReorder,
          lockedIndices: _desktopLockedIndices,
          onDragStarted: (index) =>
              _onDesktopIconDragStarted(index, desktopItems),
          onDragEnd: (_) => _onDesktopIconDragEnd(desktopItems),
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
            final icon = _DesktopIcon(
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
            // The reorderable grid requires a ValueKey on the direct child;
            // folder icons are additionally wrapped so their element can be
            // registered for drop hit tests (no GlobalKey — the grid
            // duplicates the child into the drag feedback).
            return KeyedSubtree(
              key: ValueKey(item.id),
              child: item.type == DesktopItemType.folder
                  ? _FolderHitTarget(
                      registry: _folderHitContexts,
                      folderId: item.id,
                      canRegister: () => _draggingDesktopItemId == null,
                      child: icon,
                    )
                  : icon,
            );
          }).toList(),
        ),
      );
    });
  }

  Widget _buildDock(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final pinned = _dockPinnedRoutes
        .map((route) => _resolveAppItem(route))
        .whereType<DesktopAppItem>()
        .toList();
    final runningExtras = _appItems
        .where(
          (app) =>
              _openWindows.containsKey(app.route) &&
              !pinned.any((p) => p.route == app.route),
        )
        .toList();
    final dockApps = [...pinned, ...runningExtras];

    // The max width keeps the dock centered when content fits and turns it
    // into a horizontal scroll area when it does not.
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 24,
        ),
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
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < dockApps.length; i++) ...[
                      if (i > 0) const SizedBox(width: 2),
                      _DockIcon(
                        icon: dockApps[i].icon,
                        gradientStart: dockApps[i].gradientStart,
                        gradientEnd: dockApps[i].gradientEnd,
                        label: dockApps[i].label,
                        isActive: _openWindows.containsKey(dockApps[i].route),
                        onTap: () => _openAppWindow(dockApps[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// macOS-style menu bar at the top of the desktop with a live clock.
class _MenuBar extends StatelessWidget {
  const _MenuBar({this.onOpenApp});

  /// Opens an app window by route from status widgets (pomodoro, clash).
  final void Function(String route)? onOpenApp;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    // Translucent frosted-glass surface like the real macOS menu bar: the
    // wallpaper behind is blurred, with a white (light) / black (dark) tint
    // on top. No hard bottom border — a soft shadow separates it from the
    // desktop.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: _kMenuBarHeight,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: isDark
              ? const Color(0xFF1C1C1E).withValues(alpha: 0.45)
              : const Color(0xFFF5F5F7).withValues(alpha: 0.55),
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
              // Right: live status area + weather + toggles + clock. The
              // status widgets keep glanceable system info one glance away.
              _ClashStatusMenuWidget(onOpenApp: onOpenApp),
              const _NetworkRateMenuWidget(),
              _PomodoroMenuWidget(onOpenApp: onOpenApp),
              const SizedBox(width: 8),
              const _WeatherWidget(),
              const SizedBox(width: 8),
              const _DensityToggleButton(),
              _MenuIconButton(
                icon: isDark ? LucideIcons.moon : LucideIcons.sun,
                onTap: () => ThemeState.instance.toggle(),
              ),
              const SizedBox(width: 8),
              const _ClockWidget(),
            ],
          ),
        ),
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

/// Foreground color for menu bar content, readable over any wallpaper.
Color _menuBarForeground(BuildContext context, {double alpha = 0.8}) {
  final isDark = Theme.of(context).colorScheme.brightness == Brightness.dark;
  return isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: alpha)
      : const Color(0xFF000000).withValues(alpha: alpha);
}

TextStyle _menuBarTextStyle(
  BuildContext context, {
  double alpha = 0.8,
  FontWeight weight = FontWeight.w500,
}) {
  return TextStyle(
    color: _menuBarForeground(context, alpha: alpha),
    fontSize: 12,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}

/// Formats a bytes-per-second rate compactly for the menu bar.
String _formatRate(double bytesPerSecond) {
  if (bytesPerSecond < 1024) return '${bytesPerSecond.round()}B';
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).round()}KB';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)}MB';
}

/// Live network up/down rates polled once per second from the native monitor.
///
/// Renders nothing while the monitor DLL is unavailable (non-Windows).
class _NetworkRateMenuWidget extends StatefulWidget {
  const _NetworkRateMenuWidget();

  @override
  State<_NetworkRateMenuWidget> createState() => _NetworkRateMenuWidgetState();
}

class _NetworkRateMenuWidgetState extends State<_NetworkRateMenuWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!NetworkMonitorService.instance.isRunning) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = NetworkMonitorService.instance;
    if (!service.isRunning) return const SizedBox.shrink();
    final style = _menuBarTextStyle(context);

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.arrowDown, size: 12, color: style.color),
          const SizedBox(width: 2),
          Text(_formatRate(service.recvSpeed.toDouble()), style: style),
          const SizedBox(width: 6),
          Icon(LucideIcons.arrowUp, size: 12, color: style.color),
          const SizedBox(width: 2),
          Text(_formatRate(service.sentSpeed.toDouble()), style: style),
        ],
      ),
    );
  }
}

/// Active Pomodoro countdown pinned to the menu bar so it stays visible no
/// matter which windows are open. Tapping toggles pause/resume.
class _PomodoroMenuWidget extends StatelessWidget {
  const _PomodoroMenuWidget({this.onOpenApp});

  final void Function(String route)? onOpenApp;

  @override
  Widget build(BuildContext context) {
    final pomodoro = PomodoroState.instance;
    return Watch((context) {
      final running = pomodoro.isRunning.value;
      final remaining = pomodoro.remainingSeconds.value;
      // Hidden while idle at the start of a session.
      if (!running && remaining == pomodoro.totalSeconds) {
        return const SizedBox.shrink();
      }
      final text =
          '${(remaining ~/ 60).toString().padLeft(2, '0')}:'
          '${(remaining % 60).toString().padLeft(2, '0')}';

      return ContextMenu(
        items: [
          MenuButton(
            onPressed: (context) => pomodoro.toggle(),
            child: Text(running ? '暂停' : '继续'),
          ),
          MenuButton(
            onPressed: (context) => pomodoro.reset(),
            child: const Text('重置'),
          ),
          if (onOpenApp != null)
            MenuButton(
              onPressed: (context) => onOpenApp!('/pomodoro'),
              child: const Text('打开番茄钟'),
            ),
        ],
        child: GestureDetector(
          onTap: pomodoro.toggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.timer,
                  size: 13,
                  color: _menuBarForeground(context, alpha: running ? 1 : 0.65),
                ),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: _menuBarTextStyle(context, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// System-proxy status from the Windows registry, polled every 10 seconds.
class _ClashStatusMenuWidget extends StatelessWidget {
  const _ClashStatusMenuWidget({this.onOpenApp});

  final void Function(String route)? onOpenApp;

  @override
  Widget build(BuildContext context) {
    return _ClashStatusIcon(onOpenApp: onOpenApp);
  }
}

class _ClashStatusIcon extends StatefulWidget {
  const _ClashStatusIcon({this.onOpenApp});

  final void Function(String route)? onOpenApp;

  @override
  State<_ClashStatusIcon> createState() => _ClashStatusIconState();
}

class _ClashStatusIconState extends State<_ClashStatusIcon> {
  Timer? _timer;
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    if (!ClashSystemProxyService.instance.isSupported) return;
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  void _refresh() {
    ClashSystemProxyService.instance
        .isEnabled()
        .then((value) {
          if (mounted) setState(() => _enabled = value);
        })
        .catchError((_) {
          if (mounted) setState(() => _enabled = null);
        });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _enabled;
    if (enabled == null) return const SizedBox.shrink();
    final color = enabled
        ? const Color(0xFF30D158)
        : _menuBarForeground(context, alpha: 0.45);

    return ContextMenu(
      items: [
        if (widget.onOpenApp != null)
          MenuButton(
            onPressed: (context) => widget.onOpenApp!('/clash'),
            child: const Text('打开 Clash'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Icon(LucideIcons.shield, size: 14, color: color),
      ),
    );
  }
}

/// Menu bar switch between comfortable and compact UI density.
class _DensityToggleButton extends StatelessWidget {
  const _DensityToggleButton();

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final compact = NexusDensityController.isCompact;
      return IconButton.ghost(
        icon: Icon(
          LucideIcons.rows3,
          size: 16,
          color: _menuBarForeground(context, alpha: compact ? 1 : 0.55),
        ),
        onPressed: () => NexusDensityController.toggle(),
      );
    });
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
        Icon(_iconForCode(weather.weatherCode), size: 14, color: foreground),
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
  /// Fixed cell height for every desktop icon so that long labels (up to 2
  /// lines) do not push subsequent icons out of alignment within a column.
  /// 48 (icon) + 6 (gap) + 2 lines * 11px * 1.2 height factor ≈ 80.4.
  static const double _desktopIconCellHeight = 81;

  const _DesktopIcon({
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
      height: _desktopIconCellHeight,
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
          height: _desktopIconCellHeight,
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
            color: isDark
                ? const Color(0xFFFFFFFF)
                : const Color(0xFF000000).withValues(alpha: 0.9),
            fontSize: 11,
            fontWeight: FontWeight.w500,
            height: 1.2,
            shadows: [
              Shadow(
                color: isDark
                    ? const Color(0x73000000)
                    : const Color(0x89FFFFFF),
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

/// Miniature preview of a folder's contents shown inside the desktop folder
/// icon: up to 4 app squircles in a 2x2 grid, or a folder glyph when empty.
class DesktopFolderPreview extends StatelessWidget {
  const DesktopFolderPreview({super.key, required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final folderItems = DesktopState.instance.getFolderItems(folderId);
      final previews = folderItems
          .map(
            (item) =>
                item.appRoute == null ? null : _resolveAppItem(item.appRoute!),
          )
          .whereType<DesktopAppItem>()
          .take(4)
          .toList();
      if (previews.isEmpty) {
        return Icon(
          LucideIcons.folder,
          size: 22,
          color: Theme.of(context).colorScheme.mutedForeground,
        );
      }
      return Padding(
        padding: const EdgeInsets.all(5),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final app in previews)
              Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [app.gradientStart, app.gradientEnd],
                  ),
                ),
                child: Icon(app.icon, size: 9, color: const Color(0xFFFFFFFF)),
              ),
          ],
        ),
      );
    });
  }
}

/// Registers the element context of a folder icon for drop-target hit tests.
///
/// The reorderable grid reuses the same child widget instance inside the drag
/// feedback (inflated in the overlay), so a GlobalKey here would collide with
/// itself. Instead, the folder icon's element context is written into
/// [registry] during build. Registration is skipped while a drag is active so
/// the feedback copy never overwrites the real grid entry.
class _FolderHitTarget extends StatefulWidget {
  const _FolderHitTarget({
    required this.registry,
    required this.folderId,
    required this.canRegister,
    required this.child,
  });

  final Map<String, BuildContext> registry;
  final String folderId;

  /// Runtime check evaluated during build. Must be a callback (not a plain
  /// bool) because the grid reuses the same widget instance inside the drag
  /// feedback — a snapshot bool would have been captured before the drag
  /// started and let the feedback copy overwrite the real registration.
  final bool Function() canRegister;
  final Widget child;

  @override
  State<_FolderHitTarget> createState() => _FolderHitTargetState();
}

class _FolderHitTargetState extends State<_FolderHitTarget> {
  @override
  Widget build(BuildContext context) {
    if (widget.canRegister()) {
      widget.registry[widget.folderId] = context;
    }
    return widget.child;
  }

  @override
  void dispose() {
    // Only clear if we are still the registered element (never the case for
    // a feedback copy, which never registers).
    if (widget.registry[widget.folderId] == context) {
      widget.registry.remove(widget.folderId);
    }
    super.dispose();
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
    // Fixed layout slot; hover scaling uses AnimatedScale so neighbours
    // never shift (the macOS feel without layout jitter).
    return SizedBox(
      width: 56,
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
                  MenuButton(onPressed: (context) {}, child: const Text('选项')),
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
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeOut,
                      scale: _isHovering ? 1.16 : 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(48 * 0.23),
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
                          size: 48,
                          child: Icon(widget.icon, size: 24),
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
              bottom: 60, // icon height + dot area + gap
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
              bottom: 86,
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
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.2),
        ),
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
