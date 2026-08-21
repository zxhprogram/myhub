import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Theme plumbing for Nexus Hub.
///
/// The whole UI is built from shadcn_flutter components and uses the default
/// slate color scheme. A few third-party packages (flutter_quill toolbar,
/// media_kit video controls, gpt_markdown, flutter_widget_from_html) still
/// read the ambient *Material* theme internally and cannot be rewritten;
/// [materialCompatTheme] derives a matching Material theme from the slate
/// scheme so they render correctly in dark mode. This is the only file in
/// the app allowed to import flutter/material.
abstract final class NexusAppTheme {
  static const shadcnLight = ThemeData(colorScheme: ColorSchemes.lightSlate);
  static const shadcnDark = ThemeData(colorScheme: ColorSchemes.darkSlate);

  /// Material theme mirroring the slate scheme, fed to
  /// `ShadcnApp.materialTheme` for packages that read the Material theme.
  static material.ThemeData materialCompatTheme(Brightness brightness) {
    final scheme = brightness == Brightness.dark
        ? ColorSchemes.darkSlate
        : ColorSchemes.lightSlate;
    return material.ThemeData.from(
      colorScheme: material.ColorScheme.fromSeed(
        seedColor: scheme.primary,
        brightness: brightness,
        surface: scheme.background,
        primary: scheme.primary,
        secondary: scheme.secondary,
        error: scheme.destructive,
      ),
    );
  }
}
