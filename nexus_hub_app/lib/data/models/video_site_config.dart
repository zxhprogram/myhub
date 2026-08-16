import 'package:flutter/foundation.dart';

/// Parsing protocols understood by the video sub-app.
///
/// A protocol bundles the complete set of extraction rules for a family of
/// video sites whose URL layout and page structure are identical — only the
/// domains they are deployed on differ (see [VideoSiteConfig]). Selecting a
/// protocol therefore fixes every path, payload shape and decryption step,
/// while the domains remain user-configurable.
enum VideoProtocol {
  /// The MacCMS V10 layout of www.netflixgc.com: the `ds_api/vod` JSON list
  /// endpoint, the `ajax/suggest` search API, server-rendered
  /// `/voddetail/{id}.html` detail pages, the encrypted `player_aaaa`
  /// payload on `/vodplay/...` play pages and the cloud parse endpoint
  /// whose `ConFig` object hides the stream URL behind AES-128-CBC.
  netflixgc('NetflixGC'),

  /// The mxtheme MacCMS layout of 5555dy.cc: showcase-style `/frim/{id}.html`
  /// channel pages behind an nginx cookie challenge, the same `ajax/suggest`
  /// search API, server-rendered `/movie/{id}.html` detail pages whose
  /// playback sources are `data-dropdown-value` tabs paired with `panel{n}`
  /// episode lists, and `player_aaaa` play payloads that carry the stream
  /// URL directly (`encrypt: 0`) — no cloud parse step.
  movie555('555电影');

  const VideoProtocol(this.label);

  /// Display name shown in the protocol picker.
  final String label;

  /// Site domain the protocol was first implemented against; prefill of
  /// the domain field when a source switches protocols.
  String get defaultDomain => switch (this) {
    netflixgc => 'www.netflixgc.com',
    movie555 => '5555dy.cc',
  };

  /// Host of the cloud parse endpoint, when the protocol needs one.
  /// Protocols whose play pages already resolve the stream URL have none.
  String get defaultParseDomain => switch (this) {
    netflixgc => 'cjbfq.netflixgc.tv',
    movie555 => '',
  };

  /// Helper text shown under the protocol picker in the source editor.
  String get description => switch (this) {
    netflixgc =>
      'NetflixGC 协议：列表/搜索走 JSON 接口，详情页解析 HTML，播放页双重加密'
      '后经云端解析接口取流。站点域名变更时无需改动协议，只需更新下方域名。',
    movie555 =>
      '555电影 协议：列表来自 /frim 分类页（单页展示，无分页），搜索走 suggest '
      '接口，详情页解析播放源与剧集，播放页直接返回 m3u8 地址。仅需配置站点域名。',
  };

  static VideoProtocol fromName(String? value) {
    return VideoProtocol.values.firstWhere(
      (p) => p.name == value,
      orElse: () => VideoProtocol.netflixgc,
    );
  }
}

/// One saved video data source: a display [name] plus which
/// [VideoProtocol] to parse with and the domains that protocol is
/// deployed on. Users keep several of these (see VideoSiteConfigStorage)
/// and switch between them for browsing and playback.
///
/// The domains cover everything the services talk to:
///  * [domain] — the site itself (list, search, detail and play pages);
///  * [parseDomain] — for protocols that resolve playback through a cloud
///    parse endpoint, the separate host of that endpoint (empty for
///    protocols whose play pages already carry the stream URL).
@immutable
class VideoSiteConfig {
  const VideoSiteConfig({
    required this.id,
    required this.name,
    this.protocol = VideoProtocol.netflixgc,
    this.domain = defaultDomain,
    this.parseDomain = defaultParseDomain,
  });

  /// Id of the seeded built-in source, so first runs and "恢复默认" have a
  /// stable target.
  static const String defaultId = 'netflixgc-default';

  /// Site domain the netflixgc protocol was first implemented against.
  static const String defaultDomain = 'www.netflixgc.com';

  /// Host of the cloud parse endpoint on the original deployment (see the
  /// site's `playerconfig.js`).
  static const String defaultParseDomain = 'cjbfq.netflixgc.tv';

  /// Id of the seeded built-in 555电影 source.
  static const String movie555DefaultId = 'movie555-default';

  /// Stable-enough id for new sources: timestamp prefix + monotonic
  /// counter (the same scheme as TerminalState.generateId).
  static int _idCounter = 0;
  static String generateId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  /// The seeded built-in source.
  static const VideoSiteConfig defaultConfig = VideoSiteConfig(
    id: defaultId,
    name: 'NetflixGC',
  );

  /// The seeded built-in 555电影 source (no parse endpoint).
  static const VideoSiteConfig movie555DefaultConfig = VideoSiteConfig(
    id: movie555DefaultId,
    name: '555电影',
    protocol: VideoProtocol.movie555,
    domain: '5555dy.cc',
    parseDomain: '',
  );

  final String id;

  /// Display name shown in the source picker and manager.
  final String name;

  final VideoProtocol protocol;

  /// Bare site domain, e.g. `www.netflixgc.com` (no scheme, no path).
  final String domain;

  /// Bare host of the cloud parse endpoint, e.g. `cjbfq.netflixgc.tv`.
  final String parseDomain;

  /// Site root used as the HTTP base of every request.
  String get origin => 'https://$domain';

  /// Full prefix the resource references are appended to, protocol-fixed
  /// path and query included. Empty for protocols without a parse
  /// endpoint.
  String get parseEndpoint => parseDomain.isEmpty
      ? ''
      : 'https://$parseDomain/player/ec.php?code=netflix&if=1&url=';

  /// `name · domain` summary shown in the source list.
  String get endpoint => '$name · $domain';

  @override
  bool operator ==(Object other) {
    return other is VideoSiteConfig &&
        other.id == id &&
        other.name == name &&
        other.protocol == protocol &&
        other.domain == domain &&
        other.parseDomain == parseDomain;
  }

  @override
  int get hashCode => Object.hash(id, name, protocol, domain, parseDomain);

  /// Cleans raw user input into a bare domain: trims whitespace, strips an
  /// optional `http(s)://` scheme and any trailing slashes.
  static String normalizeDomain(String raw) {
    var value = raw.trim();
    final schemeIndex = value.indexOf('://');
    if (schemeIndex >= 0) {
      value = value.substring(schemeIndex + 3);
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value.toLowerCase();
  }

  /// Whether [normalizeDomain] on [raw] yields something usable as a host.
  static bool isValidDomain(String raw) {
    return RegExp(
      r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d{1,5})?$',
    ).hasMatch(normalizeDomain(raw));
  }

  VideoSiteConfig copyWith({
    String? id,
    String? name,
    VideoProtocol? protocol,
    String? domain,
    String? parseDomain,
  }) {
    return VideoSiteConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      domain: domain ?? this.domain,
      parseDomain: parseDomain ?? this.parseDomain,
    );
  }

  factory VideoSiteConfig.fromJson(Map<String, dynamic> json) {
    final domain = normalizeDomain(json['domain'] as String? ?? '');
    final parseDomain = normalizeDomain(json['parseDomain'] as String? ?? '');
    final protocol = VideoProtocol.fromName(json['protocol'] as String?);
    return VideoSiteConfig(
      id: (json['id'] as String? ?? '').isNotEmpty
          ? json['id'] as String
          : generateId(),
      name: (json['name'] as String? ?? '').isNotEmpty
          ? json['name'] as String
          : '未命名数据源',
      protocol: protocol,
      domain: domain.isEmpty ? protocol.defaultDomain : domain,
      parseDomain: parseDomain.isEmpty
          ? protocol.defaultParseDomain
          : parseDomain,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.name,
        'domain': domain,
        'parseDomain': parseDomain,
      };
}
