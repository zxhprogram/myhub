import 'dart:io';

/// Detects the Windows system (WinINET) HTTP proxy.
///
/// Some CDNs behind the video data source are only reachable through the
/// user's local proxy — their DNS answers are polluted on the default
/// resolver, so direct connections hang until timeout. Browsers play fine
/// because they honour the system proxy, but libmpv and other direct HTTP
/// clients connect on their own. This reads the same registry values the
/// browser uses (`Internet Settings\ProxyEnable` / `ProxyServer`) so
/// playback traffic can be routed identically.
abstract final class SystemProxy {
  static String? _cached;
  static DateTime _cachedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _ttl = Duration(seconds: 60);

  /// Returns the proxy as `host:port`, or null when the system connects
  /// directly (proxy disabled, non-Windows platform, or unreadable config).
  ///
  /// PAC (`AutoConfigURL`) setups are not handled — a manual proxy is
  /// required for the result to be non-null.
  static Future<String?> httpProxy() async {
    if (DateTime.now().difference(_cachedAt) < _ttl) return _cached;
    _cached = await _readProxy();
    _cachedAt = DateTime.now();
    return _cached;
  }

  static Future<String?> _readProxy() async {
    if (!Platform.isWindows) return null;
    try {
      final enabled = await _regQuery('ProxyEnable');
      final enabledMatch = RegExp(
        r'ProxyEnable\s+REG_DWORD\s+0x(\d+)',
      ).firstMatch(enabled);
      if (enabledMatch == null || enabledMatch.group(1) != '1') return null;

      final server = await _regQuery('ProxyServer');
      final serverMatch = RegExp(
        r'ProxyServer\s+REG_SZ\s+(\S+)',
      ).firstMatch(server);
      if (serverMatch == null) return null;
      return _parseProxyServer(serverMatch.group(1)!);
    } catch (_) {
      return null;
    }
  }

  static Future<String> _regQuery(String value) async {
    final result = await Process.run('reg', [
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      value,
    ]);
    return result.stdout?.toString() ?? '';
  }

  /// `ProxyServer` holds either `host:port` (all protocols) or a
  /// per-protocol list like `http=h:p;https=h:p;ftp=h:p`.
  static String? _parseProxyServer(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;
    if (value.contains('=')) {
      final entries = {
        for (final part in value.split(';'))
          if (part.contains('='))
            part.split('=')[0].trim().toLowerCase(): part.split('=')[1].trim(),
      };
      value = entries['https'] ?? entries['http'] ?? entries.values.first;
    }
    final uri = Uri.tryParse('//$value');
    if (uri == null || uri.host.isEmpty || uri.port <= 0) return null;
    return value;
  }
}
