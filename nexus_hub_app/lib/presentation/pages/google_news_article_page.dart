import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  InAppWebViewController? _webviewController;
  bool _isLoading = true;
  bool _webviewFailed = false;

  @override
  void initState() {
    super.initState();
    _ensureWebViewAvailable();
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

  Future<void> _reload() async {
    if (_webviewFailed) return;
    await _webviewController?.reload();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || !uri.hasScheme) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          if (!_webviewFailed)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: _reload,
            ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in browser',
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: _webviewFailed ? _buildFallback() : _buildWebview(),
    );
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
              color: colorScheme.surface.withValues(alpha: 0.6),
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
      icon: Icons.language,
      title: 'Built-in viewer unavailable',
      subtitle:
          'This platform has no built-in web viewer. '
          'Open the article in your default browser instead.',
      action: NexusButton(
        label: 'Open in Browser',
        icon: Icons.open_in_browser,
        onPressed: _openInBrowser,
      ),
    );
  }
}
