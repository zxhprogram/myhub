import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/video_models.dart';
import '../models/video_site_config.dart';
import 'video_site_exception.dart';

/// Scrapes a 555电影-protocol site (an mxtheme MacCMS deployment, by
/// default 5555dy.cc) for the video sub-app.
///
/// Every page of the site sits behind an nginx challenge: the first
/// request answers 403 and issues a short-lived cookie, and replaying the
/// request with that cookie yields the real page (see [_challengeGet]).
///
/// Four data paths are used:
///  * Browse list — the `/frim/{typeId}.html` channel pages. They are
///    showcase style ("新片上线" / "排行榜" / "最近更新" sections) with no
///    pagination, so all sections are merged — deduplicated by detail
///    link — into a single page.
///  * Search — `GET /index.php/ajax/suggest?mid=1&wd=...`, the JSON
///    autocomplete API behind the site's search box (the same endpoint
///    shape the netflixgc protocol uses).
///  * Detail pages — server-rendered `/movie/{id}.html` parsed with
///    regular expressions, following the same approach as the netflixgc
///    parser (no XML/HTML package dependency).
///  * Play pages — `/play/{id}-{source}-{episode}.html` whose
///    `player_aaaa` payload carries the stream URL directly
///    (`encrypt: 0` on this deployment), so playback needs no cloud
///    parse step.
class Movie555SiteService {
  /// Creates a scraper for the site described by [config].
  Movie555SiteService({required VideoSiteConfig config})
    : _config = config,
      _dio = Dio(
        BaseOptions(
          baseUrl: config.origin,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          // The challenge answers 403; absorbing its Set-Cookie headers
          // requires letting that status through instead of throwing.
          validateStatus: (status) => status != null && status < 500,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/125.0.0.0 Safari/537.36',
          },
        ),
      );

  final VideoSiteConfig _config;

  final Dio _dio;

  /// Cookie granted by the site's 403 challenge, echoed on every request
  /// until it expires — at which point the challenge simply runs again.
  String _challengeCookie = '';

  /// Channel page of each browse category. The 555 deployment has no
  /// documentary channel, so that tab falls back to the movie channel.
  static const Map<VideoCategory, String> _categoryChannels = {
    VideoCategory.movies: '/frim/1.html',
    VideoCategory.series: '/frim/2.html',
    VideoCategory.variety: '/frim/3.html',
    VideoCategory.anime: '/frim/4.html',
    VideoCategory.documentary: '/frim/1.html',
  };

  // ------------------------------------------------------------------
  // Browse list
  // ------------------------------------------------------------------

  /// Fetches the browse list of a category. Channel pages are single-page
  /// showcases, so anything beyond [page] 1 is empty and [pageCount] is
  /// always 1.
  Future<VideoSeriesPage> fetchSeries({
    VideoCategory category = VideoCategory.series,
    int page = 1,
  }) async {
    if (page > 1) {
      return VideoSeriesPage(items: const [], page: page, pageCount: 1, total: 0);
    }
    final html = await _getHtml(_categoryChannels[category]!);
    final items = Movie555ChannelParser.parseSeries(html);
    return VideoSeriesPage(
      items: items,
      page: 1,
      pageCount: 1,
      total: items.length,
    );
  }

  // ------------------------------------------------------------------
  // Search
  // ------------------------------------------------------------------

  /// Searches by title through the site's suggest API (max 20 hits).
  Future<List<VideoSeries>> search(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return const [];
    final body = await _getJson(
      '/index.php/ajax/suggest',
      queryParameters: {'mid': '1', 'wd': trimmed},
    );
    if ((body['code'] as num?)?.toInt() != 1) return const [];
    return (body['list'] as List<dynamic>? ?? const [])
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

  /// Scrapes a series detail page (`/movie/{id}.html`), including the
  /// playback sources and their episode lists.
  Future<VideoDetail> fetchDetail(int vodId) async {
    final html = await _getHtml('/movie/$vodId.html');
    final detail = Movie555DetailParser.parse(html, vodId);
    if (detail.title.isEmpty && detail.sources.isEmpty) {
      throw StateException('Detail page could not be parsed (id $vodId)');
    }
    return detail;
  }

  // ------------------------------------------------------------------
  // Play page
  // ------------------------------------------------------------------

  /// Resolves one episode's play page (`/play/{id}-{source}-{ep}.html`)
  /// into a directly playable stream URL.
  ///
  /// The play page embeds a `player_aaaa` payload whose `url` field is
  /// the stream (an HLS playlist on this deployment, `encrypt: 0`).
  /// `link_next` provides the play path of the next episode for
  /// auto-advance.
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
    final streamUrl = switch (encrypt) {
      2 => _percentDecode(_base64Decode(rawUrl)),
      1 => _percentDecode(rawUrl),
      _ => rawUrl,
    };

    final vodData = payload['vod_data'];
    final vodName =
        vodData is Map<String, dynamic>
            ? (vodData['vod_name'] as String? ?? '')
            : '';

    return VideoPlayInfo(
      title: vodName,
      episodeLabel: episodeLabel,
      rawUrl: streamUrl,
      streamUrl: streamUrl,
      nextPlayPath: (payload['link_next'] as String?)?.isNotEmpty == true
          ? payload['link_next'] as String
          : null,
    );
  }

  // ------------------------------------------------------------------
  // Internals
  // ------------------------------------------------------------------

  Future<String> _getHtml(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await _challengeGet<String>(
      path,
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    // Fetched as plain text so the 403 challenge page (HTML) never runs
    // through the JSON transformer.
    final body = await _getHtml(path, queryParameters: queryParameters);
    try {
      return Map<String, dynamic>.from(jsonDecode(body) as Map);
    } on FormatException {
      return const <String, dynamic>{};
    }
  }

  /// Runs a GET through the site's cookie challenge: a 403 answer hands
  /// out the cookie via Set-Cookie, and one replay with it succeeds.
  /// Responses other than 200 (after the retry) fail with a
  /// [StateException].
  Future<Response<T>> _challengeGet<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    var response = await _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: _withCookie(options),
    );
    if (response.statusCode == 403) {
      _absorbChallengeCookie(response);
      response = await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: _withCookie(options),
      );
    }
    if (response.statusCode != 200) {
      throw StateException(
        '${_config.domain} 返回异常状态码（${response.statusCode}）',
      );
    }
    return response;
  }

  Options? _withCookie(Options? options) {
    if (_challengeCookie.isEmpty) return options;
    final headers = Map<String, dynamic>.from(options?.headers ?? {});
    headers['Cookie'] = _challengeCookie;
    return (options ?? Options()).copyWith(headers: headers);
  }

  /// Merges the `name=value` pairs of the response's Set-Cookie headers
  /// into [_challengeCookie]. The challenge cookie's name rotates, so the
  /// pairs are kept in a map keyed by name.
  void _absorbChallengeCookie(Response<dynamic> response) {
    final pairs = <String, String>{};
    for (final pair in _challengeCookie.split(';')) {
      final eq = pair.indexOf('=');
      if (eq > 0) pairs[pair.substring(0, eq).trim()] = pair.substring(eq + 1);
    }
    for (final raw in response.headers['set-cookie'] ?? const <String>[]) {
      final pair = raw.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq > 0) pairs[pair.substring(0, eq).trim()] = pair.substring(eq + 1);
    }
    _challengeCookie = pairs.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Mirrors the JS `unescape()` used by MacCMS players: decodes `%XX`
  /// sequences and leaves anything invalid untouched.
  static String _percentDecode(String input) {
    if (!input.contains('%')) return input;
    return input.replaceAllMapped(
      RegExp('%([0-9A-Fa-f]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
  }

  /// Base64-decodes an encrypted resource reference. The payload is ASCII
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

/// Parses a `/frim/{typeId}.html` channel page into poster items.
///
/// Layout notes (mxtheme MacCMS template): every section ("新片上线" /
/// "排行榜" / "最近更新") renders the same `a.module-poster-item` cards —
/// cover in `data-original`, broadcast state in `.module-item-note`,
/// title in `.module-poster-item-title` — and the same series can appear
/// in several sections, so items are deduplicated by detail link.
abstract final class Movie555ChannelParser {
  static final RegExp _itemRe = RegExp(
    r'<a href="(/movie/\d+\.html)"[^>]*class="module-poster-item[^"]*">([\s\S]*?)</a>',
  );
  static final RegExp _noteRe = RegExp(r'class="module-item-note">([^<]*)<');
  static final RegExp _coverRe = RegExp(r'data-original="([^"]+)"');
  static final RegExp _titleRe = RegExp(
    r'class="module-poster-item-title">([^<]*)<',
  );

  static List<VideoSeries> parseSeries(String html) {
    final seen = <String>{};
    final items = <VideoSeries>[];
    for (final match in _itemRe.allMatches(html)) {
      final href = match.group(1) ?? '';
      final inner = match.group(2) ?? '';
      if (href.isEmpty || !seen.add(href)) continue;
      final id = int.tryParse(
        RegExp(r'/movie/(\d+)\.html').firstMatch(href)?.group(1) ?? '',
      );
      if (id == null) continue;
      final title = _decodeEntities(
        _titleRe.firstMatch(inner)?.group(1) ?? '',
      ).trim();
      items.add(
        VideoSeries(
          id: id,
          title: title,
          coverUrl: _coverRe.firstMatch(inner)?.group(1) ?? '',
          remarks: _decodeEntities(
            _noteRe.firstMatch(inner)?.group(1) ?? '',
          ).trim(),
          blurb: '',
        ),
      );
    }
    return items;
  }

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

/// Parses a `/movie/{id}.html` detail page into a [VideoDetail].
///
/// Layout notes (mxtheme MacCMS template): the heading block carries the
/// `h1` title, poster and the year/area/genre tag links; metadata rows
/// are labelled `导演：` / `主演：` / `备注：`; playback sources are the
/// `data-dropdown-value` tabs of the `y-playList` box, each paired with
/// the `panel{n}` episode list that follows in the same order. Episode
/// anchors point at `/play/{vodId}-{sourceId}-{episode}.html`.
abstract final class Movie555DetailParser {
  static final RegExp _titleRe = RegExp(
    r'<div class="module-info-heading">\s*<h1>([^<]+)</h1>',
  );
  static final RegExp _coverRe = RegExp(
    r'class="module-info-poster"[\s\S]{0,600}?data-original="([^"]+)"',
  );
  static final RegExp _tagRe = RegExp(
    r'<div class="module-info-tag-link"><a[^>]*>([^<]*)</a>',
  );
  static final RegExp _synopsisRe = RegExp(
    r'class="module-info-introduction-content[^"]*"[^>]*>\s*<p>([\s\S]*?)</p>',
  );
  static final RegExp _metaSynopsisRe = RegExp(
    r'<meta name="description" content="([^"]*)"',
  );
  static final RegExp _actorsBlockRe = RegExp(
    r'主演：</span>\s*<div class="module-info-item-content">([\s\S]*?)</div>',
  );
  static final RegExp _remarksRe = RegExp(
    r'备注：</span>\s*<div class="module-info-item-content">(?:<p[^>]*>)?([^<]*)',
  );
  static final RegExp _anchorTextRe = RegExp(r'<a[^>]*>([^<]*)</a>');
  static final RegExp _tabRe = RegExp(r'data-dropdown-value="([^"]+)"');
  static final RegExp _panelRe = RegExp(r'id="(panel\d+)"');
  static final RegExp _episodeLinkRe = RegExp(
    r'<a class="module-play-list-link" href="(/play/[^"]+)"[^>]*>\s*<span>([^<]*)</span>',
  );
  static final RegExp _tagStripRe = RegExp(r'<[^>]+>');
  static final RegExp _whitespaceRe = RegExp(r'\s+');

  /// Episodes blocks end where the "相关推荐" module begins.
  static const String _relatedMarker = '相关推荐';

  static VideoDetail parse(String html, int vodId) {
    final title = _decodeEntities(_titleRe.firstMatch(html)?.group(1) ?? '')
        .trim();

    final tags = _tagRe
        .allMatches(html)
        .map((m) => _decodeEntities(m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    // Tag order on the page is year, area, then genres; deployments that
    // omit the year start with the area instead.
    final yearIndex = tags.indexWhere((t) => RegExp(r'^\d{4}$').hasMatch(t));
    final String year;
    final String area;
    final Iterable<String> genreTags;
    if (yearIndex >= 0) {
      year = tags[yearIndex];
      area = yearIndex + 1 < tags.length ? tags[yearIndex + 1] : '';
      genreTags = tags.skip(yearIndex + 2);
    } else {
      year = '';
      area = tags.isNotEmpty ? tags.first : '';
      genreTags = tags.skip(1);
    }
    final genres = genreTags.join(', ');

    final actors = _anchorTextRe
        .allMatches(_actorsBlockRe.firstMatch(html)?.group(1) ?? '')
        .map((m) => _decodeEntities(m.group(1) ?? '').trim())
        .where((t) => t.isNotEmpty)
        .join(' ');

    final synopsis = _decodeEntities(
      _synopsisRe.firstMatch(html)?.group(1) ??
          _metaSynopsisRe.firstMatch(html)?.group(1) ??
          '',
    ).replaceAll(_tagStripRe, '').replaceAll(_whitespaceRe, ' ').trim();

    return VideoDetail(
      id: vodId,
      title: title,
      coverUrl: _coverRe.firstMatch(html)?.group(1) ?? '',
      synopsis: synopsis,
      remarks: _decodeEntities(
        _remarksRe.firstMatch(html)?.group(1) ?? '',
      ).trim(),
      year: year,
      area: area,
      actors: actors,
      genres: genres,
      score: null,
      sources: _parseSources(html),
    );
  }

  /// Tab names and `panel{n}` episode blocks appear in the same order, so
  /// the i-th tab label describes the i-th panel.
  static List<VideoSource> _parseSources(String html) {
    final tabNames = _tabRe
        .allMatches(html)
        .map((m) => _decodeEntities(m.group(1) ?? '').trim())
        .toList();

    final panels = _panelRe.allMatches(html).toList();
    final relatedStart = html.indexOf(_relatedMarker);
    final sources = <VideoSource>[];
    for (var i = 0; i < panels.length; i++) {
      final start = panels[i].end;
      var end = i + 1 < panels.length ? panels[i + 1].start : html.length;
      if (relatedStart > start && end > relatedStart) end = relatedStart;
      final episodes = <VideoEpisode>[];
      for (final match in _episodeLinkRe.allMatches(
        html.substring(start, end),
      )) {
        final playPath = match.group(1) ?? '';
        final label = _decodeEntities(match.group(2) ?? '').trim();
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
      final name = i < tabNames.length && tabNames[i].isNotEmpty
          ? tabNames[i]
          : '源${i + 1}';
      sources.add(VideoSource(name: name, episodes: episodes));
    }
    return sources;
  }

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
