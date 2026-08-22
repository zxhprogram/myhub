/// YAML overwrite pipeline, ported from FlClash's `makeRealProfileTask`
/// (`lib/common/task.dart`).
///
/// FlClash assembles the runnable config by merging its patch settings, the
/// profile file and the per-profile overwrite (added / disabled rules) in an
/// isolate before handing the result to the core. The same concept is applied
/// here with line-block surgery on the stored profile YAML: everything
/// outside the overwritten top-level blocks stays byte-identical to the
/// downloaded subscription, so the merged config remains valid even for
/// exotic subscription formats that a full YAML re-serializer could break.
library;

import 'package:yaml/yaml.dart';

import '../models/clash_models.dart';

class ClashConfigOverwriter {
  const ClashConfigOverwriter._();

  /// Default inbound port injected into subscriptions that ship without any
  /// listener — the same default FlClash's patch config applies
  /// (`PatchClashConfig.mixedPort`). Without it a freshly applied
  /// subscription leaves the core with no listener at all, and regular users
  /// have no way of knowing which port to pick.
  static const defaultMixedPort = 7890;

  /// Builds the final config pushed to the core when [profile] is activated:
  /// the stored subscription plus its rule overwrite, the DNS override when
  /// enabled (FlClash's `overrideDns`) and a guaranteed inbound listener.
  static String buildFinalConfig(
    ClashProfile profile, {
    ClashDnsSettings? dnsOverride,
  }) {
    var config = profile.config;
    if (profile.addedRules.isNotEmpty || profile.disabledRules.isNotEmpty) {
      config = applyRuleOverwrite(config, profile);
    }
    if (dnsOverride != null) {
      config = replaceTopLevelBlock(
        config,
        'dns',
        emitBlock(dnsOverride.toMap(), indent: '  '),
      );
    }
    return ensureDefaultInboundPort(config);
  }

  /// Ensures the config exposes at least one inbound listener: subscriptions
  /// frequently arrive without ports, which would leave the core with
  /// nothing to point the system proxy at. Existing ports (any of the five
  /// inbound kinds, value > 0) are left untouched.
  static String ensureDefaultInboundPort(String config) {
    final doc = _load(config);
    if (doc != null) {
      for (final key in [
        'mixed-port',
        'port',
        'socks-port',
        'redir-port',
        'tproxy-port',
      ]) {
        final value = doc[key];
        if (value is num && value > 0) return config;
      }
    }
    return replaceTopLevelScalar(config, 'mixed-port', defaultMixedPort);
  }

  /// The profile's own top-level `rules:` entries.
  static List<String> rulesOf(String config) {
    final doc = _load(config);
    final rawRules = doc?['rules'];
    if (rawRules is! YamlList) return const [];
    return [for (final item in rawRules) item.toString()];
  }

  /// Merges the per-profile rule overwrite into [config].
  ///
  /// Added rules are prepended so they win the first-match evaluation of the
  /// core, disabled rules are removed (FlClash's standard overwrite scene).
  static String applyRuleOverwrite(String config, ClashProfile profile) {
    final existing = rulesOf(config);
    final disabled = profile.disabledRules.toSet();
    final added = [
      for (final rule in profile.addedRules)
        if (rule.trim().isNotEmpty) rule.trim(),
    ];
    final merged = [
      ...added,
      for (final rule in existing)
        if (!disabled.contains(rule)) rule,
    ];
    return replaceTopLevelList(config, 'rules', merged);
  }

  /// Replaces (or appends) the top-level `key:` block with [blockLines].
  ///
  /// The block extends from the `key:` line until the next line that starts
  /// at column zero; everything in between is replaced. When the key is
  /// absent the generated block is appended as a new top-level section.
  static String replaceTopLevelBlock(
    String yaml,
    String key,
    List<String> blockLines,
  ) {
    final lines = yaml.split('\n');
    final keyPattern = RegExp('^$key:(\\s.*)?\$');
    final start = lines.indexWhere(keyPattern.hasMatch);
    final generated = ['$key:', ...blockLines];

    if (start == -1) {
      var end = lines.length;
      while (end > 0 && lines[end - 1].trim().isEmpty) {
        end--;
      }
      return [...lines.sublist(0, end), ...generated].join('\n');
    }

    var blockEnd = start + 1;
    while (blockEnd < lines.length) {
      final line = lines[blockEnd];
      if (line.trim().isEmpty) {
        blockEnd++;
        continue;
      }
      final firstChar = line[0];
      if (firstChar == ' ' || firstChar == '\t') {
        blockEnd++;
        continue;
      }
      break;
    }
    return [
      ...lines.sublist(0, start),
      ...generated,
      ...lines.sublist(blockEnd),
    ].join('\n');
  }

  /// Replaces the top-level `key:` list with [items].
  static String replaceTopLevelList(
    String yaml,
    String key,
    List<String> items,
  ) {
    return replaceTopLevelBlock(yaml, key, [
      for (final item in items) '  - ${quoteScalar(item)}',
    ]);
  }

  /// Sets a top-level scalar, replacing an existing line or appending the
  /// key at the end of the document.
  static String replaceTopLevelScalar(
    String yaml,
    String key,
    Object value,
  ) {
    final lines = yaml.split('\n');
    final keyPattern = RegExp('^$key:(\\s.*)?\$');
    final rendered = '$key: ${renderScalar(value)}';
    final index = lines.indexWhere(keyPattern.hasMatch);
    if (index == -1) {
      var end = lines.length;
      while (end > 0 && lines[end - 1].trim().isEmpty) {
        end--;
      }
      return [...lines.sublist(0, end), rendered].join('\n');
    }
    lines[index] = rendered;
    return lines.join('\n');
  }

  /// Emits a nested map as YAML block lines at [indent] (two spaces per
  /// level). Scalars are single-quoted so values like `*.lan` or
  /// `DOMAIN-SUFFIX,example.com,DIRECT` survive round-trips untouched.
  static List<String> emitBlock(Map<String, dynamic> map, {String indent = ''}) {
    final lines = <String>[];
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is Map) {
        if (value.isEmpty) {
          lines.add('$indent${entry.key}: {}');
          continue;
        }
        lines.add('$indent${entry.key}:');
        lines.addAll(
          emitBlock(Map<String, dynamic>.from(value), indent: '$indent  '),
        );
      } else if (value is List) {
        if (value.isEmpty) {
          lines.add('$indent${entry.key}: []');
          continue;
        }
        lines.add('$indent${entry.key}:');
        for (final item in value) {
          lines.add('$indent  - ${renderScalar(item)}');
        }
      } else if (value == null) {
        lines.add('$indent${entry.key}:');
      } else {
        lines.add('$indent${entry.key}: ${renderScalar(value)}');
      }
    }
    return lines;
  }

  static String renderScalar(Object value) {
    if (value is bool || value is num) return value.toString();
    return quoteScalar(value.toString());
  }

  /// Single-quoted YAML scalar; single quotes are doubled per the YAML spec.
  static String quoteScalar(String value) => "'${value.replaceAll("'", "''")}'";

  static YamlMap? _load(String config) {
    try {
      final doc = loadYaml(config);
      return doc is YamlMap ? doc : null;
    } on YamlException {
      return null;
    }
  }
}
