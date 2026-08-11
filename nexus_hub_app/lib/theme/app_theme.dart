import 'package:flutter/material.dart';

import 'colors.dart';
import 'radii.dart';
import 'spacing.dart';
import 'typography.dart';

/// Builds the Material 3 theme for Nexus Hub.
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
      secondary:
          isDark ? NexusColors.secondaryDark : NexusColors.secondaryLight,
      onSecondary:
          isDark ? NexusColors.onSecondaryDark : NexusColors.onSecondaryLight,
      tertiary: isDark ? NexusColors.tertiaryDark : NexusColors.tertiaryLight,
      onTertiary:
          isDark ? NexusColors.onTertiaryDark : NexusColors.onTertiaryLight,
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
