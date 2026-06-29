import 'package:flutter/material.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class NexusHubApp extends StatelessWidget {
  const NexusHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Nexus Hub',
      debugShowCheckedModeBanner: false,
      theme: NexusAppTheme.light(),
      routerConfig: AppRouter.router,
    );
  }
}
