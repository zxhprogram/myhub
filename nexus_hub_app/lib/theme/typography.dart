import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Nexus Hub typography tokens.
///
/// All text styles use Inter and match the DESIGN.md spec.
abstract final class NexusTypography {
  static TextStyle get headlineXl => GoogleFonts.inter(
    fontSize: 30,
    fontWeight: FontWeight.w600,
    height: 36 / 30,
    letterSpacing: -0.02 * 30,
    color: NexusColors.onSurface,
  );

  static TextStyle get headlineLg => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 32 / 24,
    letterSpacing: -0.02 * 24,
    color: NexusColors.onSurface,
  );

  static TextStyle get headlineSm => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 28 / 18,
    letterSpacing: -0.01 * 18,
    color: NexusColors.onSurface,
  );

  static TextStyle get bodyLg => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: -0.01 * 16,
    color: NexusColors.onSurface,
  );

  static TextStyle get bodyMd => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: -0.01 * 14,
    color: NexusColors.onSurface,
  );

  static TextStyle get labelMd => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    letterSpacing: 0.01 * 12,
    color: NexusColors.onSurfaceVariant,
  );

  static TextStyle get labelSm => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 14 / 11,
    letterSpacing: 0.05 * 11,
    color: NexusColors.onSurfaceVariant,
  );
}
