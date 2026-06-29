import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'presentation/layout/app_shell.dart';
import 'presentation/pages/ai_chat_page.dart';
import 'presentation/pages/bookmarks_page.dart';
import 'presentation/pages/clipboard_history_page.dart';
import 'presentation/pages/dashboard_page.dart';
import 'presentation/pages/dev_tools_page.dart';
import 'presentation/pages/my_computer_page.dart';
import 'presentation/pages/rss_reader_page.dart';
import 'presentation/pages/stocks_page.dart';
import 'presentation/pages/tasks_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

class AppRouter {
  static GoRouter get router => GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: _guard,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(currentPath: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/bookmarks',
            builder: (context, state) => const BookmarksPage(),
          ),
          GoRoute(
            path: '/tasks',
            builder: (context, state) => const TasksPage(),
          ),
          GoRoute(
            path: '/clipboard',
            builder: (context, state) => const ClipboardHistoryPage(),
          ),
          GoRoute(
            path: '/rss',
            builder: (context, state) => const RssReaderPage(),
          ),
          GoRoute(
            path: '/ai-chat',
            builder: (context, state) => const AiChatPage(),
          ),
          GoRoute(
            path: '/stocks',
            builder: (context, state) => const StocksPage(),
          ),
          GoRoute(
            path: '/my-computer',
            builder: (context, state) => const MyComputerPage(),
          ),
          GoRoute(
            path: '/dev-tools',
            builder: (context, state) => const DevToolsPage(),
          ),
        ],
      ),
    ],
  );

  static String? _guard(BuildContext context, GoRouterState state) {
    // All routes are public in this iteration.
    return null;
  }
}
