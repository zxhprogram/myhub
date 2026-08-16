import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart' show RustLib;
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'data/services/clipboard_monitor_service.dart';
import 'data/services/input_hook_service.dart';
import 'data/services/network_monitor_service.dart';
import 'presentation/states/clipboard_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Boot the libmpv backend used by the Video sub-app (no-op where bundled
  // libraries are absent).
  MediaKit.ensureInitialized();
  ClipboardMonitorService.instance.start();
  // Persist clipboard items app-wide even before the history page is opened,
  // so nothing is lost when the corresponding icon is never visited.
  ClipboardState.instance.ensureListening();
  // Start per-minute network traffic recording app-wide so history is captured
  // regardless of which page is open. No-ops when network_monitor.dll is
  // absent (e.g. non-Windows).
  NetworkMonitorService.instance.start();
  // Start the global input hook and background key press recording app-wide
  // so statistics are captured even when the My Computer page is not open.
  // No-ops when input_hook.dll is absent (e.g. non-Windows).
  InputHookService.instance.start();

  // Boot the Alacritty Rust engine (used by the Terminal desktop app).
  // It is desktop-only (loads a native .so/.dll) — skip for web.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await RustLib.init();
  }

  runApp(const NexusHubApp());
}
