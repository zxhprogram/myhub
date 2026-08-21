import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'presentation/states/theme_state.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class NexusHubApp extends StatelessWidget {
  const NexusHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final themeMode = ThemeState.instance.themeMode.value;
      final platformBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      final isDark = themeMode == ThemeMode.dark ||
          (themeMode == ThemeMode.system &&
              platformBrightness == Brightness.dark);
      return ShadcnApp.router(
        title: 'Nexus Hub',
        debugShowCheckedModeBanner: false,
        theme: NexusAppTheme.shadcnLight,
        darkTheme: NexusAppTheme.shadcnDark,
        themeMode: themeMode,
        routerConfig: AppRouter.router,
        // Compatibility Material theme for packages that still read the
        // ambient Material theme (flutter_quill, media_kit controls,
        // gpt_markdown, flutter_widget_from_html).
        materialTheme: NexusAppTheme.materialCompatTheme(
          isDark ? Brightness.dark : Brightness.light,
        ),
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
