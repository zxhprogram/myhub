# Nexus Hub UI 美化实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不影响业务功能的前提下，为 Nexus Hub 引入 Light/Dark/Auto 主题，并统一优化全局 Shell 与所有页面的视觉质感。

**Architecture:** 以 Flutter `ThemeData` / `ColorScheme` 为核心，新增 `ThemeState` 持久化主题偏好；通过 `NexusColors.light` / `NexusColors.dark` 两套静态色板替换硬编码颜色；优先改造共享组件（卡片、按钮、输入框等），再逐层覆盖 Shell 与页面；所有改动保持现有 API 兼容。

**Tech Stack:** Flutter, Material 3, shadcn_flutter, shared_preferences, signals_flutter

---

## 文件结构

| 文件 | 责任 |
|------|------|
| `nexus_hub_app/lib/theme/colors.dart` | 定义 Light / Dark 两套色板；保留向后兼容的静态入口。 |
| `nexus_hub_app/lib/theme/app_theme.dart` | 生成 Light / Dark `ThemeData`。 |
| `nexus_hub_app/lib/theme/typography.dart` | 移除硬编码颜色，改为依赖 `ColorScheme`。 |
| `nexus_hub_app/lib/presentation/states/theme_state.dart` | 单例；持久化 `themeMode`；提供切换方法。 |
| `nexus_hub_app/lib/app.dart` | 接入 `darkTheme` / `themeMode`。 |
| `nexus_hub_app/lib/presentation/components/*.dart` | NexusCard / NexusButton / NexusInput / NexusChip / NexusBadge / NexusIcon 视觉升级。 |
| `nexus_hub_app/lib/presentation/layout/*.dart` | 桌面 Dock / 菜单栏 / 窗口、移动端导航栏主题化。 |
| `nexus_hub_app/lib/presentation/pages/*.dart` | 所有页面替换硬编码颜色、统一卡片/列表/空状态。 |

---

## Task 1: 主题系统基础

**Files:**
- Modify: `nexus_hub_app/lib/theme/colors.dart`
- Modify: `nexus_hub_app/lib/theme/typography.dart`
- Modify: `nexus_hub_app/lib/theme/app_theme.dart`
- Create: `nexus_hub_app/lib/presentation/states/theme_state.dart`
- Test: 新增 `nexus_hub_app/test/presentation/theme_state_test.dart`

### Step 1.1: 扩展色板

修改 `nexus_hub_app/lib/theme/colors.dart`，保留原有静态常量作为 Light 值，新增 Dark 常量与解析辅助：

```dart
import 'package:flutter/material.dart';

abstract final class NexusColors {
  // Light tokens
  static const Color surfaceLight = Color(0xFFF8F9FF);
  static const Color surfaceContainerLowestLight = Color(0xFFFFFFFF);
  static const Color surfaceContainerLowLight = Color(0xFFEFF4FF);
  static const Color surfaceContainerLight = Color(0xFFE5EEFF);
  static const Color surfaceContainerHighLight = Color(0xFFDCE9FF);
  static const Color surfaceContainerHighestLight = Color(0xFFD3E4FE);
  static const Color onSurfaceLight = Color(0xFF0B1C30);
  static const Color onSurfaceVariantLight = Color(0xFF45464D);
  static const Color inverseSurfaceLight = Color(0xFF213145);
  static const Color inverseOnSurfaceLight = Color(0xFFEAF1FF);
  static const Color outlineLight = Color(0xFF76777D);
  static const Color outlineVariantLight = Color(0xFFC6C6CD);
  static const Color primaryLight = Color(0xFF000000);
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color secondaryLight = Color(0xFF0058BE);
  static const Color onSecondaryLight = Color(0xFFFFFFFF);
  static const Color errorLight = Color(0xFFBA1A1A);
  static const Color onErrorLight = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF8F9FF);

  // Dark tokens
  static const Color surfaceDark = Color(0xFF151B2E);
  static const Color surfaceContainerLowestDark = Color(0xFF0B1020);
  static const Color surfaceContainerLowDark = Color(0xFF1B2238);
  static const Color surfaceContainerDark = Color(0xFF232B45);
  static const Color surfaceContainerHighDark = Color(0xFF2C3654);
  static const Color surfaceContainerHighestDark = Color(0xFF36405E);
  static const Color onSurfaceDark = Color(0xFFEAF1FF);
  static const Color onSurfaceVariantDark = Color(0xFF9AA3B8);
  static const Color inverseSurfaceDark = Color(0xFFEAF1FF);
  static const Color inverseOnSurfaceDark = Color(0xFF0B1C30);
  static const Color outlineDark = Color(0xFF6B7280);
  static const Color outlineVariantDark = Color(0xFF2E3A57);
  static const Color primaryDark = Color(0xFFFFFFFF);
  static const Color onPrimaryDark = Color(0xFF000000);
  static const Color secondaryDark = Color(0xFF4A9EFF);
  static const Color onSecondaryDark = Color(0xFF000000);
  static const Color errorDark = Color(0xFFFF6B6B);
  static const Color onErrorDark = Color(0xFF000000);
  static const Color backgroundDark = Color(0xFF0B1020);

  // Backwards-compatible aliases defaulting to light
  static const Color surface = surfaceLight;
  static const Color surfaceContainerLowest = surfaceContainerLowestLight;
  static const Color surfaceContainerLow = surfaceContainerLowLight;
  static const Color surfaceContainer = surfaceContainerLight;
  static const Color surfaceContainerHigh = surfaceContainerHighLight;
  static const Color surfaceContainerHighest = surfaceContainerHighestLight;
  static const Color onSurface = onSurfaceLight;
  static const Color onSurfaceVariant = onSurfaceVariantLight;
  static const Color inverseSurface = inverseSurfaceLight;
  static const Color inverseOnSurface = inverseOnSurfaceLight;
  static const Color outline = outlineLight;
  static const Color outlineVariant = outlineVariantLight;
  static const Color primary = primaryLight;
  static const Color onPrimary = onPrimaryLight;
  static const Color secondary = secondaryLight;
  static const Color onSecondary = onSecondaryLight;
  static const Color error = errorLight;
  static const Color onError = onErrorLight;
  static const Color background = backgroundLight;

  // Semantic colors remain identical for both themes
  static const Color stockUp = Color(0xFF10B981);
  static const Color stockDown = Color(0xFFEF4444);

  /// Resolves theme-aware color from a `BuildContext`.
  static ColorScheme schemeOf(BuildContext context) {
    return Theme.of(context).colorScheme;
  }
}
```

### Step 1.2: Typography 去硬编码

修改 `nexus_hub_app/lib/theme/typography.dart`，移除 `color` 硬编码，由调用方通过 `ColorScheme` 设置：

```dart
import 'package:flutter/material.dart';

abstract final class NexusTypography {
  static const _fontFamily = 'Microsoft YaHei';

  static const TextStyle headlineXl = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 36 / 30,
    letterSpacing: -0.02 * 30,
  );

  static const TextStyle headlineLg = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    letterSpacing: -0.02 * 24,
  );

  static const TextStyle headlineSm = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 28 / 18,
    letterSpacing: -0.01 * 18,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: -0.01 * 16,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: -0.01 * 14,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    letterSpacing: 0.01 * 12,
  );

  static const TextStyle labelSm = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 14 / 11,
    letterSpacing: 0.05 * 11,
  );
}
```

### Step 1.3: AppTheme 支持 Dark

修改 `nexus_hub_app/lib/theme/app_theme.dart`：

```dart
import 'package:flutter/material.dart';

import 'colors.dart';
import 'radii.dart';
import 'spacing.dart';
import 'typography.dart';

class NexusAppTheme {
  static ThemeData _buildTheme({required Brightness brightness}) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NexusColors.secondary,
      brightness: brightness,
      surface: isDark ? NexusColors.surfaceDark : NexusColors.surfaceLight,
      onSurface: isDark ? NexusColors.onSurfaceDark : NexusColors.onSurfaceLight,
      surfaceContainerLowest: isDark
          ? NexusColors.surfaceContainerLowestDark
          : NexusColors.surfaceContainerLowestLight,
      surfaceContainerLow: isDark
          ? NexusColors.surfaceContainerLowDark
          : NexusColors.surfaceContainerLowLight,
      surfaceContainer: isDark
          ? NexusColors.surfaceContainerDark
          : NexusColors.surfaceContainerLight,
      surfaceContainerHigh: isDark
          ? NexusColors.surfaceContainerHighDark
          : NexusColors.surfaceContainerHighLight,
      surfaceContainerHighest: isDark
          ? NexusColors.surfaceContainerHighestDark
          : NexusColors.surfaceContainerHighestLight,
      primary: isDark ? NexusColors.primaryDark : NexusColors.primaryLight,
      onPrimary: isDark ? NexusColors.onPrimaryDark : NexusColors.onPrimaryLight,
      secondary: isDark ? NexusColors.secondaryDark : NexusColors.secondaryLight,
      onSecondary:
          isDark ? NexusColors.onSecondaryDark : NexusColors.onSecondaryLight,
      error: isDark ? NexusColors.errorDark : NexusColors.errorLight,
      onError: isDark ? NexusColors.onErrorDark : NexusColors.onErrorLight,
      outline: isDark ? NexusColors.outlineDark : NexusColors.outlineLight,
      outlineVariant:
          isDark ? NexusColors.outlineVariantDark : NexusColors.outlineVariantLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? NexusColors.backgroundDark : NexusColors.backgroundLight,
      fontFamily: 'Microsoft YaHei',
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? NexusColors.backgroundDark : NexusColors.backgroundLight,
        titleTextStyle: NexusTypography.headlineSm.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: NexusRadii.mdRadius),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? Colors.transparent
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: BorderSide(color: colorScheme.secondary),
        ),
      ),
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      textTheme: TextTheme(
        headlineLarge: NexusTypography.headlineXl.copyWith(
          color: colorScheme.onSurface,
        ),
        headlineMedium: NexusTypography.headlineLg.copyWith(
          color: colorScheme.onSurface,
        ),
        headlineSmall: NexusTypography.headlineSm.copyWith(
          color: colorScheme.onSurface,
        ),
        bodyLarge: NexusTypography.bodyLg.copyWith(
          color: colorScheme.onSurface,
        ),
        bodyMedium: NexusTypography.bodyMd.copyWith(
          color: colorScheme.onSurface,
        ),
        labelMedium: NexusTypography.labelMd.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        labelSmall: NexusTypography.labelSm.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static ThemeData light() => _buildTheme(brightness: Brightness.light);
  static ThemeData dark() => _buildTheme(brightness: Brightness.dark);
}
```

### Step 1.4: 创建 ThemeState

创建 `nexus_hub_app/lib/presentation/states/theme_state.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

class ThemeState {
  ThemeState._();

  static final ThemeState instance = ThemeState._();

  static const _storageKey = 'nexus_theme_mode_v1';

  final themeMode = signal<ThemeMode>(ThemeMode.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    themeMode.value = _parse(raw);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, mode.name);
  }

  Future<void> toggle() async {
    final next = switch (themeMode.value) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    await setThemeMode(next);
  }

  static ThemeMode _parse(String? value) {
    return ThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ThemeMode.system,
    );
  }
}
```

### Step 1.5: 测试 ThemeState

创建 `nexus_hub_app/test/presentation/theme_state_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub/presentation/states/theme_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ThemeState.instance.init();
  });

  test('defaults to system', () {
    expect(ThemeState.instance.themeMode.value, ThemeMode.system);
  });

  test('setThemeMode persists and updates signal', () async {
    await ThemeState.instance.setThemeMode(ThemeMode.dark);
    expect(ThemeState.instance.themeMode.value, ThemeMode.dark);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('nexus_theme_mode_v1'), 'dark');
  });

  test('toggle cycles through modes', () async {
    ThemeState.instance.themeMode.value = ThemeMode.light;
    await ThemeState.instance.toggle();
    expect(ThemeState.instance.themeMode.value, ThemeMode.dark);
  });
}
```

运行测试：

```bash
cd /workspace/nexus_hub_app
flutter test test/presentation/theme_state_test.dart
```

Expected: all pass.

### Step 1.6: Commit

```bash
cd /workspace/nexus_hub_app
git add lib/theme/colors.dart lib/theme/typography.dart lib/theme/app_theme.dart \
  lib/presentation/states/theme_state.dart test/presentation/theme_state_test.dart
git commit -m "feat(theme): add light/dark color schemes and theme state"
```

---

## Task 2: 应用入口接入主题

**Files:**
- Modify: `nexus_hub_app/lib/app.dart`
- Modify: `nexus_hub_app/lib/presentation/layout/desktop_environment.dart`
- Modify: `nexus_hub_app/lib/main.dart`

### Step 2.1: app.dart 支持 themeMode

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'presentation/states/theme_state.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class NexusHubApp extends StatelessWidget {
  const NexusHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      return MaterialApp.router(
        title: 'Nexus Hub',
        debugShowCheckedModeBanner: false,
        theme: NexusAppTheme.light(),
        darkTheme: NexusAppTheme.dark(),
        themeMode: ThemeState.instance.themeMode.value,
        routerConfig: AppRouter.router,
        localizationsDelegates: const [
          FlutterQuillLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', 'US')],
      );
    });
  }
}
```

### Step 2.2: main.dart 初始化 ThemeState

在 `main.dart` 的 `runApp` 前调用：

```dart
await ThemeState.instance.init();
```

### Step 2.3: 桌面环境初始化 ThemeState

`DesktopEnvironment.initState` 已调用 `WallpaperState.instance.init()` 和 `PomodoroState.instance.init()`，追加：

```dart
ThemeState.instance.init();
```

### Step 2.4: Commit

```bash
git add lib/app.dart lib/main.dart lib/presentation/layout/desktop_environment.dart
git commit -m "feat(app): wire light/dark/auto themes into MaterialApp"
```

---

## Task 3: 组件库主题化

**Files:**
- Modify: `nexus_hub_app/lib/presentation/components/nexus_card.dart`
- Modify: `nexus_hub_app/lib/presentation/components/nexus_button.dart`
- Modify: `nexus_hub_app/lib/presentation/components/nexus_input.dart`
- Modify: `nexus_hub_app/lib/presentation/components/nexus_chip.dart`
- Modify: `nexus_hub_app/lib/presentation/components/nexus_badge.dart`
- Modify: `nexus_hub_app/lib/presentation/components/nexus_icon.dart`
- Modify: `nexus_hub_app/lib/presentation/components/nexus_avatar.dart`

### Step 3.1: NexusCard

```dart
import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';

class NexusCard extends StatelessWidget {
  const NexusCard({
    super.key,
    this.child,
    this.padding = const EdgeInsets.all(NexusSpacing.md),
    this.borderRadius = NexusRadii.xl,
    this.onTap,
  });

  final Widget? child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    Widget card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        hoverColor: colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        child: card,
      ),
    );
  }
}
```

### Step 3.2: NexusButton

```dart
import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

enum NexusButtonVariant { filled, tonal, outlined, text }

class NexusButton extends StatelessWidget {
  const NexusButton({
    super.key,
    required this.label,
    this.variant = NexusButtonVariant.filled,
    this.icon,
    this.isLoading = false,
    this.onPressed,
  });

  final String label;
  final NexusButtonVariant variant;
  final IconData? icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final foregroundColor = switch (variant) {
      NexusButtonVariant.filled => colorScheme.onPrimary,
      NexusButtonVariant.tonal => colorScheme.onSecondaryContainer,
      NexusButtonVariant.outlined || NexusButtonVariant.text => colorScheme.onSurface,
    };

    final backgroundColor = switch (variant) {
      NexusButtonVariant.filled => colorScheme.primary,
      NexusButtonVariant.tonal => colorScheme.secondaryContainer,
      NexusButtonVariant.outlined || NexusButtonVariant.text => Colors.transparent,
    };

    final border = variant == NexusButtonVariant.outlined
        ? Border.all(color: colorScheme.outlineVariant)
        : null;

    return Material(
      color: backgroundColor,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: NexusRadii.mdRadius,
        hoverColor: variant == NexusButtonVariant.filled
            ? colorScheme.primary.withValues(alpha: 0.85)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.md,
            vertical: NexusSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: border,
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                  ),
                )
              else if (icon != null)
                Icon(icon, size: 18, color: foregroundColor),
              if ((isLoading || icon != null) && label.isNotEmpty)
                const SizedBox(width: NexusSpacing.sm),
              if (label.isNotEmpty)
                Text(
                  label,
                  style: NexusTypography.labelMd.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Step 3.3: NexusInput

文件路径：`nexus_hub_app/lib/presentation/components/nexus_input.dart`

```dart
import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class NexusInput extends StatelessWidget {
  const NexusInput({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onSubmitted,
    this.obscureText = false,
    this.maxLines = 1,
    this.keyboardType,
  });

  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final String? errorText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscureText;
  final int? maxLines;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      obscureText: obscureText,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: NexusTypography.bodyMd.copyWith(color: colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        errorText: errorText,
        prefixIcon: prefixIcon != null
            ? Icon(prefixIcon, size: 18, color: colorScheme.onSurfaceVariant)
            : null,
        suffixIcon: suffixIcon != null
            ? Icon(suffixIcon, size: 18, color: colorScheme.onSurfaceVariant)
            : null,
        filled: true,
        fillColor: colorScheme.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: BorderSide(
            color: isDark
                ? Colors.transparent
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: BorderSide(color: colorScheme.secondary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: BorderSide(color: colorScheme.error),
        ),
        hintStyle: NexusTypography.bodyMd.copyWith(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
        labelStyle: NexusTypography.bodyMd.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
```

### Step 3.4: NexusChip

```dart
import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

class NexusChip extends StatelessWidget {
  const NexusChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final background = selected
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainer;
    final foreground = selected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Material(
      color: background,
      borderRadius: NexusRadii.fullRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.fullRadius,
        hoverColor: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: NexusTypography.labelMd.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Step 3.5: NexusBadge

```dart
import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/typography.dart';

class NexusBadge extends StatelessWidget {
  const NexusBadge({super.key, required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? colorScheme.secondaryContainer;
    final foreground = color != null
        ? Colors.white
        : colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        label,
        style: NexusTypography.labelSm.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

### Step 3.6: NexusIcon

```dart
import 'package:flutter/material.dart';

enum NexusIconSize { small, medium, large }

class NexusIcon extends StatelessWidget {
  const NexusIcon({
    super.key,
    required this.icon,
    this.size = NexusIconSize.medium,
    this.color,
    this.active = false,
  });

  final IconData icon;
  final NexusIconSize size;
  final Color? color;
  final bool active;

  double get _size => switch (size) {
        NexusIconSize.small => 16,
        NexusIconSize.medium => 20,
        NexusIconSize.large => 24,
      };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = color ??
        (active ? colorScheme.onSurface : colorScheme.onSurfaceVariant);

    return Icon(icon, size: _size, color: effectiveColor);
  }
}
```

### Step 3.7: NexusAvatar

保留 API，仅使用 `ColorScheme`：

```dart
import 'package:flutter/material.dart';

import '../../theme/radii.dart';
import '../../theme/typography.dart';

class NexusAvatar extends StatelessWidget {
  const NexusAvatar({super.key, required this.label, this.size = 32});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: NexusRadii.fullRadius,
      ),
      alignment: Alignment.center,
      child: Text(
        label.isNotEmpty ? label[0].toUpperCase() : '?',
        style: NexusTypography.labelMd.copyWith(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

### Step 3.8: 运行分析

```bash
cd /workspace/nexus_hub_app
flutter analyze
```

Expected: no new errors.

### Step 3.9: Commit

```bash
git add lib/presentation/components/nexus_card.dart \
  lib/presentation/components/nexus_button.dart \
  lib/presentation/components/nexus_input.dart \
  lib/presentation/components/nexus_chip.dart \
  lib/presentation/components/nexus_badge.dart \
  lib/presentation/components/nexus_icon.dart \
  lib/presentation/components/nexus_avatar.dart
git commit -m "feat(components): theme-aware cards, buttons, inputs, chips, badges, icons"
```

---

## Task 4: 全局 Shell 主题化

**Files:**
- Modify: `nexus_hub_app/lib/presentation/layout/desktop_environment.dart`
- Modify: `nexus_hub_app/lib/presentation/layout/app_shell.dart`
- Modify: `nexus_hub_app/lib/presentation/layout/top_app_bar.dart`
- Modify: `nexus_hub_app/lib/presentation/layout/side_navigation.dart`

### Step 4.1: DesktopEnvironment 主题化

关键改动点（不改动窗口管理逻辑）：

1. `_buildGradientBackground` 使用主题色：

```dart
Widget _buildGradientBackground(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = colorScheme.brightness == Brightness.dark;

  return Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [
                const Color(0xFF1A1A2E),
                const Color(0xFF16213E),
                const Color(0xFF0F3460),
                const Color(0xFF533483),
              ]
            : [
                const Color(0xFFF0F4FF),
                const Color(0xFFE5EEFF),
                const Color(0xFFDCE9FF),
                const Color(0xFFD3E4FE),
              ],
      ),
    ),
  );
}
```

2. `_buildBackground` 在壁纸上方叠加主题遮罩：

```dart
Widget _buildBackground(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  return Watch((_) {
    final wallpaper = WallpaperState.instance.currentWallpaper.value;
    Widget base = wallpaper == null
        ? _buildGradientBackground(context)
        : Image.network(
            wallpaper.url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : _buildGradientBackground(context),
            errorBuilder: (context, error, stackTrace) =>
                _buildGradientBackground(context),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        base,
        Container(
          color: colorScheme.background.withValues(alpha: 0.35),
        ),
      ],
    );
  });
}
```

3. `_buildDock` 使用主题模糊背景：

```dart
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
            color: colorScheme.surface.withValues(alpha: 0.18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(...),
        ),
      ),
    ),
  );
}
```

4. `_MenuBar` 使用主题半透明背景，并增加主题切换按钮：

```dart
class _MenuBar extends StatelessWidget {
  const _MenuBar();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      height: 32,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.2),
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Row(...),
          const Spacer(),
          _MenuIconButton(
            icon: isDark ? Icons.dark_mode : Icons.light_mode,
            onTap: () => ThemeState.instance.toggle(),
          ),
          const SizedBox(width: 8),
          const _ClockWidget(),
        ],
      ),
    );
  }
}
```

5. 桌面图标与文件夹使用主题感知颜色：

- `_DesktopIcon._buildAppIcon` 文字颜色根据主题切换。
- `_DesktopIcon._buildFolderIcon` 背景使用 `colorScheme.surface` 透明度。

### Step 4.2: AppShell / TopAppBar / SideNavigation

- `AppShell` 的移动端底部导航背景从 `Colors.white` 改为 `colorScheme.surfaceContainerLowest`，边框 `outlineVariant`。
- `TopAppBar` 背景改为 `colorScheme.background`，图标使用 `colorScheme.onSurfaceVariant`。
- `SideNavigation` 背景改为 `colorScheme.surfaceContainerLow`，导航项选中背景 `surfaceContainerHighest`，悬停 `surfaceContainerHigh`。

### Step 4.3: Commit

```bash
git add lib/presentation/layout/desktop_environment.dart \
  lib/presentation/layout/app_shell.dart \
  lib/presentation/layout/top_app_bar.dart \
  lib/presentation/layout/side_navigation.dart
git commit -m "feat(shell): theme-aware dock, menu bar, windows, and mobile nav"
```

---

## Task 5: 页面主题化

**Files:**
- Modify: `nexus_hub_app/lib/presentation/pages/dashboard_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/tasks_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/bookmarks_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/clipboard_history_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/rss_reader_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/mail_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/ai_chat_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/stocks_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/my_computer_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/dev_tools_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/pomodoro_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/camera_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/calendar_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/terminal_page.dart`
- Modify: `nexus_hub_app/lib/presentation/pages/trending_page.dart`

### Step 5.1: 全局替换策略

对每页执行以下替换（使用 IDE 全局替换或手动）：

1. `NexusColors.surfaceContainerLowest` / `Colors.white` 卡片背景 → `Theme.of(context).colorScheme.surfaceContainerLowest`。
2. `NexusColors.background` → `Theme.of(context).colorScheme.background`。
3. `NexusColors.onSurface` → `Theme.of(context).colorScheme.onSurface`。
4. `NexusColors.onSurfaceVariant` → `Theme.of(context).colorScheme.onSurfaceVariant`。
5. `NexusColors.outlineVariant` → `Theme.of(context).colorScheme.outlineVariant`。
6. 硬编码的 `Color(0xFF...)` 背景/边框值，若未在 `NexusColors` 中定义，则映射到最接近的 ColorScheme token。
7. 文字样式从 `NexusTypography.xxx.copyWith(color: NexusColors.yyy)` 改为 `.copyWith(color: colorScheme.zzz)`。

### Step 5.2: DashboardPage 重点优化

- `_MetricCard` 使用 `NexusCard` 替代裸 `Container`，增加图标背景圆角。
- `_FocusChartCard` 的随机柱状图颜色使用 `ColorScheme` 的 secondary 系列。
- `_QuickActionsCard` 的按钮使用新版 `NexusButton`。

### Step 5.3: TasksPage / BookmarksPage / MailPage 重点优化

- 列表项悬停背景 `surfaceContainerLow`。
- 空状态使用统一 `_EmptyState` 组件：

```dart
class NexusEmptyState extends StatelessWidget {
  const NexusEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 32,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: NexusTypography.headlineSm.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}
```

### Step 5.4: 运行测试

```bash
cd /workspace/nexus_hub_app
flutter analyze
flutter test
```

Expected: analyze 无新增错误；现有测试通过。

### Step 5.5: Commit

```bash
git add lib/presentation/pages/
git commit -m "feat(pages): theme-aware visual polish across all screens"
```

---

## Task 6: 验证与收尾

**Files:**
- All modified files

### Step 6.1: 静态检查

```bash
cd /workspace/nexus_hub_app
flutter analyze
```

### Step 6.2: 运行全部测试

```bash
cd /workspace/nexus_hub_app
flutter test
```

### Step 6.3: 手动验证清单

- [ ] 桌面端：右键菜单、Dock 悬停、窗口打开/关闭/最小化正常。
- [ ] 桌面端：菜单栏主题切换按钮可在 Light / Dark / System 间循环。
- [ ] 移动端：底部导航、TopAppBar、所有页面在两种主题下正常显示。
- [ ] Dashboard、Tasks、Bookmarks、Mail 等核心页面无硬编码颜色残留。
- [ ] 深色模式下文字可读性良好，边框/分隔线可见。
- [ ] 主题模式重启后持久化。

### Step 6.4: 最终 Commit

```bash
git add -A
git commit -m "feat(ui): complete light/dark theme and visual polish"
```

---

## 自审检查

1. **Spec coverage:** 设计规范中的 Light/Dark/Auto、Dock、菜单栏、窗口、组件、页面、不动范围均有对应任务。
2. **Placeholder scan:** 无 TBD/TODO；每步均含文件路径与代码。
3. **Type consistency:** `ThemeState.themeMode` 为 `Signal<ThemeMode>`；`NexusAppTheme.light()` / `dark()` 均返回 `ThemeData`；组件统一通过 `Theme.of(context).colorScheme` 取色。
