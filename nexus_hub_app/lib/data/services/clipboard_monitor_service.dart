import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:super_clipboard/super_clipboard.dart';

import '../models/clipboard_item_model.dart';

/// Monitors the system clipboard and exposes new text, image, and file items
/// as a broadcast stream.
///
/// Start monitoring once at app launch via [instance.start] and stop on exit
/// via [instance.stop].
class ClipboardMonitorService {
  ClipboardMonitorService._();

  /// The singleton instance used across the app.
  static final ClipboardMonitorService instance = ClipboardMonitorService._();

  final _controller = StreamController<ClipboardItemModel>.broadcast();
  Timer? _timer;
  String? _lastSignature;

  static const _pollInterval = Duration(seconds: 2);

  /// Stream of newly detected clipboard items.
  Stream<ClipboardItemModel> get onItem => _controller.stream;

  void start() {
    _timer?.cancel();
    _checkClipboard();
    _timer = Timer.periodic(_pollInterval, (_) => _checkClipboard());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;

    final reader = await clipboard.read();

    // Prioritize files, then images, then text.
    if (reader.canProvide(Formats.fileUri)) {
      final uri = await reader.readValue(Formats.fileUri);
      if (uri != null) {
        final signature = 'file:${uri.toString()}';
        if (signature == _lastSignature) return;
        _lastSignature = signature;
        await _persistFile(uri);
      }
    } else if (reader.canProvide(Formats.png)) {
      await _persistImage(reader, Formats.png, 'image/png', 'png');
    } else if (reader.canProvide(Formats.jpeg)) {
      await _persistImage(reader, Formats.jpeg, 'image/jpeg', 'jpg');
    } else if (reader.canProvide(Formats.gif)) {
      await _persistImage(reader, Formats.gif, 'image/gif', 'gif');
    } else if (reader.canProvide(Formats.webp)) {
      await _persistImage(reader, Formats.webp, 'image/webp', 'webp');
    } else if (reader.canProvide(Formats.bmp)) {
      await _persistImage(reader, Formats.bmp, 'image/bmp', 'bmp');
    } else if (reader.canProvide(Formats.plainText)) {
      final text = await reader.readValue(Formats.plainText);
      if (text != null && text.isNotEmpty) {
        final signature = 'text:${text.trim()}';
        if (signature == _lastSignature) return;
        _lastSignature = signature;
        _controller.add(
          ClipboardItemModel(
            content: text.trim(),
            type: 'text',
            createdAt: DateTime.now(),
          ),
        );
      }
    }
  }

  Future<void> _persistFile(Uri uri) async {
    final source = File(uri.toFilePath(windows: Platform.isWindows));
    if (!await source.exists()) return;

    final localPath = await _copyToLocalTemp(source, p.basename(source.path));
    _controller.add(
      ClipboardItemModel(
        content: p.basename(source.path),
        type: 'file',
        filePath: localPath,
        mimeType: _guessMimeType(source.path),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> _persistImage(
    ClipboardReader reader,
    SimpleFileFormat format,
    String mimeType,
    String extension,
  ) async {
    reader.getFile(format, (file) async {
      final bytes = await file.readAll();
      final signature = _imageSignature(bytes);
      if (signature == _lastSignature) return;
      _lastSignature = signature;

      final name =
          'clipboard_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final localPath = await _writeToLocalTemp(bytes, name);
      _controller.add(
        ClipboardItemModel(
          content: name,
          type: 'image',
          filePath: localPath,
          mimeType: mimeType,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  String _imageSignature(Uint8List bytes) {
    return 'image:${bytes.length}:${bytes.firstOrNull}:${bytes.lastOrNull}';
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  /// Returns the clipboard temp directory, mirroring the backend layout:
  /// a `temp` folder next to the current executable. Override with
  /// `NEXUS_HUB_TEMP_DIR` for local development.
  Future<String> _localTempDirPath() async {
    final base =
        Platform.environment['NEXUS_HUB_TEMP_DIR'] ??
        File(Platform.resolvedExecutable).parent.path;
    final temp = Directory(p.join(base, 'temp'));
    if (!temp.existsSync()) {
      temp.createSync(recursive: true);
    }
    return temp.path;
  }

  Future<String> _copyToLocalTemp(File source, String name) async {
    final dir = await _localTempDirPath();
    final safeName = _safeFileName(name);
    final uniqueName = '${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final target = File(p.join(dir, uniqueName));
    await source.copy(target.path);
    return target.path;
  }

  Future<String> _writeToLocalTemp(Uint8List bytes, String name) async {
    final dir = await _localTempDirPath();
    final file = File(p.join(dir, name));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Removes path separators and unsafe characters from file names.
  String _safeFileName(String name) {
    final base = p.basename(name);
    return base.replaceAll(RegExp('[^a-zA-Z0-9._-]'), '_');
  }
}
