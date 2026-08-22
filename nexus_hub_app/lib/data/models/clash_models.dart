/// Data models for the Clash virtual app.
///
/// Ported from FlClash (`lib/models/common.dart`, `lib/models/clash_config.dart`
/// and `lib/models/core.dart`) and adapted to the payloads of the mihomo
/// (Clash.Meta) external controller REST API, which is the transport this
/// virtual app uses to talk to a running core instead of FlClash's in-process
/// Go/Rust bridge.
library;

import 'package:flutter/painting.dart';

/// Outbound mode of the core, see the `mode` field of `GET /configs`.
enum ClashProxyMode {
  rule('rule'),
  global('global'),
  direct('direct');

  final String value;

  const ClashProxyMode(this.value);

  static ClashProxyMode parse(String? value) {
    return ClashProxyMode.values.firstWhere(
      (mode) => mode.value == value?.toLowerCase(),
      orElse: () => ClashProxyMode.rule,
    );
  }

  String get label => switch (this) {
    ClashProxyMode.rule => '规则',
    ClashProxyMode.global => '全局',
    ClashProxyMode.direct => '直连',
  };
}

/// Log severity levels accepted by `GET /logs?level=`.
enum ClashLogLevel {
  debug('debug'),
  info('info'),
  warning('warning'),
  error('error');

  final String value;

  const ClashLogLevel(this.value);

  static ClashLogLevel parse(String? value) {
    return ClashLogLevel.values.firstWhere(
      (level) => level.value == value?.toLowerCase(),
      orElse: () => ClashLogLevel.info,
    );
  }
}

/// Proxy group type, ported from FlClash `GroupType`.
enum ClashGroupType {
  selector('select'),
  urlTest('url-test'),
  fallback('fallback'),
  loadBalance('load-balance'),
  relay('relay');

  final String value;

  const ClashGroupType(this.value);

  static ClashGroupType parse(String type) {
    return switch (type.toLowerCase()) {
      'url-test' || 'urltest' => ClashGroupType.urlTest,
      'select' || 'selector' => ClashGroupType.selector,
      'fallback' => ClashGroupType.fallback,
      'load-balance' || 'loadbalance' => ClashGroupType.loadBalance,
      'relay' => ClashGroupType.relay,
      _ => ClashGroupType.selector,
    };
  }

  /// Groups whose active node is computed by the core (url-test / fallback).
  /// Ported from FlClash `GroupTypeExtension.isComputedSelected`.
  bool get isComputedSelected =>
      this == ClashGroupType.urlTest || this == ClashGroupType.fallback;

  /// Whether the user may pick a specific node in this group.
  bool get isSelectable =>
      this == ClashGroupType.selector || isComputedSelected;

  String get label => switch (this) {
    ClashGroupType.selector => '手动选择',
    ClashGroupType.urlTest => '自动测速',
    ClashGroupType.fallback => '故障转移',
    ClashGroupType.loadBalance => '负载均衡',
    ClashGroupType.relay => '链式代理',
  };
}

/// One delay history entry of a node: `{"time": "...", "delay": 123}`.
class ClashProxyHistory {
  const ClashProxyHistory({required this.delay});

  final int delay;

  factory ClashProxyHistory.fromJson(Map<String, dynamic> json) =>
      ClashProxyHistory(delay: (json['delay'] as num?)?.toInt() ?? 0);
}

/// A single proxy node or group entry of `GET /proxies`.
///
/// Ported from FlClash `Proxy`, extended with the fields the external
/// controller reports (alive / udp / history).
class ClashProxy {
  const ClashProxy({
    required this.name,
    required this.type,
    this.now,
    this.all = const [],
    this.alive = false,
    this.udp = false,
    this.history = const [],
  });

  final String name;
  final String type;
  final String? now;

  /// Member names when this entry is a group.
  final List<String> all;

  final bool alive;
  final bool udp;
  final List<ClashProxyHistory> history;

  factory ClashProxy.fromJson(Map<String, dynamic> json) {
    return ClashProxy(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      now: json['now'] as String?,
      all: (json['all'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      alive: json['alive'] as bool? ?? false,
      udp: json['udp'] as bool? ?? false,
      history: (json['history'] as List<dynamic>? ?? const [])
          .map(
            (item) => item is Map<String, dynamic>
                ? ClashProxyHistory.fromJson(item)
                : const ClashProxyHistory(delay: 0),
          )
          .toList(),
    );
  }

  /// Latest measured delay in ms; 0 means never tested, negative means
  /// timeout/unreachable (mirrors FlClash's delay semantics).
  int get latestDelay => history.isEmpty ? 0 : history.last.delay;
}

/// A proxy group: a named entry of `GET /proxies` that has member nodes.
///
/// Ported from FlClash `Group`; `all` holds the member names and `proxies`
/// resolves them against the full proxy map.
class ClashProxyGroup {
  const ClashProxyGroup({
    required this.name,
    required this.type,
    required this.all,
    required this.proxies,
    this.now,
  });

  final String name;
  final ClashGroupType type;

  /// Names of the member nodes (order preserved from the config).
  final List<String> all;

  /// Resolved member proxies, in [all] order.
  final List<ClashProxy> proxies;

  final String? now;

  String get realNow => now ?? '';

  factory ClashProxyGroup.fromProxy(ClashProxy proxy) {
    return ClashProxyGroup(
      name: proxy.name,
      type: ClashGroupType.parse(proxy.type),
      all: proxy.all,
      proxies: const [],
      now: proxy.now,
    );
  }
}

/// Connection metadata of an active connection. Ported from FlClash `Metadata`.
class ClashConnectionMetadata {
  const ClashConnectionMetadata({
    this.network = '',
    this.type = '',
    this.sourceIP = '',
    this.sourcePort = '',
    this.destinationIP = '',
    this.destinationPort = '',
    this.host = '',
    this.dnsMode = '',
    this.process = '',
    this.processPath = '',
    this.remoteDestination = '',
  });

  final String network;
  final String type;
  final String sourceIP;
  final String sourcePort;
  final String destinationIP;
  final String destinationPort;
  final String host;
  final String dnsMode;
  final String process;
  final String processPath;
  final String remoteDestination;

  factory ClashConnectionMetadata.fromJson(Map<String, dynamic> json) {
    String str(String key) => json[key]?.toString() ?? '';
    return ClashConnectionMetadata(
      network: str('network'),
      type: str('type'),
      sourceIP: str('sourceIP'),
      sourcePort: str('sourcePort'),
      destinationIP: str('destinationIP'),
      destinationPort: str('destinationPort'),
      host: str('host'),
      dnsMode: str('dnsMode'),
      process: str('process'),
      processPath: str('processPath'),
      remoteDestination: str('remoteDestination'),
    );
  }

  /// Human readable destination: host if sniffed, otherwise IP:port.
  /// Ported from FlClash `Metadata` usage in `TrackerInfo.desc`.
  String get destination {
    final target = host.isNotEmpty ? host : destinationIP;
    if (target.isEmpty) return remoteDestination;
    return '$target:$destinationPort';
  }
}

/// An active connection tracked by the core.
///
/// Ported from FlClash `TrackerInfo`; speeds are only reported by the
/// streaming endpoint, the one-shot snapshot leaves them null.
class ClashConnection {
  const ClashConnection({
    required this.id,
    required this.upload,
    required this.download,
    required this.start,
    required this.metadata,
    required this.chains,
    required this.rule,
    required this.rulePayload,
    this.uploadSpeed,
    this.downloadSpeed,
  });

  final String id;
  final int upload;
  final int download;
  final DateTime start;
  final ClashConnectionMetadata metadata;

  /// Proxy chain, outermost group first (e.g. `['Proxies', 'HK-01']`).
  final List<String> chains;
  final String rule;
  final String rulePayload;
  final int? uploadSpeed;
  final int? downloadSpeed;

  factory ClashConnection.fromJson(Map<String, dynamic> json) {
    final metadataJson = json['metadata'];
    DateTime parseStart() {
      final raw = json['start']?.toString() ?? '';
      return DateTime.tryParse(raw) ?? DateTime.now();
    }

    return ClashConnection(
      id: json['id']?.toString() ?? '',
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      start: parseStart(),
      metadata: metadataJson is Map<String, dynamic>
          ? ClashConnectionMetadata.fromJson(metadataJson)
          : const ClashConnectionMetadata(),
      chains: (json['chains'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      rule: json['rule']?.toString() ?? '',
      rulePayload: json['rulePayload']?.toString() ?? '',
      uploadSpeed: (json['uploadSpeed'] as num?)?.toInt(),
      downloadSpeed: (json['downloadSpeed'] as num?)?.toInt(),
    );
  }

  /// Node → group chain for display (innermost first, like FlClash).
  String get chainText => chains.reversed.join(' → ');

  String get ruleText =>
      rulePayload.isEmpty ? rule : '$rule / $rulePayload';
}

/// One-shot snapshot of `GET /connections`.
class ClashConnectionsSnapshot {
  const ClashConnectionsSnapshot({
    required this.connections,
    required this.uploadTotal,
    required this.downloadTotal,
    required this.memory,
  });

  final List<ClashConnection> connections;
  final int uploadTotal;
  final int downloadTotal;

  /// In-use core memory in bytes (mihomo extension).
  final int memory;

  factory ClashConnectionsSnapshot.fromJson(Map<String, dynamic> json) {
    return ClashConnectionsSnapshot(
      connections: (json['connections'] as List<dynamic>? ?? const [])
          .map(
            (item) => item is Map<String, dynamic>
                ? ClashConnection.fromJson(item)
                : null,
          )
          .whereType<ClashConnection>()
          .toList(),
      uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
      downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
      memory: (json['memory'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One log line of the `GET /logs` stream.
///
/// Ported from FlClash `Log`. mihomo sends `{"type": "...", "payload": "..."}`
/// per line; FlClash's own core used capitalized keys, both are accepted.
class ClashLog {
  const ClashLog({
    required this.level,
    required this.payload,
    required this.time,
  });

  final ClashLogLevel level;
  final String payload;
  final DateTime time;

  factory ClashLog.fromJson(Map<String, dynamic> json) {
    final rawLevel =
        json['type'] ?? json['LogLevel'] ?? ClashLogLevel.info.value;
    return ClashLog(
      level: ClashLogLevel.parse(rawLevel?.toString()),
      payload: (json['payload'] ?? json['Payload'])?.toString() ?? '',
      time: DateTime.now(),
    );
  }
}

/// One sampled second of throughput of the `GET /traffic` stream.
/// Ported from FlClash `Traffic`.
class ClashTraffic {
  const ClashTraffic({this.up = 0, this.down = 0});

  final int up;
  final int down;

  factory ClashTraffic.fromJson(Map<String, dynamic> json) {
    return ClashTraffic(
      up: (json['up'] as num?)?.toInt() ?? 0,
      down: (json['down'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Response of `GET /version`. Ported from FlClash `VersionInfo`.
class ClashVersion {
  const ClashVersion({required this.version, required this.meta});

  final String version;
  final bool meta;

  factory ClashVersion.fromJson(Map<String, dynamic> json) {
    return ClashVersion(
      version: json['version']?.toString() ?? '',
      meta: json['meta'] as bool? ?? false,
    );
  }
}

/// One routing rule of `GET /rules`.
class ClashRule {
  const ClashRule({
    required this.type,
    required this.payload,
    required this.proxy,
  });

  final String type;
  final String payload;
  final String proxy;

  factory ClashRule.fromJson(Map<String, dynamic> json) {
    return ClashRule(
      type: json['type']?.toString() ?? '',
      payload: json['payload']?.toString() ?? '',
      proxy: json['proxy']?.toString() ?? '',
    );
  }

  String get display => payload.isEmpty ? type : '$type, $payload';
}

/// Runtime configuration of `GET /configs` (only the dashboard-relevant
/// subset; the full patch surface is FlClash's overwrite editor).
class ClashRunningConfig {
  const ClashRunningConfig({
    this.mode = ClashProxyMode.rule,
    this.mixedPort,
    this.port,
    this.socksPort,
    this.allowLan = false,
    this.logLevel = ClashLogLevel.info,
  });

  final ClashProxyMode mode;
  final int? mixedPort;
  final int? port;
  final int? socksPort;
  final bool allowLan;
  final ClashLogLevel logLevel;

  factory ClashRunningConfig.fromJson(Map<String, dynamic> json) {
    int? portOf(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return null;
    }

    return ClashRunningConfig(
      mode: ClashProxyMode.parse(json['mode']?.toString()),
      mixedPort: portOf('mixed-port'),
      port: portOf('port'),
      socksPort: portOf('socks-port'),
      allowLan: json['allow-lan'] as bool? ?? false,
      logLevel: ClashLogLevel.parse(json['log-level']?.toString()),
    );
  }

  /// Primary inbound port shown in the dashboard.
  String get inboundPort {
    final mixed = mixedPort;
    if (mixed != null && mixed > 0) return '$mixed';
    final http = port;
    if (http != null && http > 0) return '$http';
    final socks = socksPort;
    if (socks != null && socks > 0) return '$socks';
    return '-';
  }
}

/// Subscription traffic accounting, decoded from the `subscription-userinfo`
/// response header most airports send along with the config.
///
/// Ported from FlClash `SubscriptionInfo`; the header looks like
/// `upload=123; download=456; total=107374182400; expire=1750000000`.
class ClashSubscriptionInfo {
  const ClashSubscriptionInfo({
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire = 0,
  });

  final int upload;
  final int download;
  final int total;

  /// Unix seconds; 0 means the server did not report an expiry.
  final int expire;

  /// Ported from FlClash `SubscriptionInfo.formHString`.
  factory ClashSubscriptionInfo.fromHeader(String? info) {
    if (info == null || info.isEmpty) return const ClashSubscriptionInfo();
    final map = <String, int>{};
    for (final part in info.split(';')) {
      final keyValue = part.trim().split('=');
      if (keyValue.length != 2) continue;
      final value = int.tryParse(keyValue[1].trim());
      if (value != null) map[keyValue[0].trim()] = value;
    }
    return ClashSubscriptionInfo(
      upload: map['upload'] ?? 0,
      download: map['download'] ?? 0,
      total: map['total'] ?? 0,
      expire: map['expire'] ?? 0,
    );
  }

  factory ClashSubscriptionInfo.fromJson(Map<String, dynamic> json) {
    int read(String key) => (json[key] as num?)?.toInt() ?? 0;
    return ClashSubscriptionInfo(
      upload: read('upload'),
      download: read('download'),
      total: read('total'),
      expire: read('expire'),
    );
  }

  Map<String, dynamic> toJson() => {
    'upload': upload,
    'download': download,
    'total': total,
    'expire': expire,
  };

  /// Traffic already consumed by this subscription.
  int get used => upload + download;

  bool get hasQuota => total > 0;

  /// 0.0 – 1.0 of the quota consumed; null when the server reports no quota.
  double? get usedFraction =>
      hasQuota ? (used / total).clamp(0.0, 1.0) : null;

  /// Expiry as a local date; null when unknown or unlimited.
  DateTime? get expireDate => expire > 0
      ? DateTime.fromMillisecondsSinceEpoch(expire * 1000)
      : null;

  /// Whether the subscription has already expired.
  bool get isExpired {
    final date = expireDate;
    return date != null && date.isBefore(DateTime.now());
  }
}

/// An imported subscription profile, ported from FlClash `Profile`.
///
/// FlClash stores profiles in a Drift database next to `{id}.yaml` files; this
/// hub app keeps the downloaded YAML in the same JSON document (persisted via
/// SharedPreferences) because configs are small enough for it.
class ClashProfile {
  const ClashProfile({
    required this.id,
    this.label = '',
    this.url = '',
    required this.addedAt,
    this.lastUpdateAt,
    this.subscriptionInfo,
    this.config = '',
    this.selectedMap = const {},
  });

  final String id;
  final String label;
  final String url;

  final DateTime addedAt;
  final DateTime? lastUpdateAt;

  /// Traffic info of the last download, when the server reported one.
  final ClashSubscriptionInfo? subscriptionInfo;

  /// Full YAML config downloaded from [url].
  final String config;

  /// Last node picked per group while this profile was running, restored on
  /// activation the way FlClash's `patchSelectGroup` does.
  final Map<String, String> selectedMap;

  /// Ported from FlClash `Profile.type` (url type vs local file type); every
  /// profile of this app originates from a subscription URL.
  bool get isFromUrl => url.isNotEmpty;

  ClashProfile copyWith({
    String? label,
    String? url,
    DateTime? lastUpdateAt,
    ClashSubscriptionInfo? subscriptionInfo,
    String? config,
    Map<String, String>? selectedMap,
  }) {
    return ClashProfile(
      id: id,
      label: label ?? this.label,
      url: url ?? this.url,
      addedAt: addedAt,
      lastUpdateAt: lastUpdateAt ?? this.lastUpdateAt,
      subscriptionInfo: subscriptionInfo ?? this.subscriptionInfo,
      config: config ?? this.config,
      selectedMap: selectedMap ?? this.selectedMap,
    );
  }

  factory ClashProfile.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(String key) =>
        DateTime.tryParse(json[key]?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final infoJson = json['subscriptionInfo'];
    final selectedJson = json['selectedMap'];
    return ClashProfile(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      addedAt: parseDate('addedAt'),
      lastUpdateAt: json['lastUpdateAt'] == null
          ? null
          : DateTime.tryParse(json['lastUpdateAt'].toString()),
      subscriptionInfo: infoJson is Map<String, dynamic>
          ? ClashSubscriptionInfo.fromJson(infoJson)
          : null,
      config: json['config']?.toString() ?? '',
      selectedMap: selectedJson is Map<String, dynamic>
          ? selectedJson.map((k, v) => MapEntry(k, v.toString()))
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'url': url,
    'addedAt': addedAt.toIso8601String(),
    'lastUpdateAt': lastUpdateAt?.toIso8601String(),
    'subscriptionInfo': subscriptionInfo?.toJson(),
    'config': config,
    'selectedMap': selectedMap,
  };
}

/// Extracts a display name from a `content-disposition` header value.
///
/// Ported from FlClash `utils.getFileNameForDisposition`: RFC 5987
/// `filename*=UTF-8''name` wins over the plain `filename=` token.
String? clashLabelFromDisposition(String? disposition) {
  if (disposition == null || disposition.isEmpty) return null;
  String? decode(String raw) {
    final name = raw.trim().replaceAll('"', '');
    if (name.isEmpty) return null;
    if (name.toLowerCase().contains("''")) {
      final parts = name.split("''");
      if (parts.length == 2 && parts[1].isNotEmpty) {
        return Uri.decodeComponent(parts[1]);
      }
    }
    return name;
  }

  for (final token in disposition.split(';')) {
    final entry = token.trim();
    final lowered = entry.toLowerCase();
    if (lowered.startsWith('filename*=')) {
      final decoded = decode(entry.substring('filename*='.length));
      if (decoded != null) return decoded;
    }
  }
  for (final token in disposition.split(';')) {
    final entry = token.trim();
    if (entry.toLowerCase().startsWith('filename=')) {
      final decoded = decode(entry.substring('filename='.length));
      if (decoded != null) return decoded;
    }
  }
  return null;
}

/// Formats a byte count like FlClash's `traffic.show` extension.
String formatClashBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0
      ? value.round().toString()
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Formats a per-second byte rate.
String formatClashSpeed(num bytesPerSecond) =>
    '${formatClashBytes(bytesPerSecond)}/s';

/// Delay → text, mirroring FlClash's proxy card ('123 ms' / '超时').
String clashDelayText(int? delay) {
  if (delay == null || delay == 0) return '未测';
  if (delay < 0) return '超时';
  return '$delay ms';
}

/// Delay → color, ported from FlClash `utils.getDelayColor` and aligned with
/// the hub palette.
Color? clashDelayColor(int? delay) {
  if (delay == null || delay == 0) return null;
  if (delay < 0) return const Color(0xFFEF4444);
  if (delay < 600) return const Color(0xFF22C55E);
  return const Color(0xFFC57F0A);
}
