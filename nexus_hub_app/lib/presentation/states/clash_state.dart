import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/clash_models.dart';
import '../../data/services/clash_api_service.dart';
import '../../data/services/clash_config_parser.dart';
import '../../data/services/clash_subscription_service.dart';

/// Connection lifecycle of the Clash virtual app.
enum ClashStatus { disconnected, connecting, connected, error }

/// Signals-backed singleton state for the Clash virtual app.
///
/// Core functionality ported from FlClash's Riverpod layer
/// (`lib/providers/`): proxies snapshot + node selection + delay testing,
/// live connections with close actions, streaming logs, traffic sampling and
/// mode switching — re-expressed on top of the external controller REST API
/// and this hub's Signals conventions (see `PomodoroState`).
///
/// Subscription profiles are ported from FlClash's `profiles` actions: import
/// from URL, manual update, delete and activate (push the config to the core
/// and restore the remembered node selection per group).
class ClashState {
  ClashState._();

  static final ClashState instance = ClashState._();

  static const _hostKey = 'nexus_clash_host_v1';
  static const _portKey = 'nexus_clash_port_v1';
  static const _secretKey = 'nexus_clash_secret_v1';
  static const _profilesKey = 'nexus_clash_profiles_v1';
  static const _activeProfileKey = 'nexus_clash_active_profile_v1';

  static const _maxLogs = 500;
  static const _maxTrafficSamples = 60;
  static const _delayTestBatchSize = 6;

  // ----- persisted endpoint configuration -----

  final apiHost = signal<String>('127.0.0.1');
  final apiPort = signal<int>(9090);
  final apiSecret = signal<String>('');

  // ----- persisted subscription profiles -----

  final profiles = signal<List<ClashProfile>>(const []);

  /// Id of the profile this app last pushed to the core (FlClash's
  /// `currentProfileId`).
  final activeProfileId = signal<String?>(null);

  /// Profiles with an in-flight download / update / apply (card spinner).
  final busyProfileIds = signal<Set<String>>(const {});

  // ----- runtime state -----

  final status = signal<ClashStatus>(ClashStatus.disconnected);
  final statusMessage = signal<String>('');

  final version = signal<ClashVersion?>(null);
  final runningConfig = signal<ClashRunningConfig?>(null);

  final proxyGroups = signal<List<ClashProxyGroup>>(const []);
  final selectedGroupName = signal<String?>(null);

  /// Whether [proxyGroups] was parsed locally from the active profile's
  /// stored YAML instead of read from a running core — true whenever no core
  /// is attached (or the core reports no groups). Selections then only
  /// update the remembered [ClashProfile.selectedMap].
  final proxiesFromProfile = signal<bool>(false);

  /// Latest delay test result per node name (0 = untested, -1 = timeout).
  final nodeDelays = signal<Map<String, int>>(const {});

  /// Nodes with an in-flight delay test (drives the per-card spinner).
  final testingNodes = signal<Set<String>>(const {});

  final connections = signal<List<ClashConnection>>(const []);
  final uploadTotal = signal<int>(0);
  final downloadTotal = signal<int>(0);
  final ruleCount = signal<int>(0);

  final logs = signal<List<ClashLog>>(const []);
  final trafficHistory = signal<List<ClashTraffic>>(const []);

  bool _endpointLoaded = false;
  ClashApiService? _api;
  ClashSubscriptionService? _subscriptionService;
  StreamSubscription<ClashTraffic>? _trafficSub;
  StreamSubscription<ClashLog>? _logsSub;
  CancelToken? _trafficCancel;
  CancelToken? _logsCancel;
  Timer? _connectionsTimer;

  /// Current throughput sample, or zeros when idle.
  ClashTraffic get currentTraffic =>
      trafficHistory.value.isEmpty
          ? const ClashTraffic()
          : trafficHistory.value.last;

  /// Loads the persisted endpoint configuration and subscription profiles.
  Future<void> init() async {
    if (_endpointLoaded) return;
    _endpointLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      apiHost.value = prefs.getString(_hostKey) ?? apiHost.value;
      apiPort.value = prefs.getInt(_portKey) ?? apiPort.value;
      apiSecret.value = prefs.getString(_secretKey) ?? apiSecret.value;
      _loadProfiles(prefs);
    } catch (_) {
      // Storage unavailable — keep the 127.0.0.1:9090 defaults.
    }
    // Show the imported nodes right away; a successful core connection
    // replaces them with the live snapshot.
    _refreshProxiesFromProfile();
  }

  void _loadProfiles(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_profilesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          profiles.value = decoded
              .map(
                (item) =>
                    item is Map<String, dynamic>
                        ? ClashProfile.fromJson(item)
                        : null,
              )
              .whereType<ClashProfile>()
              .toList();
        }
      }
      final activeId = prefs.getString(_activeProfileKey);
      if (activeId != null &&
          profiles.value.any((profile) => profile.id == activeId)) {
        activeProfileId.value = activeId;
      }
    } catch (_) {
      // Corrupted store — start with an empty profile list.
    }
  }

  Future<void> _persistProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _profilesKey,
        jsonEncode([for (final profile in profiles.value) profile.toJson()]),
      );
      final activeId = activeProfileId.value;
      if (activeId == null) {
        await prefs.remove(_activeProfileKey);
      } else {
        await prefs.setString(_activeProfileKey, activeId);
      }
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  /// Persists a new endpoint and reconnects if the app was connected.
  Future<void> updateEndpoint({
    required String host,
    required int port,
    required String secret,
  }) async {
    apiHost.value = host;
    apiPort.value = port;
    apiSecret.value = secret;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, host);
      await prefs.setInt(_portKey, port);
      await prefs.setString(_secretKey, secret);
    } catch (_) {
      // Persistence is best-effort.
    }
    if (status.value == ClashStatus.connected) {
      await connect();
    }
  }

  // -----------------------------------------------------------------------
  // Subscription profiles (ported from FlClash lib/providers/actions/profiles.dart)
  // -----------------------------------------------------------------------

  ClashSubscriptionService get _subscriptions =>
      _subscriptionService ??= ClashSubscriptionService();

  /// The profile this app last pushed to the core, if still stored.
  ClashProfile? get activeProfile {
    final id = activeProfileId.value;
    if (id == null) return null;
    for (final profile in profiles.value) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  void _setBusy(String id, bool busy) {
    final next = Set<String>.of(busyProfileIds.value);
    busy ? next.add(id) : next.remove(id);
    busyProfileIds.value = next;
  }

  /// Imports a subscription from [url] (FlClash `addProfileFormURL`).
  ///
  /// Downloads and sanity-checks the config, stores the profile and — when it
  /// is the first one and a core is connected — immediately activates it, so
  /// the "import → pick a node" flow needs no extra click.
  Future<ClashProfile> addProfile({
    required String url,
    String label = '',
  }) async {
    final download = await _subscriptions.download(url);
    final now = DateTime.now();
    final profile = ClashProfile(
      id: 'p${now.microsecondsSinceEpoch}',
      label:
          label.trim().isNotEmpty
              ? label.trim()
              : (download.suggestedLabel ?? _hostOf(url) ?? url),
      url: url,
      addedAt: now,
      lastUpdateAt: now,
      subscriptionInfo: download.subscriptionInfo,
      config: download.config,
    );
    profiles.value = [...profiles.value, profile];
    if (activeProfileId.value == null) {
      activeProfileId.value = profile.id;
    }
    await _persistProfiles();
    if (activeProfileId.value == profile.id) {
      // Pushes to a running core; with none attached this only switches the
      // local view, so the proxies page fills right after the first import.
      unawaited(
        activateProfile(profile.id).catchError((_) {}),
      );
    }
    return profile;
  }

  /// Re-downloads a stored subscription (FlClash `updateProfile`); re-applies
  /// it silently when it is the running one.
  Future<void> updateProfile(String id) async {
    final profile = profiles.value.where((p) => p.id == id).firstOrNull;
    if (profile == null || profile.url.isEmpty) return;
    _setBusy(id, true);
    try {
      final download = await _subscriptions.download(profile.url);
      final updated = profile.copyWith(
        // A server-side rename only applies while the user has not set a
        // custom label: labels derived from the URL are refreshed.
        label: _isDerivedLabel(profile) && download.suggestedLabel != null
            ? download.suggestedLabel
            : profile.label,
        subscriptionInfo: download.subscriptionInfo,
        config: download.config,
        lastUpdateAt: DateTime.now(),
      );
      _replaceProfile(updated);
      await _persistProfiles();
      if (activeProfileId.value == id) {
        await activateProfile(id);
      }
    } finally {
      _setBusy(id, false);
    }
  }

  /// Removes a stored subscription (FlClash's profile delete action). The
  /// core keeps running with whatever config it currently holds.
  Future<void> deleteProfile(String id) async {
    profiles.value = [
      for (final profile in profiles.value)
        if (profile.id != id) profile,
    ];
    if (activeProfileId.value == id) {
      activeProfileId.value = null;
    }
    await _persistProfiles();
    if (_api == null) {
      // Offline the group list derives from the profile; re-derive it.
      _refreshProxiesFromProfile();
    }
  }

  /// Pushes a stored config to the running core and restores the remembered
  /// node selection per group (FlClash `applyProfile` + `patchSelectGroup`,
  /// expressed as `PUT /configs` + `PUT /proxies/:group`).
  ///
  /// Throws [ClashApiException] when the core rejects the config; the error
  /// message comes from the core's own YAML validation. Without an attached
  /// core this only switches the active profile locally, so its nodes can be
  /// browsed and picked; the remembered picks apply once a core runs.
  Future<void> activateProfile(String id) async {
    final api = _api;
    final profile = profiles.value.where((p) => p.id == id).firstOrNull;
    if (profile == null || profile.config.isEmpty) return;

    if (api == null) {
      activeProfileId.value = id;
      await _persistProfiles();
      _refreshProxiesFromProfile();
      return;
    }

    _setBusy(id, true);
    try {
      await api.applyConfigPayload(profile.config);
      activeProfileId.value = id;
      await _persistProfiles();

      // The new config replaced every group; resync and replay the nodes the
      // user had picked last time this profile ran.
      runningConfig.value = await api.fetchConfigs();
      await refreshProxies();
      await _restoreSelections(profile);
    } finally {
      _setBusy(id, false);
    }
  }

  Future<void> _restoreSelections(ClashProfile profile) async {
    final api = _api;
    if (api == null) return;
    for (final entry in profile.selectedMap.entries) {
      final group = proxyGroups.value.where((g) => g.name == entry.key).firstOrNull;
      if (group == null) continue;
      if (!group.all.contains(entry.value)) continue;
      if (group.realNow == entry.value) continue;
      try {
        await api.selectProxy(entry.key, entry.value);
      } on ClashApiException {
        // Group not selectable / node gone — skip to the next entry.
      }
    }
    await refreshProxies();
  }

  void _replaceProfile(ClashProfile updated) {
    profiles.value = [
      for (final profile in profiles.value)
        profile.id == updated.id ? updated : profile,
    ];
  }

  bool _isDerivedLabel(ClashProfile profile) {
    final derived = _hostOf(profile.url);
    return profile.label == derived ||
        profile.label == profile.url ||
        profile.label == profile.id;
  }

  String? _hostOf(String url) => Uri.tryParse(url)?.host;

  /// Records a node selection on the running profile (FlClash stores the same
  /// `selectedMap` on the profile so it survives re-activation).
  void _recordSelection(String groupName, String proxyName) {
    final profile = activeProfile;
    if (profile == null) return;
    if (profile.selectedMap[groupName] == proxyName) return;
    _replaceProfile(
      profile.copyWith(selectedMap: {...profile.selectedMap, groupName: proxyName}),
    );
    _persistProfiles();
  }

  /// Connects to the core: probes it, loads the snapshot and starts the
  /// traffic / log streams and the connection poller.
  Future<void> connect() async {
    if (status.value == ClashStatus.connecting) return;
    status.value = ClashStatus.connecting;
    statusMessage.value = '';

    final api = ClashApiService(
      host: apiHost.value,
      port: apiPort.value,
      secret: apiSecret.value,
    );

    try {
      version.value = await api.fetchVersion();
      final config = await api.fetchConfigs();
      runningConfig.value = config;
      _api = api;
      await refreshProxies();
      await refreshConnections();
      unawaited(
        api.fetchRules().then((rules) => ruleCount.value = rules.length),
      );
      status.value = ClashStatus.connected;
      statusMessage.value = '';
      _startStreams();
    } on ClashApiException catch (error) {
      status.value = ClashStatus.error;
      statusMessage.value = error.message;
      _refreshProxiesFromProfile();
    } on TimeoutException {
      status.value = ClashStatus.error;
      statusMessage.value = '连接核心超时';
      _refreshProxiesFromProfile();
    } on Exception catch (error) {
      status.value = ClashStatus.error;
      statusMessage.value = error.toString();
      _refreshProxiesFromProfile();
    }
  }

  /// Auto-connects once from the initial disconnected state so simply opening
  /// the app window is enough when a core is already running.
  Future<void> ensureAutoConnect() async {
    await init();
    if (status.value == ClashStatus.disconnected) {
      unawaited(connect());
    }
  }

  /// Disconnects and stops all streams and timers. The proxies view keeps
  /// rendering the active profile's parsed nodes for local browsing.
  void disconnect() {
    _stopStreams();
    _api = null;
    status.value = ClashStatus.disconnected;
    statusMessage.value = '';
    trafficHistory.value = const [];
    _refreshProxiesFromProfile();
  }

  void _startStreams() {
    _stopStreams();
    final api = _api;
    if (api == null) return;

    _trafficCancel = CancelToken();
    _trafficSub = api.streamTraffic(_trafficCancel!).listen(
      (traffic) {
        final history = [...trafficHistory.value, traffic];
        trafficHistory.value = history.length > _maxTrafficSamples
            ? history.sublist(history.length - _maxTrafficSamples)
            : history;
      },
      onError: (_) => _onStreamFailure('流量流中断，核心可能已停止'),
    );

    _logsCancel = CancelToken();
    _logsSub = api.streamLogs(ClashLogLevel.debug, _logsCancel!).listen(
      (log) {
        final next = [...logs.value, log];
        logs.value = next.length > _maxLogs
            ? next.sublist(next.length - _maxLogs)
            : next;
      },
      onError: (_) => _onStreamFailure('日志流中断，核心可能已停止'),
    );

    _connectionsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refreshConnections(showErrors: false));
    });
  }

  void _stopStreams() {
    _trafficSub?.cancel();
    _trafficSub = null;
    _logsSub?.cancel();
    _logsSub = null;
    _trafficCancel?.cancel();
    _trafficCancel = null;
    _logsCancel?.cancel();
    _logsCancel = null;
    _connectionsTimer?.cancel();
    _connectionsTimer = null;
  }

  void _onStreamFailure(String message) {
    if (status.value != ClashStatus.connected) return;
    _stopStreams();
    status.value = ClashStatus.error;
    statusMessage.value = message;
  }

  /// Reloads the proxies snapshot and rebuilds the group list.
  ///
  /// Groups are discovered the way the yacd dashboard does it: the `GLOBAL`
  /// entry lists every top-level group in config order; entries are groups
  /// when they carry members of their own. Whenever no core is attached, the
  /// core answers with an error, or its config has no groups, the list falls
  /// back to parsing the active profile's stored subscription so imported
  /// nodes stay visible and selectable.
  Future<void> refreshProxies() async {
    final api = _api;
    if (api == null) {
      _refreshProxiesFromProfile();
      return;
    }
    final Map<String, ClashProxy> proxies;
    try {
      proxies = await api.fetchProxies();
    } on ClashApiException {
      _refreshProxiesFromProfile();
      return;
    }

    final global = proxies['GLOBAL'];
    final candidateNames = (global?.all ?? const [])
        .where((name) => name != 'GLOBAL')
        .toList();
    // Fallback for cores without a GLOBAL entry: treat every entry that has
    // members as a group.
    if (candidateNames.isEmpty) {
      candidateNames.addAll(
        proxies.values.where((p) => p.all.isNotEmpty).map((p) => p.name),
      );
    }

    final groups = <ClashProxyGroup>[];
    for (final name in candidateNames) {
      final proxy = proxies[name];
      if (proxy == null || proxy.all.isEmpty) continue;
      final members = [
        for (final memberName in proxy.all) proxies[memberName],
      ].whereType<ClashProxy>().toList();
      groups.add(
        ClashProxyGroup(
          name: proxy.name,
          type: ClashGroupType.parse(proxy.type),
          all: proxy.all,
          proxies: members,
          now: proxy.now,
        ),
      );
    }

    if (groups.isEmpty) {
      // A core without an applied config has nothing to show either.
      _refreshProxiesFromProfile();
      return;
    }
    proxyGroups.value = groups;
    proxiesFromProfile.value = false;
    _ensureSelectedGroup(groups);
  }

  /// Rebuilds [proxyGroups] from the active profile's stored YAML — the
  /// no-core path of [refreshProxies]. Selection state comes from the
  /// profile's remembered [ClashProfile.selectedMap].
  void _refreshProxiesFromProfile() {
    final profile = activeProfile;
    if (profile == null || profile.config.isEmpty) {
      proxyGroups.value = const [];
      proxiesFromProfile.value = false;
      selectedGroupName.value = null;
      return;
    }
    final groups = [
      for (final group in groupsForLocalDisplay(parseClashConfig(profile.config)))
        ClashProxyGroup(
          name: group.name,
          type: group.type,
          all: group.all,
          proxies: group.proxies,
          now: _rememberedSelection(profile, group),
        ),
    ];
    proxyGroups.value = groups;
    proxiesFromProfile.value = true;
    _ensureSelectedGroup(groups);
  }

  /// The profile's remembered selection of [group], when that node still
  /// exists in it.
  String? _rememberedSelection(ClashProfile profile, ClashProxyGroup group) {
    final selected = profile.selectedMap[group.name];
    if (selected == null || !group.all.contains(selected)) return null;
    return selected;
  }

  /// Keeps a valid group selected when the config changes underneath us.
  void _ensureSelectedGroup(List<ClashProxyGroup> groups) {
    final selected = selectedGroupName.value;
    if (groups.isEmpty) {
      selectedGroupName.value = null;
    } else if (selected == null || !groups.any((g) => g.name == selected)) {
      selectedGroupName.value = groups.first.name;
    }
  }

  /// The currently viewed group, if any.
  ClashProxyGroup? get selectedGroup {
    final name = selectedGroupName.value;
    if (name == null) return null;
    for (final group in proxyGroups.value) {
      if (group.name == name) return group;
    }
    return null;
  }

  /// Switches the active node of a group (`PUT /proxies/:group`).
  ///
  /// Optimistically updates the snapshot so the UI reacts instantly; the
  /// periodic refresh reconciles with the core afterwards. Without a core
  /// the pick is only recorded on the profile — [activateProfile] replays it
  /// once a core is attached.
  Future<void> selectProxy(String groupName, String proxyName) async {
    final api = _api;
    if (api != null) {
      await api.selectProxy(groupName, proxyName);
    }
    _recordSelection(groupName, proxyName);
    proxyGroups.value = [
      for (final group in proxyGroups.value)
        if (group.name == groupName)
          ClashProxyGroup(
            name: group.name,
            type: group.type,
            all: group.all,
            proxies: group.proxies,
            now: proxyName,
          )
        else
          group,
    ];
  }

  /// Tests the latency of a single node.
  Future<void> testNodeDelay(String name) async {
    final api = _api;
    if (api == null) return;
    testingNodes.value = {...testingNodes.value, name};
    try {
      final delay = await api.testDelay(name);
      final delays = Map<String, int>.of(nodeDelays.value);
      delays[name] = delay;
      nodeDelays.value = delays;
    } on ClashApiException {
      // Leave the previous value; the user can retry.
    } finally {
      final testing = Set<String>.of(testingNodes.value)..remove(name);
      testingNodes.value = testing;
    }
  }

  /// Tests every node of a group in small concurrent batches (FlClash's
  /// "test group delay" action).
  Future<void> testGroupDelays(ClashProxyGroup group) async {
    final nodes = group.proxies.map((proxy) => proxy.name).toList();
    for (var i = 0; i < nodes.length; i += _delayTestBatchSize) {
      final batch = nodes.skip(i).take(_delayTestBatchSize);
      await Future.wait(
        batch.map((name) => testNodeDelay(name).catchError((_) {})),
      );
    }
  }

  /// Switches the outbound mode (`PATCH /configs`).
  Future<void> switchMode(ClashProxyMode mode) async {
    final api = _api;
    final config = runningConfig.value;
    if (api == null || config == null) return;
    await api.patchConfigs({'mode': mode.value});
    runningConfig.value = ClashRunningConfig(
      mode: mode,
      mixedPort: config.mixedPort,
      port: config.port,
      socksPort: config.socksPort,
      allowLan: config.allowLan,
      logLevel: config.logLevel,
    );
  }

  /// Reloads the connections snapshot (`GET /connections`).
  Future<void> refreshConnections({bool showErrors = true}) async {
    final api = _api;
    if (api == null) return;
    try {
      final snapshot = await api.fetchConnections();
      connections.value = snapshot.connections;
      uploadTotal.value = snapshot.uploadTotal;
      downloadTotal.value = snapshot.downloadTotal;
    } on ClashApiException catch (error) {
      if (showErrors) {
        statusMessage.value = error.message;
      }
    }
  }

  /// Closes one active connection.
  Future<void> closeConnection(String id) async {
    final api = _api;
    if (api == null) return;
    await api.closeConnection(id);
    connections.value = [
      for (final connection in connections.value)
        if (connection.id != id) connection,
    ];
  }

  /// Closes every active connection.
  Future<void> closeAllConnections() async {
    final api = _api;
    if (api == null) return;
    await api.closeAllConnections();
    connections.value = const [];
  }

  /// Drops the buffered log lines (FlClash's "clear logs" action).
  void clearLogs() {
    logs.value = const [];
  }
}
