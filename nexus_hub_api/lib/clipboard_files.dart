import 'dart:io';

import 'package:path/path.dart' as p;

/// Base directory for persisted clipboard files.
///
/// Defaults to a `temp` folder next to the current executable. Override with
/// `NEXUS_HUB_TEMP_DIR` for local development where the executable is the Dart VM.
String get clipboardTempDir {
  final base = Platform.environment['NEXUS_HUB_TEMP_DIR'] ??
      File(Platform.resolvedExecutable).parent.path;
  return p.join(base, 'temp');
}

/// Ensures the clipboard temp directory exists.
Directory ensureClipboardTempDir() {
  final dir = Directory(clipboardTempDir);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

/// Resolves a relative [filePath] (as stored in the database) to an absolute
/// file system path.
String resolveClipboardFilePath(String filePath) {
  return p.normalize(p.join(clipboardTempDir, '..', filePath));
}
