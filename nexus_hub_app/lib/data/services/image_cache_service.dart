import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../utils/system_proxy.dart';
import 'video_site_exception.dart';

/// Disk cache for remote images (video sub-app posters / covers).
///
/// Files are stored in a `cache` folder next to the current executable,
/// mirroring the backend layout of the clipboard `temp` folder. Override
/// with `NEXUS_HUB_CACHE_DIR` for local development.
///
/// Downloads follow the route-fallback approach of [VideoStreamRelay]:
/// some CDNs of the data source are only reachable through the system
/// proxy, so a failed direct fetch is retried proxied and the working
/// route is remembered per host. Requests carry no Referer — the site
/// loads covers with `referrerpolicy="no-referrer"` and the CDN rejects
/// other senders.
class ImageCacheService {
  ImageCacheService._();

  static final ImageCacheService instance = ImageCacheService._();

  /// Test seam: overrides the folder that holds the `cache` directory,
  /// so tests do not write next to the test runner executable.
  static String? baseDirOverride;

  /// Same desktop Chrome UA the other video services identify with.
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0.0.0 Safari/537.36';

  /// Cached files above this total size trigger a sweep that deletes the
  /// oldest files first. Posters are a few tens of KB, so the cap leaves
  /// room for the whole catalog while keeping the folder bounded.
  static const int _maxCacheBytes = 256 * 1024 * 1024;

  /// Hosts known to answer only through a given route, learned from the
  /// last successful download of that host.
  final Map<String, bool> _hostPrefersProxy = {};

  /// In-flight downloads keyed by URL, so grid cells showing the same
  /// cover do not fetch it multiple times.
  final Map<String, Future<File>> _inFlight = {};

  HttpClient? _directClient;
  HttpClient? _proxyClient;
  String? _proxyHostPort;
  late final Directory _dir = _ensureCacheDir();
  bool _sweepScheduled = false;

  /// Returns the cached image file for [url], downloading it on first
  /// request. Throws on download failure; a later call retries.
  Future<File> getImage(String url) {
    final pending = _inFlight[url];
    if (pending != null) return pending;
    final task = _load(url);
    _inFlight[url] = task;
    return task.whenComplete(() => _inFlight.remove(url));
  }

  Future<File> _load(String url) async {
    final file = File(p.join(_dir.path, _keyFor(url)));
    if (file.existsSync()) return file;
    final bytes = await _download(url);
    // Write to a temp name first so a crash mid-download never leaves a
    // truncated file behind under the cache key.
    final partial = File('${file.path}.tmp');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    _scheduleSweep();
    return file;
  }

  Future<Uint8List> _download(String url) async {
    final host = Uri.parse(url).host;
    final preferProxy = _hostPrefersProxy[host] ?? false;
    final routes = preferProxy ? const [true, false] : const [false, true];
    Object? lastError;
    for (final viaProxy in routes) {
      if (viaProxy && await SystemProxy.httpProxy() == null) continue;
      try {
        final bytes = await _fetch(
          viaProxy ? await _proxyHttpClient() : _directHttpClient(),
          url,
        );
        _hostPrefersProxy[host] = viaProxy;
        return bytes;
      } catch (error) {
        lastError = error;
      }
    }
    throw StateException('图片下载失败（$host）：$lastError');
  }

  HttpClient _directHttpClient() =>
      _directClient ??= HttpClient()
        ..userAgent = _userAgent;

  Future<HttpClient> _proxyHttpClient() async {
    final existing = _proxyClient;
    if (existing != null) return existing;
    final proxy = _proxyHostPort ?? await SystemProxy.httpProxy();
    if (proxy == null) {
      throw StateException('系统代理不可用');
    }
    _proxyHostPort = proxy;
    final client = HttpClient()
      ..userAgent = _userAgent
      ..findProxy = (uri) => 'PROXY $proxy';
    return _proxyClient = client;
  }

  Future<Uint8List> _fetch(HttpClient client, String url) async {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().catchError((_) {});
      throw HttpException('HTTP ${response.statusCode}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw const HttpException('空响应');
    return bytes;
  }

  Directory _ensureCacheDir() {
    final base =
        baseDirOverride ??
        Platform.environment['NEXUS_HUB_CACHE_DIR'] ??
        File(Platform.resolvedExecutable).parent.path;
    final dir = Directory(p.join(base, 'cache'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// FNV-1a 64-bit of the URL as hex file name — stable across runs and
  /// platforms, collision-free for a catalog-sized set of URLs.
  String _keyFor(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  /// Deletes the oldest cached files once the folder exceeds the size
  /// cap. Runs at most once concurrently and failures are ignored — a
  /// bloated cache only costs disk, never correctness.
  void _scheduleSweep() {
    if (_sweepScheduled) return;
    _sweepScheduled = true;
    Future(() async {
      try {
        final entries =
            _dir
                .listSync()
                .whereType<File>()
                // `.tmp` files belong to in-flight downloads.
                .where((f) => !f.path.endsWith('.tmp'))
                .map((f) => (f, f.statSync()))
                .toList()
              ..sort(
                (a, b) => a.$2.modified.compareTo(b.$2.modified),
              );
        var total = 0;
        for (final entry in entries) {
          total += entry.$2.size;
        }
        for (final entry in entries) {
          if (total <= _maxCacheBytes) break;
          total -= entry.$2.size;
          entry.$1.deleteSync();
        }
      } catch (_) {
        // Best-effort housekeeping.
      } finally {
        _sweepScheduled = false;
      }
    });
  }
}
