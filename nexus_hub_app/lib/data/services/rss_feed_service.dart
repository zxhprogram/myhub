import 'dart:io';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

/// One article parsed out of an RSS/Atom document.
class ParsedRssArticle {
  const ParsedRssArticle({
    required this.title,
    required this.url,
    this.summary = '',
    required this.publishedAt,
  });

  final String title;
  final String url;
  final String summary;
  final DateTime publishedAt;
}

/// Result of fetching and parsing a feed URL.
class ParsedRssFeed {
  const ParsedRssFeed({required this.title, required this.articles});

  final String title;
  final List<ParsedRssArticle> articles;
}

/// Fetches and parses RSS 2.0 / Atom / RSS 1.0 (RDF) feeds over HTTP.
class RssFeedService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 5,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (compatible; NexusHub/1.0; +https://nexus-hub.app)',
        'Accept':
            'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
      },
      responseType: ResponseType.plain,
    ),
  );

  Future<ParsedRssFeed> fetch(String url) async {
    final response = await _dio.get<String>(url);
    final document = XmlDocument.parse(response.data ?? '');
    final channelTitle = _findText(document, ['channel>title', 'feed>title']) ??
        Uri.parse(url).host;

    final articles = <ParsedRssArticle>[];
    for (final item in document.findAllElements('item')) {
      final article = _parseRssItem(item);
      if (article != null) articles.add(article);
    }
    // Atom uses <entry> instead of <item>.
    for (final entry in document.findAllElements('entry')) {
      final article = _parseAtomEntry(entry);
      if (article != null) articles.add(article);
    }
    articles.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return ParsedRssFeed(title: channelTitle, articles: articles);
  }

  ParsedRssArticle? _parseRssItem(XmlElement item) {
    final title = _text(item, 'title');
    final link = _text(item, 'link') ?? _attr(item, 'link', 'href');
    if (title == null || title.isEmpty || link == null || link.isEmpty) {
      return null;
    }
    return ParsedRssArticle(
      title: title,
      url: link,
      summary: _stripTags(
        _text(item, 'description') ?? _text(item, 'content:encoded') ?? '',
      ),
      publishedAt: _parseDate(_text(item, 'pubDate') ?? _text(item, 'dc:date')),
    );
  }

  ParsedRssArticle? _parseAtomEntry(XmlElement entry) {
    final title = _text(entry, 'title');
    final link = entry.findElements('link').isNotEmpty
        ? _attr(entry, 'link', 'href')
        : null;
    if (title == null || title.isEmpty || link == null || link.isEmpty) {
      return null;
    }
    return ParsedRssArticle(
      title: title,
      url: link,
      summary: _stripTags(
        _text(entry, 'summary') ?? _text(entry, 'content') ?? '',
      ),
      publishedAt: _parseDate(
        _text(entry, 'published') ?? _text(entry, 'updated'),
      ),
    );
  }

  /// Looks up `parent>child` paths from the document root.
  String? _findText(XmlDocument document, List<String> paths) {
    for (final path in paths) {
      final parts = path.split('>');
      Iterable<XmlElement> elements = document.childElements;
      XmlElement? current;
      for (final part in parts) {
        current = _firstNamed(elements, part);
        if (current == null) break;
        elements = current.childElements;
      }
      final text = current?.innerText.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  XmlElement? _firstNamed(Iterable<XmlElement> elements, String localName) {
    for (final element in elements) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  String? _text(XmlElement parent, String localName) {
    for (final element in parent.childElements) {
      if (element.name.local == localName) {
        return element.innerText.trim();
      }
    }
    return null;
  }

  String? _attr(XmlElement parent, String localName, String attributeName) {
    for (final element in parent.childElements) {
      if (element.name.local == localName) {
        final value = element.getAttribute(attributeName) ??
            element.getAttribute('xmlns:$attributeName');
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String _stripTags(String html) {
    return html
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true), '')
        .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  DateTime _parseDate(String? value) {
    if (value != null && value.isNotEmpty) {
      // RFC 822 dates ("Mon, 25 Aug 2026 08:00:00 GMT").
      try {
        return HttpDate.parse(value).toLocal();
      } catch (_) {}
      // ISO 8601 dates commonly found in Atom feeds.
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();
    }
    return DateTime.now();
  }
}
