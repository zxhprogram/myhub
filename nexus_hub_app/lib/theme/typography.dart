import 'package:flutter/material.dart';

import 'colors.dart';

/// Nexus Hub typography tokens.
///
/// All text styles use Microsoft YaHei and match the DESIGN.md spec.
abstract final class NexusTypography {
  static const _fontFamily = 'Microsoft YaHei';

  static TextStyle get headlineXl => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 36 / 30,
    letterSpacing: -0.02 * 30,
    color: NexusColors.onSurface,
  );

  static TextStyle get headlineLg => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    letterSpacing: -0.02 * 24,
    color: NexusColors.onSurface,
  );

  static TextStyle get headlineSm => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 28 / 18,
    letterSpacing: -0.01 * 18,
    color: NexusColors.onSurface,
  );

  static TextStyle get bodyLg => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: -0.01 * 16,
    color: NexusColors.onSurface,
  );

  static TextStyle get bodyMd => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: -0.01 * 14,
    color: NexusColors.onSurface,
  );

  static TextStyle get labelMd => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    letterSpacing: 0.01 * 12,
    color: NexusColors.onSurfaceVariant,
  );

  static TextStyle get labelSm => const TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 14 / 11,
    letterSpacing: 0.05 * 11,
    color: NexusColors.onSurfaceVariant,
  );
}
