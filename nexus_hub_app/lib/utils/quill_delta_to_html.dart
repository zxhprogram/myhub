import 'dart:convert';

/// Converts a Quill Delta JSON string into an HTML string.
///
/// flutter_quill 11.x does not ship a Delta-to-HTML converter, so this
/// lightweight walker covers the formatting exposed by [NexusRichTextEditor]:
/// bold, italic, underline, links, bullet/numbered lists, images, and headers.
class QuillDeltaToHtml {
  QuillDeltaToHtml._();

  /// Converts [deltaJson] (a JSON-encoded list of Delta operations) into HTML.
  /// Returns an empty string if the input is null or empty.
  static String convert(String? deltaJson) {
    if (deltaJson == null || deltaJson.trim().isEmpty) return '';
    final List<dynamic> ops;
    try {
      ops = jsonDecode(deltaJson) as List<dynamic>;
    } catch (_) {
      return _escapeHtml(deltaJson);
    }
    if (ops.isEmpty) return '';

    // Flatten ops into a list of tokens: text characters with inline attrs,
    // image embeds, and newline markers with block attrs.
    final tokens = <_Token>[];
    for (final op in ops) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert == null) continue;
      final attrs = op['attributes'] is Map
          ? Map<String, dynamic>.from(op['attributes'] as Map)
          : <String, dynamic>{};

      if (insert is String) {
        for (var i = 0; i < insert.length; i++) {
          final ch = insert[i];
          if (ch == '\n') {
            tokens.add(_Token.newline(attrs));
          } else {
            tokens.add(_Token.text(ch, attrs));
          }
        }
      } else if (insert is Map && insert['image'] is String) {
        tokens.add(_Token.image(insert['image'] as String, attrs));
      }
    }

    // Group tokens into lines separated by newline tokens. Each newline
    // carries the block-level attributes for the line it terminates.
    final buffer = StringBuffer();
    var lineStart = 0;
    for (var i = 0; i < tokens.length; i++) {
      if (tokens[i].isNewline) {
        _emitLine(buffer, tokens, lineStart, i, tokens[i].attrs);
        lineStart = i + 1;
      }
    }
    // Emit any trailing content without a terminating newline.
    if (lineStart < tokens.length) {
      _emitLine(buffer, tokens, lineStart, tokens.length, {});
    }
    return buffer.toString();
  }

  static void _emitLine(
    StringBuffer buffer,
    List<_Token> tokens,
    int start,
    int end,
    Map<String, dynamic> blockAttrs,
  ) {
    // Skip empty lines — they produce no meaningful email content.
    if (start >= end) return;
    final hasContent = tokens
        .sublist(start, end)
        .any((t) => t.isImage || (t.text != null && t.text!.isNotEmpty));
    if (!hasContent) return;

    final inlineHtml = _renderInline(tokens, start, end);

    if (blockAttrs['list'] == 'bullet') {
      buffer.write('<ul><li>$inlineHtml</li></ul>');
    } else if (blockAttrs['list'] == 'ordered') {
      buffer.write('<ol><li>$inlineHtml</li></ol>');
    } else if (blockAttrs['header'] is int) {
      final level = (blockAttrs['header'] as int).clamp(1, 6);
      buffer.write('<h$level>$inlineHtml</h$level>');
    } else if (blockAttrs['blockquote'] == true) {
      buffer.write('<blockquote>$inlineHtml</blockquote>');
    } else {
      buffer.write('<p>$inlineHtml</p>');
    }
  }

  static String _renderInline(List<_Token> tokens, int start, int end) {
    final buffer = StringBuffer();
    for (var i = start; i < end; i++) {
      final t = tokens[i];
      if (t.isImage) {
        buffer.write('<img src="${_escapeAttr(t.imageSrc!)}" />');
      } else if (t.text != null) {
        buffer.write(_wrapInline(t.text!, t.attrs));
      }
    }
    return buffer.toString();
  }

  static String _wrapInline(String text, Map<String, dynamic> attrs) {
    var html = _escapeHtml(text);
    if (attrs['link'] is String) {
      html = '<a href="${_escapeAttr(attrs['link'] as String)}">$html</a>';
    }
    if (attrs['bold'] == true) {
      html = '<strong>$html</strong>';
    }
    if (attrs['italic'] == true) {
      html = '<em>$html</em>';
    }
    if (attrs['underline'] == true) {
      html = '<u>$html</u>';
    }
    return html;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  static String _escapeAttr(String text) {
    return _escapeHtml(text).replaceAll('"', '&quot;');
  }
}

class _Token {
  _Token.text(this._text, this.attrs)
      : imageSrc = null,
        isNewline = false;
  _Token.image(this.imageSrc, this.attrs)
      : _text = null,
        isNewline = false;
  _Token.newline(this.attrs)
      : _text = null,
        imageSrc = null,
        isNewline = true;

  final String? _text;
  final String? imageSrc;
  final Map<String, dynamic> attrs;
  final bool isNewline;

  bool get isImage => imageSrc != null;
  String? get text => _text;
}
