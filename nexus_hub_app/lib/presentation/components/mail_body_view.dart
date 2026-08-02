import 'dart:convert';

// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mime_part.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../theme/colors.dart';
import '../../theme/typography.dart';

/// Renders the body of an email message using [HtmlWidget] from
/// `flutter_widget_from_html`.
///
/// The widget:
/// * Prefers the HTML body when available, falling back to the plain-text body
///   wrapped in a minimal HTML document.
/// * Injects CSS to match the app's theme (font, colors, spacing).
/// * Resolves CID (Content-ID) image references in the HTML by scanning the
///   MIME part tree and converting matching inline image parts to base64 data
///   URIs, so that inline images render correctly even when the message is
///   loaded from cache.
class MailBodyView extends StatelessWidget {
  const MailBodyView({super.key, required this.message});

  final MailMessage message;

  @override
  Widget build(BuildContext context) {
    final html = _buildHtml();
    return HtmlWidget(
      html,
      textStyle: NexusTypography.bodyLg.copyWith(
        height: 1.5,
        color: NexusColors.onSurface,
      ),
    );
  }

  String _buildHtml() {
    // Build a CID-to-data-URI map from the MIME tree.
    final cidMap = _buildCidMap();

    // Prefer HTML body; fall back to plain text wrapped in a minimal document.
    final bodyHtml = message.htmlBody.isNotEmpty
        ? _resolveCidReferences(message.htmlBody, cidMap)
        : _escapePlainText(message.plainTextBody);

    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
    font-size: 15px;
    line-height: 1.5;
    color: #0B1C30;
    background: transparent;
    margin: 0;
    padding: 0;
    word-wrap: break-word;
    overflow-wrap: break-word;
  }
  a { color: #0058BE; }
  blockquote {
    margin: 12px 0;
    padding: 8px 16px;
    border-left: 3px solid #C6C6CD;
    color: #45464D;
  }
  img { max-width: 100%; height: auto; }
  table { border-collapse: collapse; width: 100%; }
  td, th { padding: 8px; border: 1px solid #C6C6CD; }
  pre, code {
    font-family: 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
    font-size: 13px;
    background: #EFF4FF;
    padding: 2px 4px;
    border-radius: 4px;
  }
  pre { padding: 12px; overflow-x: auto; }
  pre code { background: none; padding: 0; }
  hr { border: none; border-top: 1px solid #C6C6CD; margin: 16px 0; }
  h1, h2, h3, h4, h5, h6 { margin: 16px 0 8px; }
  p { margin: 0 0 8px; }
  ul, ol { margin: 8px 0; padding-left: 24px; }
</style>
</head>
<body>
$bodyHtml
</body>
</html>
''';
  }

  /// Traverses the MIME tree to build a map of content-id → base64 data URI.
  Map<String, String> _buildCidMap() {
    final map = <String, String>{};
    _collectCidParts(message.root, map);
    return map;
  }

  void _collectCidParts(MimePart part, Map<String, String> map) {
    final cid = part.headers['content-id'];
    if (cid != null && part.body != null && part.body!.isNotEmpty) {
      final cleanCid = cid.trim();
      // Content-ID may be wrapped in angle brackets: <...>.
      final stripped = cleanCid.startsWith('<') && cleanCid.endsWith('>')
          ? cleanCid.substring(1, cleanCid.length - 1)
          : cleanCid;
      final base64 = base64Encode(part.body!);
      map[stripped] = 'data:${part.contentType};base64,$base64';
    }
    for (final child in part.children) {
      _collectCidParts(child, map);
    }
  }

  /// Replaces `cid:...` references in the HTML with data URIs from [cidMap].
  String _resolveCidReferences(String html, Map<String, String> cidMap) {
    if (cidMap.isEmpty) return html;
    final cidRegex = RegExp(r'cid:([^\s">&]+)');
    return html.replaceAllMapped(cidRegex, (match) {
      final cid = match.group(1)!;
      final dataUri = cidMap[cid];
      if (dataUri != null) return dataUri;
      return match.group(0)!;
    });
  }

  /// Escapes plain text for display as HTML.
  String _escapePlainText(String text) {
    if (text.isEmpty) return '<p>No content</p>';
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;');
    final paragraphs = escaped.split('\n\n');
    return paragraphs
        .map((p) {
          final withBreaks = p.replaceAll('\n', '<br>');
          return '<p>$withBreaks</p>';
        })
        .join('\n');
  }
}
