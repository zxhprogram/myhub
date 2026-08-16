import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/video_models.dart';

/// Scrapes netflixgc.com (a MacCMS V10 video site) for the video sub-app.
///
/// Three data paths are used:
///  * Browse list — the site's own JSON endpoint `POST /index.php/ds_api/vod`
///    that the web list page loads its grid from.
///  * Search — `GET /index.php/ajax/suggest?mid=1&wd=...`, the JSON
///    autocomplete API behind the site's search box.
///  * Detail / play pages — server-rendered HTML parsed with regular
///    expressions, following the same approach as the Google News RSS
///    parser (no XML/HTML package dependency).
///
/// Play pages encrypt the raw resource reference inside a `player_aaaa`
/// payload (`encrypt: 2` = base64 + percent-encoding). After decrypting, the
/// reference is handed to the site's cloud parse player, which is what gets
/// embedded in the in-app WebView.
class VideoSiteService {
  VideoSiteService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://www.netflixgc.com',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                    'AppleWebKit/537.36 (KHTML, like Gecko) '
                    'Chrome/125.0.0.0 Safari/537.36',
              },
            ),
          );

  final Dio _dio;

  /// Cloud parse player used by every playback source on this site (see the
  /// site's `playerconfig.js`); it resolves the encrypted resource reference
  /// into a streamable video inside an embeddable HTML page.
  static const String _parsePlayerPrefix =
      'https://cjbfq.netflixgc.tv/player/ec.php?code=netflix&if=1&url=';

  // ------------------------------------------------------------------
  // Browse list
  // ------------------------------------------------------------------

  /// Fetches one page of a browse list (movies / series / variety, sorted
  /// by recency).
  ///
  /// An empty [items] list with the requested [page] means the site reported
  /// "no more data" (endpoint code 2).
  Future<VideoSeriesPage> fetchSeries({
    VideoCategory category = VideoCategory.series,
    int page = 1,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/index.php/ds_api/vod',
      data: {
        'type': category.typeId,
        'class': '',
        'area': '',
        'year': '',
        'lang': '',
        'version': '',
        'state': '',
        'letter': '',
        'time': '',
        'level': '0',
        'weekday': '',
        'by': 'time',
        'page': '$page',
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final data = response.data ?? const <String, dynamic>{};
    final code = (data['code'] as num?)?.toInt() ?? 0;
    if (code != 1) {
      // code 2 = no more data; anything else surfaces as an empty page.
      return VideoSeriesPage(items: const [], page: page, pageCount: 0, total: 0);
    }
    final list = (data['list'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(VideoSeries.fromJson)
        .toList();
    return VideoSeriesPage(
      items: list,
      page: (data['page'] as num?)?.toInt() ?? page,
      pageCount: (data['pagecount'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------

  /// Searches by title through the site's suggest API (max 20 hits).
  Future<List<VideoSeries>> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];
    final response = await _dio.get<Map<String, dynamic>>(
      '/index.php/ajax/suggest',
      queryParameters: {'mid': '1', 'wd': trimmed},
    );
    final data = response.data ?? const <String, dynamic>{};
    if ((data['code'] as num?)?.toInt() != 1) return const [];
    return (data['list'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(
          (item) => VideoSeries(
            id: (item['id'] as num?)?.toInt() ?? 0,
            title: (item['name'] as String?) ?? '',
            coverUrl: (item['pic'] as String?) ?? '',
            remarks: '',
            blurb: '',
          ),
        )
        .toList();
  }

  // ------------------------------------------------------------------
  // Detail page
  // ------------------------------------------------------------------

  /// Scrapes a series detail page (`/voddetail/{id}.html`), including the
  /// playback sources and their episode lists.
  Future<VideoDetail> fetchDetail(int vodId) async {
    final html = await _getHtml('/voddetail/$vodId.html');
    final detail = VideoSiteDetailParser.parse(html, vodId);
    if (detail.title.isEmpty && detail.sources.isEmpty) {
      throw StateException('Detail page could not be parsed (id $vodId)');
    }
    return detail;
  }

  // ------------------------------------------------------------------
  // Play page
  // ------------------------------------------------------------------

  /// Resolves one episode's play page (`/vodplay/{id}-{source}-{ep}.html`)
  /// into the embeddable cloud player URL.
  Future<VideoPlayInfo> resolvePlay({
    required String playPath,
    required String episodeLabel,
  }) async {
    final html = await _getHtml(playPath);
    final match = RegExp(
      r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*;?\s*</script>',
    ).firstMatch(html);
    if (match == null) {
      throw StateException('No player payload on $playPath');
    }

    final Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode(match.group(1)!) as Map,
      );
    } on FormatException {
      throw StateException('Malformed player payload on $playPath');
    }

    final encrypt = (payload['encrypt'] as num?)?.toInt() ?? 0;
    final rawUrl = (payload['url'] as String?) ?? '';
    if (rawUrl.isEmpty) {
      throw StateException('Empty resource URL on $playPath');
    }
    final decrypted = switch (encrypt) {
      2 => _percentDecode(_base64Decode(rawUrl)),
      1 => _percentDecode(rawUrl),
      _ => rawUrl,
    };

    final vodData = payload['vod_data'];
    final vodName =
        vodData is Map<String, dynamic> ? (vodData['vod_name'] as String? ?? '') : '';

    return VideoPlayInfo(
      title: vodName,
      episodeLabel: episodeLabel,
      rawUrl: decrypted,
      playerUrl: '$_parsePlayerPrefix${Uri.encodeComponent(decrypted)}',
      nextPlayPath: (payload['link_next'] as String?)?.isNotEmpty == true
          ? payload['link_next'] as String
          : null,
    );
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Future<String> _getHtml(String path) async {
    final response = await _dio.get<String>(
      path,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  /// Mirrors the JS `unescape()` used by the site player: decodes `%XX`
  /// sequences and leaves anything invalid untouched. `%uXXXX` is not used
  /// by this site and therefore not handled.
  static String _percentDecode(String input) {
    if (!input.contains('%')) return input;
    return input.replaceAllMapped(
      RegExp('%([0-9A-Fa-f]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
  }

  /// Base64-decodes the encrypted resource reference. The payload is ASCII
  /// percent-encoded text, so latin1 is the exact decoding.
  static String _base64Decode(String input) {
    var normalized = input.trim();
    normalized += '=' * ((4 - normalized.length % 4) % 4);
    try {
      return latin1.decode(base64Decode(normalized));
    } on FormatException {
      return input;
    }
  }
}

/// Exception thrown when a scraped page does not contain the expected data.
class StateException implements Exception {
  StateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Parses a `/voddetail/{id}.html` page into a [VideoDetail].
///
/// Layout notes (dsn2 MacCMS template): the playback source tabs live in
/// `.anthology-tab` and their episode lists in the `.anthology-list-box`
/// divs that follow, in the same order. Each episode anchor points at
/// `/vodplay/{vodId}-{sourceId}-{episode}.html`.
abstract final class VideoSiteDetailParser {
  static final RegExp _titleRe = RegExp(
    r'<h3 class="slide-info-title[^"]*">([^<]+)</h3>',
  );
  static final RegExp _coverRe = RegExp(
    r'class="detail-pic"[\s\S]{0,600}?data-src="([^"]+)"',
  );
  static final RegExp _infoBlockRe = RegExp(
    r'<div class="slide-info hide">([\s\S]*?)</div>',
  );
  static final RegExp _remarksRe = RegExp(
    r'<span class="slide-info-remarks[^"]*">([^<]+)</span>',
  );
  static final RegExp _yearRe = RegExp(r'<a[^>]*>(\d{4})</a>');
  static final RegExp _actorsBlockRe = RegExp(r'演员\s*:</strong>([\s\S]*?)</div>');
  static final RegExp _genresBlockRe = RegExp(r'类型\s*:</strong>([\s\S]*?)</div>');
  static final RegExp _anchorTextRe = RegExp(r'<a[^>]*>([^<]+)</a>');
  static final RegExp _scoreRe = RegExp(r'<div class="fraction">([\d.]+)</div>');
  static final RegExp _synopsisRe = RegExp(
    r'<meta name="description" content="([^"]*)"',
  );
  static final RegExp _tabBlockRe = RegExp(
    r'<div class="anthology-tab[^"]*">([\s\S]*?)<div class="anthology-list',
  );
  static final RegExp _tabRe = RegExp(r'<a class="swiper-slide">([\s\S]*?)</a>');
  static final RegExp _episodeLinkRe = RegExp(
    r'<a[^>]*href="(/vodplay/[^"]+)"[^>]*>([^<]*)</a>',
  );
  static final RegExp _badgeRe = RegExp(r'<span class="badge">[^<]*</span>');
  static final RegExp _tagRe = RegExp(r'<[^>]+>');
  static final RegExp _whitespaceRe = RegExp(r'\s+');

  static const String _boxMarker = 'class="anthology-list-box';

  static VideoDetail parse(String html, int vodId) {
    final title = _decodeEntities(
      _first(_titleRe, html) ?? '',
    ).trim();

    final infoBlock = _infoBlockRe.firstMatch(html)?.group(1) ?? '';
    final plainRemarks = _remarksRe
        .allMatches(infoBlock)
        .map((m) => _decodeEntities(m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final year = _yearRe.firstMatch(infoBlock)?.group(1) ?? '';

    final actors = _anchorTextRe
        .allMatches(_actorsBlockRe.firstMatch(html)?.group(1) ?? '')
        .map((m) => _decodeEntities(m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .join(' ');

    final genres = _anchorTextRe
        .allMatches(_genresBlockRe.firstMatch(html)?.group(1) ?? '')
        .map((m) => _decodeEntities(m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .join(', ');

    final scoreText = _scoreRe.firstMatch(html)?.group(1);
    final score = scoreText == null ? null : double.tryParse(scoreText);

    final sources = _parseSources(html);

    return VideoDetail(
      id: vodId,
      title: title,
      coverUrl: _first(_coverRe, html) ?? '',
      synopsis: _decodeEntities(
        _first(_synopsisRe, html) ?? '',
      ).trim(),
      remarks: plainRemarks.isNotEmpty ? plainRemarks.first : '',
      year: year,
      area: plainRemarks.length > 1 ? plainRemarks.last : '',
      actors: actors,
      genres: genres,
      score: (score != null && score > 0) ? score : null,
      sources: sources,
    );
  }

  /// Tab names and episode boxes are siblings in the DOM and share their
  /// order, so the i-th tab label describes the i-th box.
  static List<VideoSource> _parseSources(String html) {
    final tabBlock = _tabBlockRe.firstMatch(html)?.group(1) ?? html;
    final tabNames = _tabRe
        .allMatches(tabBlock)
        .map((m) => _cleanTabName(m.group(1) ?? ''))
        .toList();

    final segments = html.split(_boxMarker);
    final sources = <VideoSource>[];
    for (var i = 1; i < segments.length; i++) {
      final episodes = <VideoEpisode>[];
      for (final match in _episodeLinkRe.allMatches(segments[i])) {
        final playPath = match.group(1) ?? '';
        final label = _decodeEntities(
          match.group(2) ?? '',
        ).trim();
        if (playPath.isEmpty) continue;
        episodes.add(
          VideoEpisode(
            index: episodes.length + 1,
            label: label.isEmpty ? '${episodes.length + 1}' : label,
            playPath: playPath,
          ),
        );
      }
      if (episodes.isEmpty) continue;
      final name = i - 1 < tabNames.length && tabNames[i - 1].isNotEmpty
          ? tabNames[i - 1]
          : '源$i';
      sources.add(VideoSource(name: name, episodes: episodes));
    }
    return sources;
  }

  static String _cleanTabName(String raw) {
    return _decodeEntities(
      raw.replaceAll(_badgeRe, '').replaceAll(_tagRe, ''),
    ).replaceAll(_whitespaceRe, ' ').trim();
  }

  static String? _first(RegExp re, String input) => re.firstMatch(input)?.group(1);

  /// Decodes the HTML entities emitted by this site (basic named entities
  /// plus numeric references).
  static String _decodeEntities(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAllMapped(
          RegExp(r'&#x([0-9a-fA-F]+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
        )
        .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)),
        );
  }
}
