/// Windows system proxy control, ported from FlClash's `ProxyManager` +
/// `plugins/proxy` (FlClash ships a per-platform native plugin; this hub only
/// needs Windows, where "system proxy" is a pair of WinINET registry values
/// plus the `InternetSetOptionW` refresh notification).
///
/// The registry is written through `reg.exe` (the same approach as the hub's
/// `SystemProxy` reader) and WinINET is refreshed with a direct FFI call to
/// `wininet.dll`, following the input_hook / network_monitor service pattern.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

class ClashSystemProxyException implements Exception {
  const ClashSystemProxyException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ClashSystemProxyService {
  ClashSystemProxyService._();

  static final ClashSystemProxyService instance = ClashSystemProxyService._();

  static const _regPath =
      r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  // InternetSetOption option codes: notify settings changed + refresh state.
  static const _optionSettingsChanged = 39;
  static const _optionRefresh = 37;

  /// Default bypass list, ported from FlClash's Windows defaults.
  static const defaultBypass = 'localhost;127.*;10.*;172.16.*;<local>';

  bool get isSupported => !kIsWeb && Platform.isWindows;

  /// Whether the WinINET proxy is currently enabled.
  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final output = await _query('ProxyEnable');
    return RegExp(r'ProxyEnable\s+REG_DWORD\s+0x1').hasMatch(output);
  }

  /// The configured proxy server, when one is set.
  Future<String?> server() async {
    if (!isSupported) return null;
    final output = await _query('ProxyServer');
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+(\S+)').firstMatch(output);
    return match?.group(1);
  }

  /// Points WinINET at [server] (typically `127.0.0.1:<inbound-port>`).
  Future<void> enable({required String server, required String bypass}) async {
    if (!isSupported) {
      throw const ClashSystemProxyException('当前平台不支持设置系统代理');
    }
    await _write('ProxyEnable', 'REG_DWORD', '1');
    await _write('ProxyServer', 'REG_SZ', server);
    await _write('ProxyOverride', 'REG_SZ', bypass);
    _notifyWininet();
  }

  /// Restores direct connections (the proxy values are left in place, only
  /// the master switch is turned off — the same behavior as FlClash).
  Future<void> disable() async {
    if (!isSupported) {
      throw const ClashSystemProxyException('当前平台不支持设置系统代理');
    }
    await _write('ProxyEnable', 'REG_DWORD', '0');
    _notifyWininet();
  }

  Future<String> _query(String name) async {
    try {
      final result = await Process.run(
        'reg',
        ['query', 'HKCU\\$_regPath', '/v', name],
      );
      return result.stdout.toString();
    } catch (_) {
      return '';
    }
  }

  Future<void> _write(String name, String type, String value) async {
    final result = await Process.run('reg', [
      'add',
      'HKCU\\$_regPath',
      '/v',
      name,
      '/t',
      type,
      '/d',
      value,
      '/f',
    ]);
    if (result.exitCode != 0) {
      throw ClashSystemProxyException(
        '写入系统代理设置失败：${result.stderr.toString().trim()}',
      );
    }
  }

  /// Tells WinINET the settings changed so running applications pick them up
  /// without a logoff. Best-effort — if the call is unavailable the registry
  /// change still applies on the next WinINET reload.
  void _notifyWininet() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final setOption = wininet.lookupFunction<
        Int32 Function(IntPtr, Int32, IntPtr, Int32),
        int Function(int, int, int, int)
      >('InternetSetOptionW');
      setOption(0, _optionSettingsChanged, 0, 0);
      setOption(0, _optionRefresh, 0, 0);
    } catch (_) {
      // Ignore — see above.
    }
  }
}
