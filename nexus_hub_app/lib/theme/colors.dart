import 'package:flutter/material.dart';

/// Nexus Hub design system colors.
///
/// Values are sourced from Design/nexus_hub/DESIGN.md.
/// Light tokens are kept as the default static values for backwards
/// compatibility. Use [NexusColors.schemeOf] to resolve theme-aware colors.
abstract final class NexusColors {
  // ------------------------------------------------------------------
  // Light tokens
  // ------------------------------------------------------------------
  static const Color surfaceLight = Color(0xFFF8F9FF);
  static const Color surfaceDimLight = Color(0xFFCBDBF5);
  static const Color surfaceBrightLight = Color(0xFFF8F9FF);
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
  static const Color surfaceTintLight = Color(0xFF565E74);

  static const Color primaryLight = Color(0xFF000000);
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color primaryContainerLight = Color(0xFF131B2E);
  static const Color onPrimaryContainerLight = Color(0xFF7C839B);
  static const Color inversePrimaryLight = Color(0xFFBEC6E0);

  static const Color secondaryLight = Color(0xFF0058BE);
  static const Color onSecondaryLight = Color(0xFFFFFFFF);
  static const Color secondaryContainerLight = Color(0xFF2170E4);
  static const Color onSecondaryContainerLight = Color(0xFFFEFCFF);

  static const Color tertiaryLight = Color(0xFF000000);
  static const Color onTertiaryLight = Color(0xFFFFFFFF);
  static const Color tertiaryContainerLight = Color(0xFF171C1F);
  static const Color onTertiaryContainerLight = Color(0xFF808488);

  static const Color errorLight = Color(0xFFBA1A1A);
  static const Color onErrorLight = Color(0xFFFFFFFF);
  static const Color errorContainerLight = Color(0xFFFFDAD6);
  static const Color onErrorContainerLight = Color(0xFF93000A);

  static const Color primaryFixedLight = Color(0xFFDAE2FD);
  static const Color primaryFixedDimLight = Color(0xFFBEC6E0);
  static const Color onPrimaryFixedLight = Color(0xFF131B2E);
  static const Color onPrimaryFixedVariantLight = Color(0xFF3F465C);

  static const Color secondaryFixedLight = Color(0xFFD8E2FF);
  static const Color secondaryFixedDimLight = Color(0xFFADC6FF);
  static const Color onSecondaryFixedLight = Color(0xFF001A42);
  static const Color onSecondaryFixedVariantLight = Color(0xFF004395);

  static const Color tertiaryFixedLight = Color(0xFFDFE3E7);
  static const Color tertiaryFixedDimLight = Color(0xFFC3C7CB);
  static const Color onTertiaryFixedLight = Color(0xFF171C1F);
  static const Color onTertiaryFixedVariantLight = Color(0xFF43474B);

  static const Color backgroundLight = Color(0xFFF8F9FF);
  static const Color onBackgroundLight = Color(0xFF0B1C30);
  static const Color surfaceVariantLight = Color(0xFFD3E4FE);

  // ------------------------------------------------------------------
  // Dark tokens
  // ------------------------------------------------------------------
  static const Color surfaceDark = Color(0xFF151B2E);
  static const Color surfaceDimDark = Color(0xFF0B1020);
  static const Color surfaceBrightDark = Color(0xFF1B2238);
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
  static const Color surfaceTintDark = Color(0xFF565E74);

  static const Color primaryDark = Color(0xFFFFFFFF);
  static const Color onPrimaryDark = Color(0xFF000000);
  static const Color primaryContainerDark = Color(0xFFEAF1FF);
  static const Color onPrimaryContainerDark = Color(0xFF0B1C30);
  static const Color inversePrimaryDark = Color(0xFF131B2E);

  static const Color secondaryDark = Color(0xFF4A9EFF);
  static const Color onSecondaryDark = Color(0xFF000000);
  static const Color secondaryContainerDark = Color(0xFF004395);
  static const Color onSecondaryContainerDark = Color(0xFFFEFCFF);

  static const Color tertiaryDark = Color(0xFFFFFFFF);
  static const Color onTertiaryDark = Color(0xFF000000);
  static const Color tertiaryContainerDark = Color(0xFFDFE3E7);
  static const Color onTertiaryContainerDark = Color(0xFF171C1F);

  static const Color errorDark = Color(0xFFFF6B6B);
  static const Color onErrorDark = Color(0xFF000000);
  static const Color errorContainerDark = Color(0xFF93000A);
  static const Color onErrorContainerDark = Color(0xFFFFDAD6);

  static const Color primaryFixedDark = Color(0xFF3F465C);
  static const Color primaryFixedDimDark = Color(0xFF131B2E);
  static const Color onPrimaryFixedDark = Color(0xFFDAE2FD);
  static const Color onPrimaryFixedVariantDark = Color(0xFFBEC6E0);

  static const Color secondaryFixedDark = Color(0xFF004395);
  static const Color secondaryFixedDimDark = Color(0xFF001A42);
  static const Color onSecondaryFixedDark = Color(0xFFD8E2FF);
  static const Color onSecondaryFixedVariantDark = Color(0xFFADC6FF);

  static const Color tertiaryFixedDark = Color(0xFF43474B);
  static const Color tertiaryFixedDimDark = Color(0xFF171C1F);
  static const Color onTertiaryFixedDark = Color(0xFFDFE3E7);
  static const Color onTertiaryFixedVariantDark = Color(0xFFC3C7CB);

  static const Color backgroundDark = Color(0xFF0B1020);
  static const Color onBackgroundDark = Color(0xFFEAF1FF);
  static const Color surfaceVariantDark = Color(0xFF232B45);

  // ------------------------------------------------------------------
  // Backwards-compatible static aliases (default to light)
  // ------------------------------------------------------------------
  static const Color surface = surfaceLight;
  static const Color surfaceDim = surfaceDimLight;
  static const Color surfaceBright = surfaceBrightLight;
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
  static const Color surfaceTint = surfaceTintLight;

  static const Color primary = primaryLight;
  static const Color onPrimary = onPrimaryLight;
  static const Color primaryContainer = primaryContainerLight;
  static const Color onPrimaryContainer = onPrimaryContainerLight;
  static const Color inversePrimary = inversePrimaryLight;

  static const Color secondary = secondaryLight;
  static const Color onSecondary = onSecondaryLight;
  static const Color secondaryContainer = secondaryContainerLight;
  static const Color onSecondaryContainer = onSecondaryContainerLight;

  static const Color tertiary = tertiaryLight;
  static const Color onTertiary = onTertiaryLight;
  static const Color tertiaryContainer = tertiaryContainerLight;
  static const Color onTertiaryContainer = onTertiaryContainerLight;

  static const Color error = errorLight;
  static const Color onError = onErrorLight;
  static const Color errorContainer = errorContainerLight;
  static const Color onErrorContainer = onErrorContainerLight;

  static const Color primaryFixed = primaryFixedLight;
  static const Color primaryFixedDim = primaryFixedDimLight;
  static const Color onPrimaryFixed = onPrimaryFixedLight;
  static const Color onPrimaryFixedVariant = onPrimaryFixedVariantLight;

  static const Color secondaryFixed = secondaryFixedLight;
  static const Color secondaryFixedDim = secondaryFixedDimLight;
  static const Color onSecondaryFixed = onSecondaryFixedLight;
  static const Color onSecondaryFixedVariant = onSecondaryFixedVariantLight;

  static const Color tertiaryFixed = tertiaryFixedLight;
  static const Color tertiaryFixedDim = tertiaryFixedDimLight;
  static const Color onTertiaryFixed = onTertiaryFixedLight;
  static const Color onTertiaryFixedVariant = onTertiaryFixedVariantLight;

  static const Color background = backgroundLight;
  static const Color onBackground = onBackgroundLight;
  static const Color surfaceVariant = surfaceVariantLight;

  // Semantic colors used by specific modules.
  static const Color stockUp = Color(0xFF10B981);
  static const Color stockDown = Color(0xFFEF4444);

  /// Resolves the theme-aware [ColorScheme] from a [BuildContext].
  static ColorScheme schemeOf(BuildContext context) {
    return Theme.of(context).colorScheme;
  }
}
