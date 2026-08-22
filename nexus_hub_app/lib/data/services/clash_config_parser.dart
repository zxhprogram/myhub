/// Local parser for Clash subscription YAML configs.
///
/// The proxies view normally reads groups and nodes from the external
/// controller of a running core; when no core is attached this parser reads
/// the very same information straight out of the downloaded `proxies:` /
/// `proxy-groups:` sections, so the user can still inspect and pick nodes.
/// Only the fields the node list needs (name / type / members) are read —
/// servers, cipher keys and the like stay in the raw config that is pushed
/// to the core verbatim.
library;

import 'package:yaml/yaml.dart';

import '../models/clash_models.dart';

/// Result of parsing one subscription config.
class ClashParsedConfig {
  const ClashParsedConfig({this.proxies = const [], this.groups = const []});

  /// Top-level nodes of `proxies:`, in config order.
  final List<ClashProxy> proxies;

  /// Groups of `proxy-groups:` with members resolved to [ClashProxy] entries.
  final List<ClashProxyGroup> groups;
}

/// Node names Clash cores accept inside a group although they never appear
/// in `proxies:`.
const _builtinProxyNames = {'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE'};

/// Parses [config]; any malformed section is skipped rather than throwing,
/// mirroring how leniently the cores themselves load airport configs.
ClashParsedConfig parseClashConfig(String config) {
  dynamic document;
  try {
    document = loadYaml(config);
  } on YamlException {
    return const ClashParsedConfig();
  }
  if (document is! Map) return const ClashParsedConfig();

  // Everything a group member can resolve to: nodes, built-ins and other
  // groups (cores let a selector point at a nested group). Group types are
  // collected first so forward references resolve in one pass.
  final resolvable = <String, ClashProxy>{};
  final proxiesSection = document['proxies'];
  if (proxiesSection is List) {
    for (final entry in proxiesSection) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString() ?? '';
      if (name.isEmpty || resolvable.containsKey(name)) continue;
      resolvable[name] = ClashProxy(name: name, type: entry['type']?.toString() ?? '');
    }
  }
  for (final name in _builtinProxyNames) {
    resolvable.putIfAbsent(name, () => ClashProxy(name: name, type: name.toLowerCase()));
  }

  final groupEntries = <Map>[];
  final groupsSection = document['proxy-groups'];
  if (groupsSection is List) {
    for (final entry in groupsSection) {
      if (entry is! Map) continue;
      final name = entry['name']?.toString() ?? '';
      if (name.isEmpty || groupEntries.any((g) => g['name']?.toString() == name)) {
        continue;
      }
      groupEntries.add(entry);
      resolvable.putIfAbsent(
        name,
        () => ClashProxy(
          name: name,
          type: ClashGroupType.parse(entry['type']?.toString() ?? '').value,
        ),
      );
    }
  }

  final groups = <ClashProxyGroup>[];
  for (final entry in groupEntries) {
    final name = entry['name']?.toString() ?? '';
    final all = <String>[];
    final members = <ClashProxy>[];
    final proxiesList = entry['proxies'];
    if (proxiesList is List) {
      for (final member in proxiesList) {
        final memberName = member?.toString() ?? '';
        if (memberName.isEmpty || all.contains(memberName)) continue;
        all.add(memberName);
        members.add(
          // Names only reachable through a `use:` provider are kept listed
          // with no type; the core resolves them when the config is applied.
          resolvable[memberName] ?? ClashProxy(name: memberName, type: ''),
        );
      }
    }
    groups.add(
      ClashProxyGroup(
        name: name,
        type: ClashGroupType.parse(entry['type']?.toString() ?? ''),
        all: all,
        proxies: members,
      ),
    );
  }

  return ClashParsedConfig(
    proxies: [
      for (final entry in proxiesSection ?? const <dynamic>[])
        if (entry is Map) resolvable[entry['name']?.toString() ?? ''],
    ].whereType<ClashProxy>().toList(),
    groups: groups,
  );
}

/// Builds the group list shown by the proxies view for a locally parsed
/// config: the configured groups when present, otherwise one virtual
/// selector holding every node (many airport configs ship without
/// `proxy-groups:`).
List<ClashProxyGroup> groupsForLocalDisplay(ClashParsedConfig parsed) {
  final groups = <ClashProxyGroup>[
    for (final group in parsed.groups)
      ClashProxyGroup(
        name: group.name,
        type: group.type,
        all: group.all,
        proxies: group.proxies,
      ),
  ];
  if (groups.isEmpty && parsed.proxies.isNotEmpty) {
    groups.add(
      ClashProxyGroup(
        name: '全部节点',
        type: ClashGroupType.selector,
        all: [for (final proxy in parsed.proxies) proxy.name],
        proxies: parsed.proxies,
      ),
    );
  }
  return groups;
}
