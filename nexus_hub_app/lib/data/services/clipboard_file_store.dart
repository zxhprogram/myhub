import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores clipboard file/image payloads on disk under
/// `{appSupport}/clipboard_files` (previously handled by the backend's
/// upload + static file serving endpoints).
class ClipboardFileStore {
  static const _dirName = 'clipboard_files';

  Future<String> _baseDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, _dirName));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// Copies [sourcePath] into the store and returns the stored absolute path.
  /// The file is named `<timestamp>_<sanitized-basename>`, mirroring the
  /// naming scheme the backend used for uploads.
  Future<String> importFile(String sourcePath) async {
    final base = await _baseDir();
    final name = _safeFileName(p.basename(sourcePath));
    final target = p.join(base, '${DateTime.now().millisecondsSinceEpoch}_$name');
    await File(sourcePath).copy(target);
    return target;
  }

  /// Deletes [storedPath] if it lives inside the store directory. Files
  /// outside the store (e.g. legacy temp paths) are left untouched.
  Future<void> deleteFile(String storedPath) async {
    try {
      final base = await _baseDir();
      final resolved = File(storedPath).absolute.path;
      if (!p.isWithin(base, resolved)) return;
      final file = File(resolved);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Ignore cleanup failures.
    }
  }

  /// Removes every managed file (used when the clipboard history is cleared).
  Future<void> deleteAll() async {
    try {
      final base = await _baseDir();
      final dir = Directory(base);
      if (!dir.existsSync()) return;
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            await entity.delete();
          } on FileSystemException {
            // Ignore cleanup failures.
          }
        }
      }
    } on FileSystemException {
      // Ignore cleanup failures.
    }
  }

  String _safeFileName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return sanitized.isEmpty ? 'file' : sanitized;
  }
}
