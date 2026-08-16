import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import '../../utils/system_proxy.dart';
import 'video_site_service.dart' show StateException;

/// Local HLS relay: moves all stream networking away from libmpv.
///
/// libmpv's own HTTP stack misbehaves on this data source — proxied
/// playlists degrade to per-segment playback (no total duration, a
/// re-buffer between every .ts file) and DNS-poisoned CDN hosts hang
/// until timeout. The relay instead fetches the playlist and every
/// segment in Dart, where routing can fall back from a direct connection
/// to the system proxy per host, and serves mpv a fully local playlist
/// whose segment links point back at this relay. mpv then only ever
/// talks to 127.0.0.1 over plain HTTP and the HLS demuxer sees a clean,
/// self-describing playlist with the complete duration.
class VideoStreamRelay {
  VideoStreamRelay({String? userAgent}) : _userAgent = userAgent ?? _defaultUserAgent;

  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/125.0.0.0 Safari/537.36';

  /// Master playlists are followed at most this many levels deep.
  static const int _maxPlaylistDepth = 3;

  /// Redirect chains are followed at most this many hops.
  static const int _maxRedirectHops = 6;

  /// Segments kept in memory so seeking backwards is instant.
  static const int _cacheLimit = 48;

  final String _userAgent;
  final HttpClient _directClient =
      HttpClient()..connectionTimeout = const Duration(seconds: 8);
  HttpClient? _proxyClient;
  String? _proxyHostPort;

  /// Whether the last successful fetch for a host went through the proxy.
  /// Remembered so only the first request per host pays fallback latency.
  final Map<String, bool> _hostPrefersProxy = {};

  /// Small LRU segment cache (insertion order = recency).
  final Map<String, Uint8List> _segmentCache = {};

  HttpServer? _server;
  String? _playlistBody;

  /// Fetches [streamUrl] (following master playlists), rewrites segment
  /// links to local ones and starts serving. Returns the local playlist
  /// URL for the player to open.
  Future<String> serve(String streamUrl) async {
    await stop();
    var url = streamUrl;
    String body;
    for (var depth = 0;; depth++) {
      body = utf8.decode(await _fetchBytes(url));
      if (!body.contains('#EXT-X-STREAM-INF') || depth >= _maxPlaylistDepth) {
        break;
      }
      final variant = _firstEntryUrl(body, url);
      if (variant == null) break;
      url = variant;
    }
    _playlistBody = _rewritePlaylist(body, url);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(
      _handleRequest,
      onError: (Object _) {}, // client-visible failures are per-request
    );
    return 'http://127.0.0.1:${server.port}/index.m3u8';
  }

  /// Stops the server and releases connections. Safe to call repeatedly.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _playlistBody = null;
    _segmentCache.clear();
    await server?.close(force: true);
  }

  // ------------------------------------------------------------------
  // Local server
  // ------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/index.m3u8') {
        final body = _playlistBody;
        if (body == null) {
          await _respond(
            request,
            HttpStatus.serviceUnavailable,
            'text/plain',
            utf8.encode('no playlist'),
          );
          return;
        }
        await _respond(
          request,
          HttpStatus.ok,
          'application/vnd.apple.mpegurl',
          utf8.encode(body),
        );
      } else if (request.uri.path == '/segment') {
        final target = request.uri.queryParameters['u'];
        if (target == null) {
          await _respond(
            request,
            HttpStatus.badRequest,
            'text/plain',
            utf8.encode('missing u'),
          );
          return;
        }
        final bytes = await _fetchSegment(target);
        await _respond(request, HttpStatus.ok, 'video/mp2t', bytes);
      } else {
        await _respond(
          request,
          HttpStatus.notFound,
          'text/plain',
          utf8.encode('not found'),
        );
      }
    } catch (_) {
      try {
        await _respond(
          request,
          HttpStatus.badGateway,
          'text/plain',
          utf8.encode('upstream failure'),
        );
      } catch (_) {
        // Client already gone.
      }
    }
  }

  Future<void> _respond(
    HttpRequest request,
    int status,
    String contentType,
    List<int> body,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    response.headers.contentLength = body.length;
    response.add(body);
    await response.close();
  }

  // ------------------------------------------------------------------
  // Upstream fetching
  // ------------------------------------------------------------------

  Future<Uint8List> _fetchSegment(String url) async {
    final cached = _segmentCache.remove(url);
    if (cached != null) {
      _segmentCache[url] = cached;
      return cached;
    }
    final bytes = await _fetchBytes(url, minExpectedBytes: 1024);
    _segmentCache[url] = bytes;
    while (_segmentCache.length > _cacheLimit) {
      _segmentCache.remove(_segmentCache.keys.first);
    }
    return bytes;
  }

  /// Follows redirects manually so every hop picks its own best route.
  ///
  /// This matters because playlist hosts and their segment redirect
  /// targets often live on different CDNs with opposite reachability:
  /// e.g. the playlist host answers only directly while the segment
  /// target (an overseas CDN) returns 403 unless proxied.
  Future<Uint8List> _fetchBytes(String url, {int minExpectedBytes = 0}) async {
    var current = url;
    for (var hop = 0; hop < _maxRedirectHops; hop++) {
      final result = await _requestWithRouteFallback(
        current,
        minExpectedBytes: minExpectedBytes,
      );
      final location = result.redirectLocation;
      if (location != null) {
        current = Uri.parse(current).resolve(location).toString();
        continue;
      }
      return result.body!;
    }
    throw StateException('视频源重定向次数过多');
  }

  Future<_HopResult> _requestWithRouteFallback(
    String url, {
    int minExpectedBytes = 0,
  }) async {
    final host = Uri.parse(url).host;
    final preferProxy = _hostPrefersProxy[host] ?? false;
    final routes = preferProxy ? const [true, false] : const [false, true];
    Object? lastError;
    for (final viaProxy in routes) {
      if (viaProxy && await SystemProxy.httpProxy() == null) continue;
      try {
        final result = await _fetchRaw(
          viaProxy ? await _proxyHttpClient() : _directClient,
          url,
        );
        final acceptable =
            result.redirectLocation != null ||
            (result.body != null && result.body!.length >= minExpectedBytes);
        if (acceptable) {
          _hostPrefersProxy[host] = viaProxy;
          return result;
        }
        // Transport worked but the answer is unusable (403/418 WAF,
        // truncated stub) — try the other route for this hop.
        lastError = HttpException('HTTP ${result.status}');
      } catch (error) {
        lastError = error;
      }
    }
    throw StateException(
      '视频流获取失败（$host）：$lastError',
    );
  }

  Future<_HopResult> _fetchRaw(HttpClient client, String url) async {
    final request = await client
        .getUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 20));
    final location = response.headers.value(HttpHeaders.locationHeader);
    if (response.isRedirect && location != null) {
      await response.drain<void>().catchError((_) {});
      return _HopResult(response.statusCode, location, null);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().catchError((_) {});
      return _HopResult(response.statusCode, null, null);
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return _HopResult(response.statusCode, null, builder.takeBytes());
  }

  Future<HttpClient> _proxyHttpClient() async {
    final existing = _proxyClient;
    if (existing != null) return existing;
    final proxy = _proxyHostPort ?? await SystemProxy.httpProxy();
    if (proxy == null) {
      throw StateException('系统代理不可用');
    }
    _proxyHostPort = proxy;
    final client = HttpClient();
    client.findProxy = (uri) => 'PROXY $proxy';
    return _proxyClient = client;
  }
  // ------------------------------------------------------------------
  // Playlist rewriting
  // ------------------------------------------------------------------

  /// Replaces every URI line with a local `/segment?u=...` link so the
  /// player never contacts the CDN directly.
  String _rewritePlaylist(String body, String playlistUrl) {
    final base = Uri.parse(playlistUrl);
    final out = StringBuffer();
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        out.writeln(rawLine);
        continue;
      }
      final absolute = base.resolve(line).toString();
      out.writeln('/segment?u=${Uri.encodeComponent(absolute)}');
    }
    return out.toString();
  }

  String? _firstEntryUrl(String body, String playlistUrl) {
    final base = Uri.parse(playlistUrl);
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      return base.resolve(trimmed).toString();
    }
    return null;
  }
}

/// One upstream response hop: either a redirect ([redirectLocation] set)
/// or a final body (200 with payload).
class _HopResult {
  const _HopResult(this.status, this.redirectLocation, this.body);

  final int status;
  final String? redirectLocation;
  final Uint8List? body;
}
