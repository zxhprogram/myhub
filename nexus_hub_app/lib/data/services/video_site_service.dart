import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pointycastle/export.dart';

import '../models/video_models.dart';
import '../models/video_site_config.dart';
import 'video_site_config_storage.dart';

/// Scrapes a netflixgc-protocol site (a MacCMS V10 deployment, by default
/// www.netflixgc.com) for the video sub-app.
///
/// The extraction rules below make up the netflixgc protocol; the two hosts
/// it talks to — the site itself and the cloud parse endpoint — come from
/// the [VideoSiteConfig] passed in (or the persisted one), because the
/// domains a deployment lives on change over time while the URL layout
/// does not.
///
/// Four data paths are used:
///  * Browse list — the site's own JSON endpoint `POST /index.php/ds_api/vod`
///    that the web list page loads its grid from.
///  * Search — `GET /index.php/ajax/suggest?mid=1&wd=...`, the JSON
///    autocomplete API behind the site's search box.
///  * Detail pages — server-rendered HTML parsed with regular expressions,
///    following the same approach as the Google News RSS parser (no
///    XML/HTML package dependency).
///  * Play pages — two layers of encryption, both decrypted natively:
///    the play page hides the resource reference in a `player_aaaa`
///    payload (`encrypt: 2` = base64 + percent-encoding), and the cloud
///    parse endpoint responds with a player page whose `ConFig` object
///    embeds the actual stream URL behind AES-128-CBC (key derived from a
///    per-request `uid`, mirroring the site player's `uic()` routine).
class VideoSiteService {
  /// Creates a scraper for the site described by [config], defaulting to
  /// the persisted configuration (see [VideoSiteConfigStorage]).
  VideoSiteService({Dio? dio, VideoSiteConfig? config})
    : _config = config ?? VideoSiteConfigStorage.current,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: (config ?? VideoSiteConfigStorage.current).origin,
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

  final VideoSiteConfig _config;

  final Dio _dio;

  /// Cloud parse endpoint every playback source on the site resolves
  /// through (see the site's `playerconfig.js`). It must be requested with
  /// a Referer on the configured site domain, otherwise it answers with a
  /// failure code.
  String get _parseEndpoint => _config.parseEndpoint;

  /// AES setup of the site player's `uic()` decryption, keyed by the
  /// per-request `uid` embedded in each parse response.
  static const String _aesKeyPrefix = '2890';
  static const String _aesKeySuffix = 'tB959C';
  static const String _aesIv = '2F131BE91247866E';

  /// Failure codes of the parse endpoint (see its `tips` messages).
  static const Map<int, String> _parseErrors = {
    304: '访问过于频繁，已被临时冻结，请稍后再试',
    301: '解析接口未返回播放地址',
    0: '资源解析失败，请稍后重试或更换播放源',
    101: '资源解析失败，请稍后重试或更换播放源',
    102: '该资源暂时无法解析，请更换播放源',
    103: '未匹配到解析接口',
  };

  // ------------------------------------------------------------------
  // Browse list
  // ------------------------------------------------------------------

  /// Fetches one page of a browse list (movies / series / documentary /
  /// variety / anime, sorted by recency).
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
  /// into a directly playable stream URL.
  ///
  /// 1. The play page hides the resource reference in `player_aaaa`
  ///    (base64 + percent-encoded).
  /// 2. The reference goes to the cloud parse endpoint (a Referer on the
  ///    configured site domain required), whose HTML embeds a `ConFig`
  ///    object with the stream URL AES-encrypted and the per-request key
  ///    material.
  /// 3. AES-128-CBC decryption (the site player's `uic()` algorithm)
  ///    yields the final stream URL, playable without a browser.
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
        vodData is Map<String, dynamic>
            ? (vodData['vod_name'] as String? ?? '')
            : '';

    final streamUrl = await _resolveStream(decrypted, playPath);

    return VideoPlayInfo(
      title: vodName,
      episodeLabel: episodeLabel,
      rawUrl: decrypted,
      streamUrl: streamUrl,
      nextPlayPath: (payload['link_next'] as String?)?.isNotEmpty == true
          ? payload['link_next'] as String
          : null,
    );
  }

  /// Runs the resource reference through the cloud parse endpoint and
  /// decrypts the embedded stream URL.
  Future<String> _resolveStream(String rawUrl, String playPath) async {
    final response = await _dio.get<String>(
      '$_parseEndpoint${Uri.encodeComponent(rawUrl)}',
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Referer': '${_config.origin}$playPath'},
      ),
    );
    final html = response.data ?? '';
    final config = _extractParseConfig(html);
    if (config == null) {
      throw StateException('解析接口返回异常，请稍后重试');
    }

    final code = (config['code'] as num?)?.toInt() ?? 0;
    if (code != 200) {
      throw StateException(_parseErrors[code] ?? '资源解析失败（code $code）');
    }

    final encryptedUrl = config['url'] as String? ?? '';
    final configSection = config['config'];
    final uid =
        configSection is Map<String, dynamic>
        ? (configSection['uid'] as String? ?? '')
        : '';
    if (encryptedUrl.isEmpty || uid.isEmpty) {
      throw StateException(_parseErrors[301]!);
    }

    final streamUrl = _decryptStreamUrl(encryptedUrl, uid);
    if (streamUrl.isEmpty) {
      throw StateException('资源解析失败，请稍后重试或更换播放源');
    }
    return streamUrl;
  }

  /// Extracts the `let ConFig = {...}` object embedded in the parse
  /// response. The whole inline script is the assignment, so slicing from
  /// the first `{` to the last `}` yields the JSON.
  Map<String, dynamic>? _extractParseConfig(String html) {
    final scriptStart = html.indexOf('let ConFig');
    if (scriptStart < 0) return null;
    final braceStart = html.indexOf('{', scriptStart);
    final braceEnd = html.lastIndexOf('}');
    if (braceStart < 0 || braceEnd <= braceStart) return null;
    try {
      return Map<String, dynamic>.from(
        jsonDecode(html.substring(braceStart, braceEnd + 1)) as Map,
      );
    } on FormatException {
      return null;
    }
  }

  /// AES-128-CBC decryption of the stream URL, mirroring the site player's
  /// `uic()`: key = `'2890' + uid + 'tB959C'`, fixed IV, PKCS7 padding.
  String _decryptStreamUrl(String encryptedUrl, String uid) {
    try {
      final key = utf8.encode('$_aesKeyPrefix$uid$_aesKeySuffix');
      final iv = utf8.encode(_aesIv);
      final cipher = PaddedBlockCipherImpl(
        PKCS7Padding(),
        CBCBlockCipher(AESEngine()),
      )..init(
          false,
          PaddedBlockCipherParameters(
            ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
            null,
          ),
        );
      final decrypted = cipher.process(base64Decode(encryptedUrl));
      return utf8.decode(decrypted).trim();
    } catch (_) {
      // Bad padding / encoding just means the response was not a valid
      // encrypted URL; surface it as a resolution failure to the caller.
      return '';
    }
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
