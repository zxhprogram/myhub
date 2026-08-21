import 'package:flutter/foundation.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_empty_state.dart';

/// In-app web reader that opens [url] inside an embedded WebView.
///
/// Uses `flutter_inappwebview`, which supports Windows desktop via the
/// WebView2 runtime (in addition to Android, iOS and macOS). Falls back to
/// an "open in browser" prompt when no WebView runtime is available, so the
/// feature degrades gracefully.
class NexusWebViewPage extends StatefulWidget {
  const NexusWebViewPage({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<NexusWebViewPage> createState() => _NexusWebViewPageState();
}

class _NexusWebViewPageState extends State<NexusWebViewPage> {
  final GlobalKey<NexusWebViewState> _webViewKey =
      GlobalKey<NexusWebViewState>();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.card,
      headers: [
        Container(
          color: colorScheme.muted,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton.ghost(
                icon: const Icon(RadixIcons.arrowLeft),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton.ghost(
                icon: const Icon(LucideIcons.refreshCw),
                onPressed: () => _webViewKey.currentState?.reload(),
              ),
              IconButton.ghost(
                icon: const Icon(LucideIcons.compass),
                onPressed: () => _webViewKey.currentState?.openInBrowser(),
              ),
            ],
          ),
        ),
      ],
      child: NexusWebView(key: _webViewKey, url: widget.url),
    );
  }
}

/// Embeddable WebView widget without its own Scaffold, suitable for placing
/// inside a page region (e.g. the Google News detail pane). Reacts to [url]
/// changes by loading the new address in-place.
class NexusWebView extends StatefulWidget {
  const NexusWebView({super.key, required this.url});

  final String url;

  @override
  State<NexusWebView> createState() => NexusWebViewState();
}

class NexusWebViewState extends State<NexusWebView> {
  InAppWebViewController? _webviewController;
  bool _isLoading = true;
  bool _webviewFailed = false;

  @override
  void initState() {
    super.initState();
    _ensureWebViewAvailable();
  }

  @override
  void didUpdateWidget(NexusWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _setLoading(true);
    _webviewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.url)),
    );
  }

  /// On Windows the embedded WebView is backed by the WebView2 runtime.
  /// It ships with Windows 10/11 via Edge, but double-check and degrade
  /// gracefully when it is missing. Other platforms always have a viewer.
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

  void _setLoading(bool loading) {
    if (!mounted) return;
    setState(() => _isLoading = loading);
  }

  Future<void> reload() async {
    if (_webviewFailed) return;
    _setLoading(true);
    await _webviewController?.reload();
  }

  Future<void> openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return _webviewFailed ? _buildFallback() : _buildWebview();
  }

  Widget _buildWebview() {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            transparentBackground: false,
          ),
          onWebViewCreated: (controller) => _webviewController = controller,
          onLoadStart: (_, _) => _setLoading(true),
          onLoadStop: (_, _) => _setLoading(false),
          onReceivedError: (_, _, _) => _setLoading(false),
        ),
        if (_isLoading)
          Positioned.fill(
            child: ColoredBox(
              color: colorScheme.card.withValues(alpha: 0.6),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFallback() {
    return NexusEmptyState(
      icon: LucideIcons.languages,
      title: 'Built-in viewer unavailable',
      subtitle:
          'This platform has no built-in web viewer. '
          'Open the article in your default browser instead.',
      action: NexusButton(
        label: 'Open in Browser',
        icon: LucideIcons.compass,
        onPressed: openInBrowser,
      ),
    );
  }
}
