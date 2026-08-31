import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../utils/system_proxy.dart';

/// Creates [Dio] instances that honor the machine's proxy configuration:
/// when a Windows system proxy is enabled (WinINET registry, e.g. Clash's
/// "system proxy" toggle) — or HTTPS_PROXY/HTTP_PROXY is set — requests are
/// routed through it; otherwise traffic goes out directly.
///
/// Dart's HttpClient does not read the Windows proxy settings on its own,
/// which is why GitHub API calls otherwise fail with "could not reach
/// GitHub" on machines that are only reachable through the proxy.
abstract final class ProxyDioFactory {
  static Dio? _cached;

  /// Returns a shared, proxy-configured [Dio] instance.
  static Future<Dio> instance() async {
    final existing = _cached;
    if (existing != null) return existing;
    final dio = Dio();
    final proxy = kIsWeb ? null : await _resolveProxy();
    if (proxy != null) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.findProxy = (uri) => 'PROXY $proxy';
          return client;
        },
      );
    }
    _cached = dio;
    return dio;
  }

  /// Proxy authority (`host:port`) to route traffic through, or null for a
  /// direct connection. The system proxy (when enabled) wins over the
  /// environment variables.
  static Future<String?> _resolveProxy() async =>
      await SystemProxy.httpProxy() ??
      _normalize(
        Platform.environment['HTTPS_PROXY'] ??
            Platform.environment['https_proxy'] ??
            Platform.environment['HTTP_PROXY'] ??
            Platform.environment['http_proxy'],
      );

  /// Strips scheme / path so `http://127.0.0.1:7890` becomes `127.0.0.1:7890`.
  static String? _normalize(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    for (final prefix in ['http://', 'https://']) {
      if (value.startsWith(prefix)) {
        value = value.substring(prefix.length);
      }
    }
    value = value.split('/').first;
    return value.contains(':') ? value : null;
  }
}
