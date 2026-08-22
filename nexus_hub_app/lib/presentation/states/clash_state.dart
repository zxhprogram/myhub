import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:dio/io.dart' show IOHttpClientAdapter;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/clash_models.dart';
import '../../data/services/clash_api_service.dart';
import '../../data/services/clash_config_parser.dart';
import '../../data/services/clash_overwrite_service.dart';
import '../../data/services/clash_subscription_service.dart';
import '../../data/services/clash_system_proxy.dart';

/// Connection lifecycle of the Clash virtual app.
enum ClashStatus { disconnected, connecting, connected, error }

/// Signals-backed singleton state for the Clash virtual app.
///
/// Core functionality ported from FlClash's Riverpod layer
/// (`lib/providers/`): proxies snapshot + node selection + delay testing,
/// live connections with close actions, streaming logs, traffic and memory
/// sampling, mode / config hot patching, the new-connection request stream,
/// external provider management, the editable dashboard widget grid and the
/// profile pipeline (import from URL / file, auto-update, rule overwrite,
/// DNS override) — re-expressed on top of the external controller REST API
/// and this hub's Signals conventions (see `PomodoroState`).
class ClashState {
  ClashState._();

  static final ClashState instance = ClashState._();

  static const _hostKey = 'nexus_clash_host_v1';
  static const _portKey = 'nexus_clash_port_v1';
  static const _secretKey = 'nexus_clash_secret_v1';
  static const _profilesKey = 'nexus_clash_profiles_v1';
  static const _activeProfileKey = 'nexus_clash_active_profile_v1';
  static const _settingsKey = 'nexus_clash_settings_v1';

  static const _maxLogs = 500;
  static const _maxTrafficSamples = 60;
  static const _maxRequests = 200;
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

  // ----- persisted UI / behavior settings (FlClash's AppSettingProps etc.) -----

  /// Cards shown on the dashboard, in display order (FlClash's editable
  /// dashboard widget grid).
  final dashboardWidgets =
      signal<List<ClashDashboardWidget>>(clashDefaultDashboardWidgets);

  final proxiesLayout = signal<ClashProxiesLayout>(ClashProxiesLayout.tabs);
  final proxiesSort = signal<ClashProxiesSort>(ClashProxiesSort.defaultOrder);

  /// Close every connection after a node switch (FlClash
  /// `AppSettingProps.closeConnections`).
  final closeConnectionsOnSwitch = signal<bool>(false);

  /// URL used by every delay test (FlClash `AppSettingProps.testUrl`).
  final testUrl =
      signal<String>(ClashApiService.defaultTestUrl);

  /// Windows system proxy bypass list (FlClash `NetworkProps.bypassDomain`).
  final systemProxyBypass = signal<String>(
    ClashSystemProxyService.defaultBypass,
  );

  /// Whether the DNS override is merged into profiles on activation
  /// (FlClash `Config.overrideDns`).
  final dnsOverrideEnabled = signal<bool>(false);

  /// The DNS override payload; defaults to FlClash's template.
  final dnsOverride = signal<ClashDnsSettings?>(null);

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

  /// New connections since the stream started, newest first (FlClash's
  /// requests view, which is fed by the core's request hook; here it is
  /// derived by diffing the connection snapshots).
  final requests = signal<List<ClashConnection>>(const []);

  final uploadTotal = signal<int>(0);
  final downloadTotal = signal<int>(0);

  final rules = signal<List<ClashRule>>(const []);
  final ruleCount = signal<int>(0);

  final proxyProviders = signal<List<ClashProxyProvider>>(const []);
  final ruleProviders = signal<List<ClashRuleProvider>>(const []);
  final updatingProviders = signal<Set<String>>(const {});

  /// In-use core memory in bytes (`GET /memory` stream, FlClash's memory
  /// dashboard widget).
  final memory = signal<int>(0);

  /// Exit IP detection result (FlClash's network detection widget).
  final networkInfo = signal<ClashNetworkInfo?>(null);
  final networkChecking = signal<bool>(false);

  /// Whether the Windows system proxy currently points at the core.
  final systemProxyEnabled = signal<bool>(false);
  final systemProxyBusy = signal<bool>(false);

  final logs = signal<List<ClashLog>>(const []);
  final trafficHistory = signal<List<ClashTraffic>>(const []);

  bool _endpointLoaded = false;
  ClashApiService? _api;
  ClashSubscriptionService? _subscriptionService;
  StreamSubscription<ClashTraffic>? _trafficSub;
  StreamSubscription<ClashLog>? _logsSub;
  StreamSubscription<int>? _memorySub;
  CancelToken? _trafficCancel;
  CancelToken? _logsCancel;
  CancelToken? _memoryCancel;
  Timer? _connectionsTimer;
  Timer? _autoUpdateTimer;

  /// Connection bookkeeping for speed deltas and the requests diff.
  final Map<String, ClashConnection> _previousConnectionsById = {};
  DateTime? _lastConnectionsPollAt;
  bool _requestsSeeded = false;

  /// Current throughput sample, or zeros when idle.
  ClashTraffic get currentTraffic =>
      trafficHistory.value.isEmpty
          ? const ClashTraffic()
          : trafficHistory.value.last;

  /// Loads the persisted endpoint configuration, subscription profiles and
  /// UI settings, then starts the profile auto-update timer.
  Future<void> init() async {
    if (_endpointLoaded) return;
    _endpointLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      apiHost.value = prefs.getString(_hostKey) ?? apiHost.value;
      apiPort.value = prefs.getInt(_portKey) ?? apiPort.value;
      apiSecret.value = prefs.getString(_secretKey) ?? apiSecret.value;
      _loadProfiles(prefs);
      _loadSettings(prefs);
    } catch (_) {
      // Storage unavailable — keep the 127.0.0.1:9090 defaults.
    }
    // Show the imported nodes right away; a successful core connection
    // replaces them with the live snapshot.
    _refreshProxiesFromProfile();
    unawaited(syncSystemProxyState());
    _autoUpdateTimer ??= Timer.periodic(
      const Duration(minutes: 1),
      (_) => _autoUpdateTick(),
    );
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

  void _loadSettings(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_settingsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final widgets = decoded['dashboardWidgets'];
      if (widgets is List && widgets.isNotEmpty) {
        dashboardWidgets.value = ClashDashboardWidget.parseList(
          [for (final name in widgets) name.toString()],
        );
      }
      proxiesLayout.value = ClashProxiesLayout.parse(
        decoded['proxiesLayout']?.toString(),
      );
      proxiesSort.value = ClashProxiesSort.parse(
        decoded['proxiesSort']?.toString(),
      );
      closeConnectionsOnSwitch.value =
          decoded['closeConnectionsOnSwitch'] as bool? ?? false;
      testUrl.value =
          decoded['testUrl']?.toString() ?? ClashApiService.defaultTestUrl;
      systemProxyBypass.value =
          decoded['systemProxyBypass']?.toString() ??
          ClashSystemProxyService.defaultBypass;
      dnsOverrideEnabled.value = decoded['dnsOverrideEnabled'] as bool? ?? false;
      final dnsJson = decoded['dnsOverride'];
      if (dnsJson is Map<String, dynamic>) {
        dnsOverride.value = ClashDnsSettings.fromMap(dnsJson);
      }
    } catch (_) {
      // Corrupted store — keep the defaults.
    }
  }

  Map<String, dynamic> _settingsSnapshot() => {
    'dashboardWidgets': [
      for (final widget in dashboardWidgets.value) widget.name,
    ],
    'proxiesLayout': proxiesLayout.value.name,
    'proxiesSort': proxiesSort.value.name,
    'closeConnectionsOnSwitch': closeConnectionsOnSwitch.value,
    'testUrl': testUrl.value,
    'systemProxyBypass': systemProxyBypass.value,
    'dnsOverrideEnabled': dnsOverrideEnabled.value,
    'dnsOverride': dnsOverride.value?.toMap(),
  };

  Future<void> _persistSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, jsonEncode(_settingsSnapshot()));
    } catch (_) {
      // Persistence is best-effort.
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

  Future<void> _persistEndpoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_hostKey, apiHost.value);
      await prefs.setInt(_portKey, apiPort.value);
      await prefs.setString(_secretKey, apiSecret.value);
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
    await _persistEndpoint();
    if (status.value == ClashStatus.connected) {
      await connect();
    }
  }

  // -----------------------------------------------------------------------
  // UI / behavior settings
  // -----------------------------------------------------------------------

  Future<void> setDashboardWidgets(List<ClashDashboardWidget> widgets) async {
    dashboardWidgets.value = List.of(widgets);
    await _persistSettings();
  }

  Future<void> setProxiesLayout(ClashProxiesLayout layout) async {
    proxiesLayout.value = layout;
    await _persistSettings();
  }

  Future<void> setProxiesSort(ClashProxiesSort sort) async {
    proxiesSort.value = sort;
    await _persistSettings();
  }

  Future<void> setCloseConnectionsOnSwitch(bool value) async {
    closeConnectionsOnSwitch.value = value;
    await _persistSettings();
  }

  Future<void> setTestUrl(String url) async {
    final trimmed = url.trim();
    testUrl.value = trimmed.isEmpty ? ClashApiService.defaultTestUrl : trimmed;
    await _persistSettings();
  }

  Future<void> setSystemProxyBypass(String bypass) async {
    systemProxyBypass.value = bypass.trim().isEmpty
        ? ClashSystemProxyService.defaultBypass
        : bypass.trim();
    await _persistSettings();
  }

  /// Enables / disables the DNS override; enabling without a stored payload
  /// installs FlClash's default template.
  Future<void> setDnsOverrideEnabled(bool enabled) async {
    dnsOverrideEnabled.value = enabled;
    if (enabled && dnsOverride.value == null) {
      dnsOverride.value = ClashDnsSettings.defaultOverride();
    }
    await _persistSettings();
  }

  Future<void> setDnsOverride(ClashDnsSettings settings) async {
    dnsOverride.value = settings;
    await _persistSettings();
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

  /// Imports a profile from a local YAML file (FlClash `addProfileFromFile`).
  Future<ClashProfile> addLocalProfile({
    required String config,
    String label = '',
  }) async {
    final parsed = parseClashConfig(config);
    if (parsed.proxies.isEmpty && parsed.groups.isEmpty) {
      throw const ClashSubscriptionException(
        '文件中未找到任何代理节点（proxies / proxy-groups）',
      );
    }
    final now = DateTime.now();
    final profile = ClashProfile(
      id: 'p${now.microsecondsSinceEpoch}',
      label: label.trim().isNotEmpty ? label.trim() : '本地配置',
      url: '',
      addedAt: now,
      lastUpdateAt: now,
      config: config,
    );
    profiles.value = [...profiles.value, profile];
    if (activeProfileId.value == null) {
      activeProfileId.value = profile.id;
    }
    await _persistProfiles();
    if (activeProfileId.value == profile.id) {
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

  /// Updates every subscription that has a URL (FlClash's "update all"
  /// action); local profiles are skipped.
  Future<void> updateAllProfiles() async {
    for (final profile in profiles.value) {
      if (profile.url.isEmpty) continue;
      try {
        await updateProfile(profile.id);
      } catch (_) {
        // Keep going — one broken subscription must not block the rest.
      }
    }
  }

  /// Edits the stored metadata of a profile (FlClash's profile edit sheet).
  Future<void> updateProfileMeta(
    String id, {
    String? label,
    String? url,
    bool? autoUpdate,
    int? autoUpdateIntervalMinutes,
  }) async {
    final profile = profiles.value.where((p) => p.id == id).firstOrNull;
    if (profile == null) return;
    _replaceProfile(
      profile.copyWith(
        label: label?.trim().isEmpty == true ? profile.label : label,
        url: url,
        autoUpdate: autoUpdate,
        autoUpdateIntervalMinutes: autoUpdateIntervalMinutes,
      ),
    );
    await _persistProfiles();
  }

  /// Stores the per-profile rule overwrite (FlClash's standard overwrite
  /// scene) and re-applies the profile when it is the running one.
  Future<void> setProfileOverwrite(
    String id, {
    required List<String> addedRules,
    required List<String> disabledRules,
  }) async {
    final profile = profiles.value.where((p) => p.id == id).firstOrNull;
    if (profile == null) return;
    _replaceProfile(
      profile.copyWith(addedRules: addedRules, disabledRules: disabledRules),
    );
    await _persistProfiles();
    if (activeProfileId.value == id && _api != null) {
      unawaited(
        activateProfile(id).catchError((_) {}),
      );
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

  /// The config that would be pushed for [profile] right now: the stored
  /// YAML plus the rule overwrite and DNS override. Used by the profile
  /// preview dialog.
  String finalConfigOf(ClashProfile profile) {
    return ClashConfigOverwriter.buildFinalConfig(
      profile,
      dnsOverride: dnsOverrideEnabled.value ? dnsOverride.value : null,
    );
  }

  /// Pushes a stored config to the running core and restores the remembered
  /// node selection per group (FlClash `applyProfile` + `patchSelectGroup`,
  /// expressed as `PUT /configs` + `PUT /proxies/:group`).
  ///
  /// Before the push the stored YAML is run through the overwrite pipeline
  /// (rule overwrite + DNS override). Throws [ClashApiException] when the
  /// core rejects the config; the error message comes from the core's own
  /// YAML validation. Without an attached core this only switches the active
  /// profile locally, so its nodes can be browsed and picked; the remembered
  /// picks apply once a core runs.
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
      await api.applyConfigPayload(
        ClashConfigOverwriter.buildFinalConfig(
          profile,
          dnsOverride: dnsOverrideEnabled.value ? dnsOverride.value : null,
        ),
      );
      activeProfileId.value = id;
      await _persistProfiles();

      // The new config replaced every group; resync and replay the nodes the
      // user had picked last time this profile ran.
      runningConfig.value = await api.fetchConfigs();
      await refreshProxies();
      await refreshRules(showErrors: false);
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

  /// Periodic subscription refresh (FlClash `autoUpdateProfiles`): every
  /// minute the timer updates every profile whose interval elapsed.
  void _autoUpdateTick() {
    final now = DateTime.now();
    for (final profile in profiles.value) {
      if (!profile.autoUpdate || profile.url.isEmpty) continue;
      if (profile.autoUpdateIntervalMinutes <= 0) continue;
      if (busyProfileIds.value.contains(profile.id)) continue;
      final last = profile.lastUpdateAt ?? profile.addedAt;
      if (now.difference(last).inMinutes >= profile.autoUpdateIntervalMinutes) {
        unawaited(
          updateProfile(profile.id).catchError((_) {}),
        );
      }
    }
  }

  // -----------------------------------------------------------------------
  // Core connection & streams
  // -----------------------------------------------------------------------

  /// Connects to the core: probes it, loads the snapshot and starts the
  /// traffic / log / memory streams and the connection poller.
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
      unawaited(refreshRules(showErrors: false));
      unawaited(refreshProxyProviders(showErrors: false));
      unawaited(refreshRuleProviders(showErrors: false));
      unawaited(detectNetwork());
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
    requests.value = const [];
    connections.value = const [];
    rules.value = const [];
    ruleCount.value = 0;
    proxyProviders.value = const [];
    ruleProviders.value = const [];
    memory.value = 0;
    _previousConnectionsById.clear();
    _lastConnectionsPollAt = null;
    _requestsSeeded = false;
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

    // Older cores expose no /memory endpoint — a failure here is not fatal.
    _memoryCancel = CancelToken();
    _memorySub = api.streamMemory(_memoryCancel!).listen(
      (value) => memory.value = value,
      onError: (_) {},
    );

    _requestsSeeded = false;
    _previousConnectionsById.clear();
    _connectionsTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(refreshConnections(showErrors: false));
    });
  }

  void _stopStreams() {
    _trafficSub?.cancel();
    _trafficSub = null;
    _logsSub?.cancel();
    _logsSub = null;
    _memorySub?.cancel();
    _memorySub = null;
    _trafficCancel?.cancel();
    _trafficCancel = null;
    _logsCancel?.cancel();
    _logsCancel = null;
    _memoryCancel?.cancel();
    _memoryCancel = null;
    _connectionsTimer?.cancel();
    _connectionsTimer = null;
  }

  void _onStreamFailure(String message) {
    if (status.value != ClashStatus.connected) return;
    _stopStreams();
    status.value = ClashStatus.error;
    statusMessage.value = message;
  }

  // -----------------------------------------------------------------------
  // Proxies (FlClash lib/providers/actions/proxies.dart)
  // -----------------------------------------------------------------------

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
  /// periodic refresh reconciles with the core afterwards. Optionally closes
  /// every connection first (FlClash `AppSettingProps.closeConnections`).
  /// Without a core the pick is only recorded on the profile —
  /// [activateProfile] replays it once a core is attached.
  Future<void> selectProxy(String groupName, String proxyName) async {
    final api = _api;
    if (api != null) {
      await api.selectProxy(groupName, proxyName);
      if (closeConnectionsOnSwitch.value) {
        unawaited(
          api.closeAllConnections().catchError((_) {}),
        );
      }
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

  /// Tests the latency of a single node against the configured test URL.
  Future<void> testNodeDelay(String name) async {
    final api = _api;
    if (api == null) return;
    testingNodes.value = {...testingNodes.value, name};
    try {
      final delay = await api.testDelay(name, url: testUrl.value);
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

  // -----------------------------------------------------------------------
  // External providers (FlClash's providers management)
  // -----------------------------------------------------------------------

  Future<void> refreshProxyProviders({bool showErrors = true}) async {
    final api = _api;
    if (api == null) return;
    try {
      final providers = await api.fetchProxyProviders();
      providers.sort((a, b) => a.name.compareTo(b.name));
      proxyProviders.value = providers;
    } on ClashApiException catch (error) {
      if (showErrors) statusMessage.value = error.message;
    }
  }

  /// Refreshes one proxy provider and merges the health-check results of its
  /// nodes into [nodeDelays].
  Future<void> updateProxyProvider(String name) async {
    final api = _api;
    if (api == null) return;
    _setProviderBusy(name, true);
    try {
      await api.updateProxyProvider(name);
      try {
        final delays = await api.healthcheckProxyProvider(name);
        final merged = Map<String, int>.of(nodeDelays.value)..addAll(delays);
        nodeDelays.value = merged;
      } on ClashApiException {
        // Health check is optional — the refresh itself already succeeded.
      }
      await refreshProxyProviders(showErrors: false);
    } finally {
      _setProviderBusy(name, false);
    }
  }

  Future<void> refreshRuleProviders({bool showErrors = true}) async {
    final api = _api;
    if (api == null) return;
    try {
      final providers = await api.fetchRuleProviders();
      providers.sort((a, b) => a.name.compareTo(b.name));
      ruleProviders.value = providers;
    } on ClashApiException catch (error) {
      if (showErrors) statusMessage.value = error.message;
    }
  }

  Future<void> updateRuleProvider(String name) async {
    final api = _api;
    if (api == null) return;
    _setProviderBusy(name, true);
    try {
      await api.updateRuleProvider(name);
      await refreshRuleProviders(showErrors: false);
    } finally {
      _setProviderBusy(name, false);
    }
  }

  void _setProviderBusy(String name, bool busy) {
    final next = Set<String>.of(updatingProviders.value);
    busy ? next.add(name) : next.remove(name);
    updatingProviders.value = next;
  }

  // -----------------------------------------------------------------------
  // Runtime configuration (PATCH /configs hot patching)
  // -----------------------------------------------------------------------

  /// Applies a partial config update and reloads the running config.
  Future<void> patchConfig(Map<String, dynamic> payload) async {
    final api = _api;
    if (api == null) return;
    await api.patchConfigs(payload);
    runningConfig.value = await api.fetchConfigs();
  }

  /// Switches the outbound mode (`PATCH /configs {"mode": ..}`).
  Future<void> switchMode(ClashProxyMode mode) async {
    await patchConfig({'mode': mode.value});
  }

  /// Hot-patches the TUN inbound (FlClash's TUN toggle). The controller
  /// replaces the whole `tun` block, so the current settings are merged in.
  Future<void> applyTunSettings(ClashTunSettings settings) async {
    await patchConfig({'tun': settings.toMap()});
  }

  Future<void> setTunEnabled(bool enabled) async {
    final current = runningConfig.value?.tun ?? const ClashTunSettings();
    await applyTunSettings(current.copyWith(enable: enabled));
  }

  // -----------------------------------------------------------------------
  // Rules / connections / requests (FlClash's rules, connections & requests views)
  // -----------------------------------------------------------------------

  /// Reloads the routing rule table (`GET /rules`).
  Future<void> refreshRules({bool showErrors = true}) async {
    final api = _api;
    if (api == null) return;
    try {
      final rules = await api.fetchRules();
      this.rules.value = rules;
      ruleCount.value = rules.length;
    } on ClashApiException catch (error) {
      if (showErrors) statusMessage.value = error.message;
    }
  }

  /// Reloads the connections snapshot (`GET /connections`), computes
  /// per-connection speeds from the deltas and appends newly seen
  /// connections to [requests].
  Future<void> refreshConnections({bool showErrors = true}) async {
    final api = _api;
    if (api == null) return;
    try {
      final snapshot = await api.fetchConnections();
      _applyConnectionsSnapshot(snapshot);
    } on ClashApiException catch (error) {
      if (showErrors) {
        statusMessage.value = error.message;
      }
    }
  }

  void _applyConnectionsSnapshot(ClashConnectionsSnapshot snapshot) {
    final now = DateTime.now();
    final previous = _previousConnectionsById;
    final elapsedSeconds = _lastConnectionsPollAt == null
        ? 1
        : math.max(1, now.difference(_lastConnectionsPollAt!).inSeconds);
    _lastConnectionsPollAt = now;

    final recordRequests = _requestsSeeded;
    final newRequests = <ClashConnection>[];
    final withSpeeds = <ClashConnection>[];
    for (final connection in snapshot.connections) {
      final before = previous[connection.id];
      if (before == null) {
        withSpeeds.add(connection);
        if (recordRequests) newRequests.add(connection);
      } else {
        withSpeeds.add(
          ClashConnection(
            id: connection.id,
            upload: connection.upload,
            download: connection.download,
            start: connection.start,
            metadata: connection.metadata,
            chains: connection.chains,
            rule: connection.rule,
            rulePayload: connection.rulePayload,
            uploadSpeed:
                math.max(0, connection.upload - before.upload) ~/
                elapsedSeconds,
            downloadSpeed:
                math.max(0, connection.download - before.download) ~/
                elapsedSeconds,
          ),
        );
      }
      previous[connection.id] = connection;
    }
    final currentIds = {for (final connection in snapshot.connections) connection.id};
    previous.removeWhere((id, _) => !currentIds.contains(id));

    if (recordRequests && newRequests.isNotEmpty) {
      requests.value = [
        ...newRequests,
        ...requests.value,
      ].take(_maxRequests).toList();
    }
    _requestsSeeded = true;

    connections.value = withSpeeds;
    uploadTotal.value = snapshot.uploadTotal;
    downloadTotal.value = snapshot.downloadTotal;
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

  /// Drops the buffered request entries (the requests view clear button).
  void clearRequests() {
    requests.value = const [];
  }

  /// Drops the buffered log lines (FlClash's "clear logs" action).
  void clearLogs() {
    logs.value = const [];
  }

  // -----------------------------------------------------------------------
  // Network detection (FlClash's dashboard network detection widget)
  // -----------------------------------------------------------------------

  /// Detects the exit IP. When a core is attached the probe is routed through
  /// its inbound port first, so the result shows the exit node like FlClash;
  /// a direct fallback covers cores without an inbound listener.
  Future<void> detectNetwork() async {
    if (networkChecking.value) return;
    networkChecking.value = true;
    try {
      final inboundPort = runningConfig.value?.inboundPortValue;
      ClashNetworkInfo? info;
      if (inboundPort != null && status.value == ClashStatus.connected) {
        info = await _probeIp(proxyPort: inboundPort);
      }
      info ??= await _probeIp();
      if (info != null) {
        networkInfo.value = info;
      }
    } catch (_) {
      // Keep the previous result on failure.
    } finally {
      networkChecking.value = false;
    }
  }

  Future<ClashNetworkInfo?> _probeIp({int? proxyPort}) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 6),
        validateStatus: (status) => status != null && status < 300,
      ),
    );
    if (proxyPort != null) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.findProxy =
            (uri) => 'PROXY 127.0.0.1:$proxyPort';
        return client;
      };
    }
    const sources = [
      ('https://ipapi.co/json/', true),
      ('https://api.ipify.org?format=json', false),
    ];
    for (final (url, withCountry) in sources) {
      try {
        final response = await dio.get<dynamic>(url);
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final ip = data['ip']?.toString() ?? '';
          if (ip.isNotEmpty) {
            return ClashNetworkInfo(
              ip: ip,
              country: withCountry
                  ? (data['country_name']?.toString() ?? '')
                  : '',
            );
          }
        }
      } catch (_) {
        // Try the next source.
      }
    }
    return null;
  }

  // -----------------------------------------------------------------------
  // System proxy (FlClash's ProxyManager, Windows)
  // -----------------------------------------------------------------------

  /// Reads the WinINET state into [systemProxyEnabled].
  Future<void> syncSystemProxyState() async {
    try {
      systemProxyEnabled.value =
          await ClashSystemProxyService.instance.isEnabled();
    } catch (_) {
      systemProxyEnabled.value = false;
    }
  }

  /// Points the Windows system proxy at the core's inbound port, or restores
  /// direct connections. When the core exposes no listener yet, the default
  /// inbound port (7890) is hot-patched in first so the user never has to
  /// know which port to configure. Throws [ClashSystemProxyException] on
  /// failure.
  Future<void> setSystemProxy(bool enabled) async {
    if (systemProxyBusy.value) return;
    systemProxyBusy.value = true;
    try {
      final service = ClashSystemProxyService.instance;
      if (enabled) {
        var port = runningConfig.value?.inboundPortValue;
        if (port == null) {
          try {
            await patchConfig({
              'mixed-port': ClashConfigOverwriter.defaultMixedPort,
            });
          } on ClashApiException catch (error) {
            throw ClashSystemProxyException(
              '启用默认端口 ${ClashConfigOverwriter.defaultMixedPort} 失败：${error.message}',
            );
          }
          port = runningConfig.value?.inboundPortValue;
        }
        if (port == null) {
          throw const ClashSystemProxyException(
            '无法确定核心的入站端口：请先连接核心并应用订阅，'
            '或在设置的"入站端口"中启用端口',
          );
        }
        await service.enable(
          server: '127.0.0.1:$port',
          bypass: systemProxyBypass.value,
        );
      } else {
        await service.disable();
      }
      systemProxyEnabled.value = enabled;
    } finally {
      systemProxyBusy.value = false;
    }
  }

  // -----------------------------------------------------------------------
  // Backup & restore (FlClash's local file backup)
  // -----------------------------------------------------------------------

  /// Everything persisted by the clash virtual app, as a JSON-serializable
  /// map for the local backup file.
  Map<String, dynamic> exportBackup() => {
    'app': 'nexus-hub-clash',
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'endpoint': {
      'host': apiHost.value,
      'port': apiPort.value,
      'secret': apiSecret.value,
    },
    'activeProfileId': activeProfileId.value,
    'profiles': [for (final profile in profiles.value) profile.toJson()],
    'settings': _settingsSnapshot(),
  };

  /// Restores a backup produced by [exportBackup].
  Future<void> importBackup(Map<String, dynamic> data) async {
    final profilesJson = data['profiles'];
    if (profilesJson is! List || profilesJson.isEmpty) {
      throw const FormatException('备份文件中没有可导入的订阅配置');
    }
    final restored = profilesJson
        .map(
          (item) =>
              item is Map<String, dynamic> ? ClashProfile.fromJson(item) : null,
        )
        .whereType<ClashProfile>()
        .toList();
    if (restored.isEmpty) {
      throw const FormatException('备份文件中没有可导入的订阅配置');
    }

    profiles.value = restored;
    final activeId = data['activeProfileId']?.toString();
    activeProfileId.value = restored.any((p) => p.id == activeId)
        ? activeId
        : restored.first.id;

    final endpoint = data['endpoint'];
    if (endpoint is Map<String, dynamic>) {
      apiHost.value = endpoint['host']?.toString() ?? apiHost.value;
      apiPort.value =
          (endpoint['port'] as num?)?.toInt() ?? apiPort.value;
      apiSecret.value = endpoint['secret']?.toString() ?? '';
      await _persistEndpoint();
    }
    await _persistProfiles();

    final settings = data['settings'];
    if (settings is Map<String, dynamic>) {
      final widgets = settings['dashboardWidgets'];
      if (widgets is List && widgets.isNotEmpty) {
        dashboardWidgets.value = ClashDashboardWidget.parseList(
          [for (final name in widgets) name.toString()],
        );
      }
      proxiesLayout.value = ClashProxiesLayout.parse(
        settings['proxiesLayout']?.toString(),
      );
      proxiesSort.value = ClashProxiesSort.parse(
        settings['proxiesSort']?.toString(),
      );
      closeConnectionsOnSwitch.value =
          settings['closeConnectionsOnSwitch'] as bool? ?? false;
      testUrl.value =
          settings['testUrl']?.toString() ?? ClashApiService.defaultTestUrl;
      systemProxyBypass.value =
          settings['systemProxyBypass']?.toString() ??
          ClashSystemProxyService.defaultBypass;
      dnsOverrideEnabled.value =
          settings['dnsOverrideEnabled'] as bool? ?? false;
      final dnsJson = settings['dnsOverride'];
      if (dnsJson is Map<String, dynamic>) {
        dnsOverride.value = ClashDnsSettings.fromMap(dnsJson);
      }
      await _persistSettings();
    }

    _refreshProxiesFromProfile();
  }
}
