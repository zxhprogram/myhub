import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart' show RustLib;

import 'app.dart';
import 'data/services/clipboard_monitor_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ClipboardMonitorService.instance.start();

  // Boot the Alacritty Rust engine (used by the Terminal desktop app).
  // It is desktop-only (loads a native .so/.dll) — skip for web.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await RustLib.init();
  }

  runApp(const NexusHubApp());
}
