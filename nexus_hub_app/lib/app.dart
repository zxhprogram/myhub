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
