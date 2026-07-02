import 'package:flutter/material.dart';

import 'app.dart';
import 'data/services/clipboard_monitor_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ClipboardMonitorService.instance.start();
  runApp(const NexusHubApp());
}
