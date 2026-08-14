import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/models/google_news_item.dart';
import '../../theme/typography.dart';
import '../components/nexus_button.dart';
import '../components/nexus_empty_state.dart';

/// In-app web reader that opens a news article inside a [WebViewWidget].
///
/// Falls back to an "open in browser" prompt when the platform has no WebView
/// implementation (e.g. Windows desktop), so the feature degrades gracefully.
class GoogleNewsArticlePage extends StatefulWidget {
  const GoogleNewsArticlePage({super.key, required this.item});

  final GoogleNewsItem item;

  @override
  State<GoogleNewsArticlePage> createState() => _GoogleNewsArticlePageState();
}

class _GoogleNewsArticlePageState extends State<GoogleNewsArticlePage> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _webviewFailed = false;

  @override
  void initState() {
    super.initState();
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => _setLoading(true),
            onPageFinished: (_) => _setLoading(false),
          ),
        )
        ..loadRequest(Uri.parse(widget.item.link));
    } catch (_) {
      // Platform without a WebView implementation (e.g. Windows desktop).
      _webviewFailed = true;
    }
  }

  void _setLoading(bool loading) {
    if (!mounted) return;
    setState(() => _isLoading = loading);
  }

  Future<void> _reload() async {
    if (_webviewFailed) return;
    await _controller.reload();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.item.link);
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
          widget.item.title,
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
        WebViewWidget(controller: _controller),
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
