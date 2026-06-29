# Nexus Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter desktop/web productivity hub matching the Nexus Hub design system, with a Dart Frog backend and SQLite persistence.

**Architecture:** Monorepo containing `nexus_hub_app/` (Flutter + signals + go_router + dio + sqflite) and `nexus_hub_api/` (dart_frog + sqlite + dio). Shared data models live in the frontend `data/` layer and backend `models/` layer. The UI uses a consistent shell (`ShellRoute`) with sidebar, top bar, and responsive content area.

**Tech Stack:** Flutter 3.41, Dart 3.11, signals, go_router, dio, sqflite, dart_frog, sqlite3, very_good_analysis.

---

## File Structure

```
myhub/
├── Design/                          # Source design assets (read-only)
├── docs/superpowers/plans/          # This plan
├── nexus_hub_app/                   # Flutter frontend
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── router.dart
│   │   ├── theme/
│   │   │   ├── colors.dart
│   │   │   ├── typography.dart
│   │   │   ├── radii.dart
│   │   │   ├── spacing.dart
│   │   │   └── app_theme.dart
│   │   ├── core/
│   │   │   ├── constants.dart
│   │   │   ├── extensions/
│   │   │   └── widgets/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   ├── database/
│   │   │   └── providers/
│   │   ├── services/
│   │   │   ├── api_client.dart
│   │   │   └── clipboard_service.dart
│   │   ├── state/
│   │   │   ├── app_state.dart
│   │   │   ├── bookmarks_state.dart
│   │   │   ├── tasks_state.dart
│   │   │   └── chat_state.dart
│   │   ├── presentation/
│   │   │   ├── layout/
│   │   │   │   ├── app_shell.dart
│   │   │   │   ├── side_navigation.dart
│   │   │   │   ├── top_app_bar.dart
│   │   │   │   └── page_scaffold.dart
│   │   │   ├── components/
│   │   │   │   ├── nexus_card.dart
│   │   │   │   ├── nexus_button.dart
│   │   │   │   ├── nexus_input.dart
│   │   │   │   ├── nexus_chip.dart
│   │   │   │   ├── nexus_badge.dart
│   │   │   │   ├── nexus_avatar.dart
│   │   │   │   └── nexus_icon.dart
│   │   │   └── pages/
│   │   │       ├── dashboard_page.dart
│   │   │       ├── bookmarks_page.dart
│   │   │       ├── tasks_page.dart
│   │   │       ├── ai_chat_page.dart
│   │   │       ├── clipboard_history_page.dart
│   │   │       ├── dev_tools_page.dart
│   │   │       ├── my_computer_page.dart
│   │   │       ├── rss_reader_page.dart
│   │   │       └── stocks_page.dart
│   │   └── utils/
│   ├── test/
│   │   ├── widget/
│   │   └── unit/
│   ├── pubspec.yaml
│   └── analysis_options.yaml
├── nexus_hub_api/                   # Dart Frog backend
│   ├── routes/
│   │   ├── index.dart
│   │   ├── bookmarks/
│   │   │   ├── index.dart
│   │   │   └── [id].dart
│   │   ├── tasks/
│   │   │   ├── index.dart
│   │   │   └── [id].dart
│   │   ├── clipboard/
│   │   │   ├── index.dart
│   │   │   └── [id].dart
│   │   └── health.dart
│   ├── lib/
│   │   ├── database.dart
│   │   ├── models/
│   │   └── services/
│   ├── test/
│   ├── pubspec.yaml
│   └── analysis_options.yaml
└── README.md
```

---

## Task 1: Initialize Projects

**Files:**
- Create: `nexus_hub_app/pubspec.yaml`
- Create: `nexus_hub_app/analysis_options.yaml`
- Create: `nexus_hub_api/pubspec.yaml`
- Create: `nexus_hub_api/analysis_options.yaml`
- Create: `README.md`

- [ ] **Step 1: Create Flutter project files**

```yaml
# nexus_hub_app/pubspec.yaml
name: nexus_hub_app
description: Nexus Hub Flutter frontend
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.11.0

dependencies:
  flutter:
    sdk: flutter
  signals_flutter: ^6.1.4
  go_router: ^14.8.1
  dio: ^5.8.0+1
  sqflite: ^2.4.2
  sqflite_common_ffi: ^2.3.5
  path: ^1.9.1
  path_provider: ^2.1.5
  intl: ^0.20.2
  shimmer: ^3.0.0
  flutter_svg: ^2.0.17
  google_fonts: ^6.2.1
  lucide_icons_flutter: ^2.0.1
  equatable: ^2.0.7
  json_annotation: ^4.9.0
  url_launcher: ^6.3.1

flutter:
  uses-material-design: true
  assets:
    - assets/images/
```

- [ ] **Step 2: Create Dart Frog project files**

```yaml
# nexus_hub_api/pubspec.yaml
name: nexus_hub_api
description: Nexus Hub Dart Frog backend
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.11.0

dependencies:
  dart_frog: ^1.2.0
  sqlite3: ^2.7.5
  dio: ^5.8.0+1
  shelf_cors_headers: ^0.1.0

dev_dependencies:
  mocktail: ^1.0.4
  test: ^1.25.15
  very_good_analysis: ^7.0.0
```

- [ ] **Step 3: Install dependencies**

Run:
```bash
cd nexus_hub_app && flutter pub get
cd ../nexus_hub_api && dart pub get
```

Expected: dependencies resolved successfully.

---

## Task 2: Implement Design System

**Files:**
- Create: `nexus_hub_app/lib/theme/colors.dart`
- Create: `nexus_hub_app/lib/theme/typography.dart`
- Create: `nexus_hub_app/lib/theme/radii.dart`
- Create: `nexus_hub_app/lib/theme/spacing.dart`
- Create: `nexus_hub_app/lib/theme/app_theme.dart`

- [ ] **Step 1: Define colors**

```dart
import 'package:flutter/material.dart';

abstract final class NexusColors {
  static const Color surface = Color(0xFFF8F9FF);
  static const Color surfaceDim = Color(0xFFCBDBF5);
  static const Color surfaceBright = Color(0xFFF8F9FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFEFF4FF);
  static const Color surfaceContainer = Color(0xFFE5EEFF);
  static const Color surfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color surfaceContainerHighest = Color(0xFFD3E4FE);
  static const Color onSurface = Color(0xFF0B1C30);
  static const Color onSurfaceVariant = Color(0xFF45464D);
  static const Color inverseSurface = Color(0xFF213145);
  static const Color inverseOnSurface = Color(0xFFEAF1FF);
  static const Color outline = Color(0xFF76777D);
  static const Color outlineVariant = Color(0xFFC6C6CD);
  static const Color surfaceTint = Color(0xFF565E74);
  static const Color primary = Color(0xFF000000);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF131B2E);
  static const Color onPrimaryContainer = Color(0xFF7C839B);
  static const Color inversePrimary = Color(0xFFBEC6E0);
  static const Color secondary = Color(0xFF0058BE);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFF2170E4);
  static const Color onSecondaryContainer = Color(0xFFFEFCFF);
  static const Color tertiary = Color(0xFF000000);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF171C1F);
  static const Color onTertiaryContainer = Color(0xFF808488);
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);
  static const Color primaryFixed = Color(0xFFDAE2FD);
  static const Color primaryFixedDim = Color(0xFFBEC6E0);
  static const Color onPrimaryFixed = Color(0xFF131B2E);
  static const Color onPrimaryFixedVariant = Color(0xFF3F465C);
  static const Color secondaryFixed = Color(0xFFD8E2FF);
  static const Color secondaryFixedDim = Color(0xFFADC6FF);
  static const Color onSecondaryFixed = Color(0xFF001A42);
  static const Color onSecondaryFixedVariant = Color(0xFF004395);
  static const Color tertiaryFixed = Color(0xFFDFE3E7);
  static const Color tertiaryFixedDim = Color(0xFFC3C7CB);
  static const Color onTertiaryFixed = Color(0xFF171C1F);
  static const Color onTertiaryFixedVariant = Color(0xFF43474B);
  static const Color background = Color(0xFFF8F9FF);
  static const Color onBackground = Color(0xFF0B1C30);
  static const Color surfaceVariant = Color(0xFFD3E4FE);
  static const Color stockUp = Color(0xFF10B981);
  static const Color stockDown = Color(0xFFEF4444);
}
```

- [ ] **Step 2: Define typography, radii, spacing, and theme**

See implementation files for full definitions.

---

## Task 3: Shared Layout Components

**Files:**
- Create: `nexus_hub_app/lib/presentation/layout/app_shell.dart`
- Create: `nexus_hub_app/lib/presentation/layout/side_navigation.dart`
- Create: `nexus_hub_app/lib/presentation/layout/top_app_bar.dart`
- Create: `nexus_hub_app/lib/presentation/layout/page_scaffold.dart`

- [ ] **Step 1: Implement SideNavigation with route-aware active state**

Active route uses `secondaryContainer` background and filled icon. Inactive routes use `onSurfaceVariant` with hover background `surfaceContainerHigh`.

- [ ] **Step 2: Implement TopAppBar with search and actions**

Search input uses rounded full border with `⌘K` hint. Notification and settings icons included.

- [ ] **Step 3: Implement AppShell using ShellRoute**

Wraps all pages with sidebar and top bar. Content area scrolls independently.

---

## Task 4: Routing

**Files:**
- Create: `nexus_hub_app/lib/router.dart`
- Modify: `nexus_hub_app/lib/app.dart`

- [ ] **Step 1: Define routes**

```dart
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardPage()),
        GoRoute(path: '/bookmarks', builder: (_, __) => const BookmarksPage()),
        GoRoute(path: '/tasks', builder: (_, __) => const TasksPage()),
        GoRoute(path: '/ai-chat', builder: (_, __) => const AiChatPage()),
        GoRoute(path: '/clipboard', builder: (_, __) => const ClipboardHistoryPage()),
        GoRoute(path: '/dev-tools', builder: (_, __) => const DevToolsPage()),
        GoRoute(path: '/my-computer', builder: (_, __) => const MyComputerPage()),
        GoRoute(path: '/rss', builder: (_, __) => const RssReaderPage()),
        GoRoute(path: '/stocks', builder: (_, __) => const StocksPage()),
      ],
    ),
  ],
);
```

---

## Task 5: Core Component Library

**Files:**
- Create: `nexus_hub_app/lib/presentation/components/nexus_card.dart`
- Create: `nexus_hub_app/lib/presentation/components/nexus_button.dart`
- Create: `nexus_hub_app/lib/presentation/components/nexus_input.dart`
- Create: `nexus_hub_app/lib/presentation/components/nexus_chip.dart`
- Create: `nexus_hub_app/lib/presentation/components/nexus_badge.dart`
- Create: `nexus_hub_app/lib/presentation/components/nexus_avatar.dart`
- Create: `nexus_hub_app/lib/presentation/components/nexus_icon.dart`

---

## Task 6: Data Layer & State Management

**Files:**
- Create: `nexus_hub_app/lib/data/models/bookmark.dart`
- Create: `nexus_hub_app/lib/data/models/task.dart`
- Create: `nexus_hub_app/lib/data/models/clipboard_item.dart`
- Create: `nexus_hub_app/lib/data/database/app_database.dart`
- Create: `nexus_hub_app/lib/state/bookmarks_state.dart`
- Create: `nexus_hub_app/lib/state/tasks_state.dart`
- Create: `nexus_hub_app/lib/services/api_client.dart`

- [ ] **Step 1: Define models with JSON serialization**

- [ ] **Step 2: Implement SQLite database helper with migrations**

- [ ] **Step 3: Implement Signals-based state classes**

---

## Task 7: Page Implementation

Implement each page to match design 1:1. Use design tokens. Add responsive grid behavior. Pages include:
- DashboardPage
- BookmarksPage + NewBookmarkDialog
- TasksPage + NewTaskDialog
- AiChatPage
- ClipboardHistoryPage
- DevToolsPage
- MyComputerPage
- RssReaderPage
- StocksPage

---

## Task 8: Backend

**Files:**
- Create: `nexus_hub_api/lib/database.dart`
- Create: `nexus_hub_api/routes/bookmarks/index.dart`
- Create: `nexus_hub_api/routes/bookmarks/[id].dart`
- Create: `nexus_hub_api/routes/tasks/index.dart`
- Create: `nexus_hub_api/routes/tasks/[id].dart`
- Create: `nexus_hub_api/routes/clipboard/index.dart`
- Create: `nexus_hub_api/routes/health.dart`

- [ ] **Step 1: Configure SQLite database and migrations**

- [ ] **Step 2: Implement REST endpoints**

- [ ] **Step 3: Wire API client in frontend**

---

## Task 9: Testing & Quality

- [ ] Write widget tests for core components.
- [ ] Write unit tests for state classes and database operations.
- [ ] Run `flutter analyze` and `dart analyze`.
- [ ] Document run instructions in README.md.
