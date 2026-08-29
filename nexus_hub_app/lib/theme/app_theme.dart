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
  /// App-wide default font: Microsoft YaHei (微软雅黑).
  static const _fontFamily = 'Microsoft YaHei';

  /// shadcn typography with the sans family switched to Microsoft YaHei so
  /// every [Text] rendered through shadcn (and the root DefaultTextStyle
  /// wired by ShadcnApp from `typography.sans`) picks it up by default.
  static final Typography typography = Typography.geist().copyWith(
    sans: () => const TextStyle(fontFamily: _fontFamily),
  );

  static final shadcnLight = ThemeData(
    colorScheme: ColorSchemes.lightSlate,
    typography: typography,
  );
  static final shadcnDark = ThemeData(
    colorScheme: ColorSchemes.darkSlate,
    typography: typography,
  );

  /// Material theme mirroring the slate scheme, fed to
  /// `ShadcnApp.materialTheme` for packages that read the Material theme.
  static material.ThemeData materialCompatTheme(Brightness brightness) {
    final scheme = brightness == Brightness.dark
        ? ColorSchemes.darkSlate
        : ColorSchemes.lightSlate;
    final data = material.ThemeData.from(
      colorScheme: material.ColorScheme.fromSeed(
        seedColor: scheme.primary,
        brightness: brightness,
        surface: scheme.background,
        primary: scheme.primary,
        secondary: scheme.secondary,
        error: scheme.destructive,
      ),
    );
    // Keep the embedded Material surfaces (quill toolbar, media_kit controls)
    // on the same app-wide font.
    return data.copyWith(
      textTheme: data.textTheme.apply(fontFamily: _fontFamily),
      primaryTextTheme: data.primaryTextTheme.apply(fontFamily: _fontFamily),
    );
  }
}
