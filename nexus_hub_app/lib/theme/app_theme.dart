import 'package:flutter/material.dart';

import 'colors.dart';
import 'radii.dart';
import 'spacing.dart';
import 'typography.dart';

/// Builds the Material 3 theme for Nexus Hub.
class NexusAppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: NexusColors.primary,
      brightness: Brightness.light,
      surface: NexusColors.surface,
      onSurface: NexusColors.onSurface,
      surfaceContainerLowest: NexusColors.surfaceContainerLowest,
      surfaceContainerLow: NexusColors.surfaceContainerLow,
      surfaceContainer: NexusColors.surfaceContainer,
      surfaceContainerHigh: NexusColors.surfaceContainerHigh,
      surfaceContainerHighest: NexusColors.surfaceContainerHighest,
      primary: NexusColors.primary,
      onPrimary: NexusColors.onPrimary,
      secondary: NexusColors.secondary,
      onSecondary: NexusColors.onSecondary,
      tertiary: NexusColors.tertiary,
      onTertiary: NexusColors.onTertiary,
      error: NexusColors.error,
      onError: NexusColors.onError,
      outline: NexusColors.outline,
      outlineVariant: NexusColors.outlineVariant,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: NexusColors.background,
      fontFamily: 'Inter',
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: NexusColors.background,
        titleTextStyle: NexusTypography.headlineSm,
      ),
      cardTheme: CardThemeData(
        color: NexusColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: NexusRadii.mdRadius),
      ),
      dividerTheme: const DividerThemeData(
        color: NexusColors.outlineVariant,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: NexusColors.surfaceContainerLow,
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
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NexusRadii.mdRadius,
          borderSide: const BorderSide(color: NexusColors.outline),
        ),
      ),
      iconTheme: const IconThemeData(color: NexusColors.onSurfaceVariant),
      textTheme: TextTheme(
        headlineLarge: NexusTypography.headlineXl,
        headlineMedium: NexusTypography.headlineLg,
        headlineSmall: NexusTypography.headlineSm,
        bodyLarge: NexusTypography.bodyLg,
        bodyMedium: NexusTypography.bodyMd,
        labelMedium: NexusTypography.labelMd,
        labelSmall: NexusTypography.labelSm,
      ),
    );
  }
}
