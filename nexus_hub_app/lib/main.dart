import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart' show RustLib;

import 'app.dart';
import 'data/services/clipboard_monitor_service.dart';
import 'data/services/network_monitor_service.dart';
import 'presentation/states/theme_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeState.instance.init();
  ClipboardMonitorService.instance.start();
  // Start per-minute network traffic recording app-wide so history is captured
  // regardless of which page is open. No-ops when network_monitor.dll is
  // absent (e.g. non-Windows).
  NetworkMonitorService.instance.start();

  // Boot the Alacritty Rust engine (used by the Terminal desktop app).
  // It is desktop-only (loads a native .so/.dll) — skip for web.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await RustLib.init();
  }

  runApp(const NexusHubApp());
}
