import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../data/services/zhihu_auth_store.dart';
import '../../../data/services/zhihu_service.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_empty_state.dart';

/// WebView-based Zhihu sign-in (WebView2 on Windows).
///
/// Zhihu login cannot be automated (QR scan, rotating captchas, encrypted
/// credentials), so the page embeds the real sign-in flow via
/// `flutter_inappwebview` and lets the user complete the human checks by
/// hand. Login success is detected by watching the WebView cookie store
/// for the `z_c0` session token — it is HttpOnly, so `document.cookie`
/// cannot see it; the plugin's [CookieManager] reads it from the native
/// cookie jar instead (WebView2's ICoreWebView2CookieManager on Windows).
///
/// Once seen, the whole cookie jar is captured into [ZhihuAuthStore] and
/// replayed by [ZhihuService] as a `Cookie` header. Pops with `true` when
/// the session was captured, `null`/`false` on cancel.
class ZhihuLoginPage extends StatefulWidget {
  const ZhihuLoginPage({super.key});

  @override
  State<ZhihuLoginPage> createState() => _ZhihuLoginPageState();
}

class _ZhihuLoginPageState extends State<ZhihuLoginPage> {
  /// Polled alongside navigation callbacks in case the login completes
  /// without a full page navigation (QR scan inside the same document).
  Timer? _pollTimer;

  /// Guards against double-capture once the token has been seen.
  bool _captured = false;

  bool _checking = false;
  bool _webviewFailed = false;

  @override
  void initState() {
    super.initState();
    _ensureWebViewAvailable();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkLogin(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// On Windows the embedded WebView is backed by the WebView2 runtime. It
  /// ships with Windows 10/11 via Edge, but degrade gracefully when it is
  /// missing (same check as the Google News web reader).
  Future<void> _ensureWebViewAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return;
    String? version;
    try {
      version = await WebViewEnvironment.getAvailableVersion();
    } catch (_) {
      version = null;
    }
    if (!mounted || version != null) return;
    setState(() => _webviewFailed = true);
  }

  Future<void> _checkLogin() async {
    if (_captured || _checking || !mounted) return;
    _checking = true;
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri('https://www.zhihu.com'),
      );
      String? token;
      for (final cookie in cookies) {
        if (cookie.name == 'z_c0' && cookie.value.isNotEmpty) {
          token = cookie.value;
          break;
        }
      }
      if (token == null) return;
      _captured = true;
      _pollTimer?.cancel();
      final header = [
        for (final cookie in cookies)
          if (cookie.value.isNotEmpty) '${cookie.name}=${cookie.value}',
      ].join('; ');
      await ZhihuAuthStore.save(header);
      // Best-effort profile fetch; the session works without it.
      try {
        final me = await ZhihuService().fetchMe();
        await ZhihuAuthStore.setUser(me);
      } catch (_) {}
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('登录成功，已保存知乎会话')),
        );
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      // Keep polling; transient cookie-store failures are expected while
      // the WebView is still initialising.
    } finally {
      _checking = false;
    }
  }

  Future<void> _manualCheck() async {
    await _checkLogin();
    if (_captured || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('还未检测到登录状态，请先在页面中完成登录')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          '登录知乎',
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(onPressed: _manualCheck, child: const Text('我已完成登录')),
        ],
      ),
      body: _webviewFailed ? _buildFallback(context) : _buildWebView(),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('https://www.zhihu.com/signin?next=%2F'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
      ),
      onLoadStop: (_, _) => _checkLogin(),
      onUpdateVisitedHistory: (_, _, _) => _checkLogin(),
    );
  }

  Widget _buildFallback(BuildContext context) {
    return NexusEmptyState(
      icon: Icons.language,
      title: '内置浏览器不可用',
      subtitle: '未检测到 WebView2 运行时，无法在此完成登录。请安装 Edge/WebView2 后重试。',
    );
  }
}
