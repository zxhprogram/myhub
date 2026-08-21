import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../data/services/zhihu_auth_store.dart';
import '../../../data/services/zhihu_service.dart';
import '../../components/zhihu_ui.dart';

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
///
/// ## Why the WebView is parked, never destroyed
///
/// Closing this page used to take the whole process down with it: the
/// widget's `dispose` invokes the plugin's native `dispose`, which erases
/// the WebView synchronously inside the method-call handler —
/// `UnregisterTexture` → texture-bridge teardown → `DestroyWindow` +
/// `ICoreWebView2Controller::Close()` — and that teardown chain crashes
/// the app without any error (the vendored plugin already carries two
/// local patches for related teardown landmines; see the pubspec notes).
///
/// The fix uses the plugin's own escape hatch: with a [keepAlive] handle,
/// the native side stores the WebView under `keepAliveWebViews`, and the
/// `dispose` handler only looks in `webViews` — so widget disposal is a
/// no-op natively. The WebView is parked on `about:blank` and reused by
/// the next login ([_keepAlive] is app-lifetime). [disposeKeepAlive] is
/// deliberately never called: it would re-enter the crashing path.
class ZhihuLoginPage extends StatefulWidget {
  const ZhihuLoginPage({super.key});

  @override
  State<ZhihuLoginPage> createState() => _ZhihuLoginPageState();
}

class _ZhihuLoginPageState extends State<ZhihuLoginPage> {
  static const _signInUrl = 'https://www.zhihu.com/signin?next=%2F';

  /// App-lifetime keep-alive handle parking the login WebView between
  /// logins (see the class documentation for why it must never be
  /// disposed).
  static InAppWebViewKeepAlive? _keepAlive;

  /// Controller of the currently attached WebView; null while parked.
  InAppWebViewController? _webController;

  /// Polled alongside navigation callbacks in case the login completes
  /// without a full page navigation (QR scan inside the same document).
  Timer? _pollTimer;

  /// Guards against double-capture once the token has been seen.
  bool _captured = false;

  bool _checking = false;
  bool _webviewFailed = false;

  /// Set when the store flagged the parked session as stale (logout), so
  /// the WebView's cookies get cleared before the sign-in page loads —
  /// otherwise the still-valid zhihu session would auto-login instantly
  /// with the previous account.
  bool _clearWebviewSession = false;

  @override
  void initState() {
    super.initState();
    _clearWebviewSession = ZhihuAuthStore.consumeWebSessionInvalidated();
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
      // Park the WebView before leaving so the kept-alive instance stops
      // running the logged-in page in the background.
      unawaited(_parkWebView());
      // Best-effort profile fetch; the session works without it.
      try {
        final me = await ZhihuService().fetchMe();
        await ZhihuAuthStore.setUser(me);
      } catch (_) {}
      if (!mounted) return;
      zhihuShowToast(context, '登录成功，已保存知乎会话');
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

  /// Navigates the parked WebView to a blank document. The WebView keeps
  /// living after this page closes (keep-alive), and `about:blank` costs
  /// nothing to render.
  Future<void> _parkWebView() async {
    final controller = _webController;
    _webController = null;
    if (controller == null) return;
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    } catch (_) {
      // Parking is best-effort; a failed navigation changes nothing for the
      // already-captured session.
    }
  }

  /// Prepares a freshly attached WebView: optionally clears the stale
  /// zhihu cookies, then (re)loads the sign-in page. The explicit
  /// navigation matters for re-attachments, where `initialUrlRequest` is
  /// ignored by the native side.
  Future<void> _prepareSession() async {
    final controller = _webController;
    if (controller == null) return;
    if (_clearWebviewSession) {
      _clearWebviewSession = false;
      try {
        await CookieManager.instance().deleteCookies(
          url: WebUri('https://www.zhihu.com'),
        );
      } catch (_) {
        // If clearing fails the page may auto-login with the old session;
        // the user can sign out on the page itself.
      }
    }
    try {
      await controller.loadUrl(
        urlRequest: URLRequest(url: WebUri(_signInUrl)),
      );
    } catch (_) {
      // initialUrlRequest already covers the fresh-creation path.
    }
  }

  Future<void> _manualCheck() async {
    await _checkLogin();
    if (_captured || !mounted) return;
    zhihuShowToast(context, '还未检测到登录状态，请先在页面中完成登录');
  }

  @override
  Widget build(BuildContext context) {
    return ZhihuShadcnHost(
      builder: (context) {
        final theme = Theme.of(context);
        return Container(
          color: theme.colorScheme.background,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                  child: Row(
                    children: [
                      IconButton.ghost(
                        icon: const Icon(LucideIcons.x, size: 16),
                        size: ButtonSize.small,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const Gap(4),
                      Text(
                        '登录知乎',
                        style: theme.typography.small.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Button.ghost(
                        style: const ButtonStyle.ghost(
                          size: ButtonSize.small,
                          density: ButtonDensity.dense,
                        ),
                        onPressed: _manualCheck,
                        child: const Text('我已完成登录'),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: theme.colorScheme.border),
                Expanded(
                  child: _webviewFailed
                      ? ZhihuEmptyState(
                          icon: LucideIcons.globe,
                          title: '内置浏览器不可用',
                          subtitle:
                              '未检测到 WebView2 运行时，无法在此完成登录。请安装 Edge/WebView2 后重试。',
                        )
                      : _buildWebView(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      keepAlive: _keepAlive ??= InAppWebViewKeepAlive(),
      initialUrlRequest: URLRequest(url: WebUri(_signInUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
      ),
      onWebViewCreated: (controller) {
        _webController = controller;
        unawaited(_prepareSession());
      },
      onLoadStop: (_, _) => _checkLogin(),
      onUpdateVisitedHistory: (_, _, _) => _checkLogin(),
    );
  }
}
