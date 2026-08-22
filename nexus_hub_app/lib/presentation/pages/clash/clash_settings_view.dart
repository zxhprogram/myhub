import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException, ClashApiService;
import '../../../data/services/clash_overwrite_service.dart'
    show ClashConfigOverwriter;
import '../../../data/services/clash_system_proxy.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_input.dart';
import '../../components/nexus_toast.dart';

/// Settings screen, ported from FlClash's config views (`views/config/`):
/// the external controller endpoint, hot-patchable runtime options (ports,
/// general switches, TUN), the DNS override merged on profile activation,
/// the Windows system proxy, app behaviors, backup & restore and the runtime
/// readout of the attached core.
class ClashSettingsView extends StatefulWidget {
  const ClashSettingsView({super.key});

  @override
  State<ClashSettingsView> createState() => _ClashSettingsViewState();
}

class _ClashSettingsViewState extends State<ClashSettingsView> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _secretController = TextEditingController();

  final _mixedPortController = TextEditingController();
  final _httpPortController = TextEditingController();
  final _socksPortController = TextEditingController();
  final _redirPortController = TextEditingController();
  final _tproxyPortController = TextEditingController();

  final _tunDeviceController = TextEditingController();
  final _tunDnsHijackController = TextEditingController();

  final _bypassController = TextEditingController();
  final _testUrlController = TextEditingController();

  bool _userEditedEndpoint = false;
  bool _userEditedPorts = false;
  bool _userEditedTun = false;
  bool _userEditedBypass = false;
  bool _userEditedTestUrl = false;
  bool _savingEndpoint = false;
  bool _applyingPorts = false;
  bool _applyingTun = false;

  @override
  void initState() {
    super.initState();
    _syncEndpointControllers();
    // The persisted endpoint loads asynchronously — refresh the fields once
    // it lands unless the user already started editing.
    ClashState.instance.init().then((_) {
      if (mounted && !_userEditedEndpoint) {
        setState(_syncEndpointControllers);
      }
      _syncPersistedControllers();
    });
  }

  void _syncEndpointControllers() {
    final state = ClashState.instance;
    _hostController.text = state.apiHost.value;
    _portController.text = '${state.apiPort.value}';
    _secretController.text = state.apiSecret.value;
  }

  /// Fills the fields that mirror persisted state / the running config.
  void _syncPersistedControllers() {
    final state = ClashState.instance;
    if (!_userEditedBypass) {
      _bypassController.text = state.systemProxyBypass.value;
    }
    if (!_userEditedTestUrl) {
      _testUrlController.text = state.testUrl.value;
    }
    if (!_userEditedTun) {
      final tun = state.runningConfig.value?.tun;
      _tunDeviceController.text = tun?.device ?? '';
      _tunDnsHijackController.text = tun?.dnsHijack.join(', ') ?? '';
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _secretController.dispose();
    _mixedPortController.dispose();
    _httpPortController.dispose();
    _socksPortController.dispose();
    _redirPortController.dispose();
    _tproxyPortController.dispose();
    _tunDeviceController.dispose();
    _tunDnsHijackController.dispose();
    _bypassController.dispose();
    _testUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() {});
      return;
    }
    setState(() => _savingEndpoint = true);
    final state = ClashState.instance;
    await state.updateEndpoint(
      host: _hostController.text.trim(),
      port: port,
      secret: _secretController.text.trim(),
    );
    await state.connect();
    if (mounted) setState(() => _savingEndpoint = false);
  }

  Future<void> _patch(
    BuildContext context,
    Map<String, dynamic> payload,
    String successMessage,
  ) async {
    try {
      await ClashState.instance.patchConfig(payload);
      if (context.mounted) {
        nexusToast(context, successMessage);
      }
    } on ClashApiException catch (error) {
      if (context.mounted) {
        nexusToast(context, '核心拒绝了修改：${error.message}', isError: true);
      }
    } catch (error) {
      if (context.mounted) {
        nexusToast(context, '修改失败：$error', isError: true);
      }
    }
  }

  /// Reads the five port fields into a `PATCH /configs` payload; empty fields
  /// are skipped, 0 disables the listener.
  Future<void> _applyPorts(BuildContext context) async {
    int? parse(TextEditingController controller) {
      final text = controller.text.trim();
      if (text.isEmpty) return null;
      return int.tryParse(text);
    }

    final mixed = parse(_mixedPortController);
    final http = parse(_httpPortController);
    final socks = parse(_socksPortController);
    final redir = parse(_redirPortController);
    final tproxy = parse(_tproxyPortController);
    if ([mixed, http, socks, redir, tproxy].any((port) => port == null)) {
      nexusToast(context, '端口必须是数字（留空表示不修改，0 表示关闭）', isError: true);
      return;
    }

    setState(() => _applyingPorts = true);
    final payload = <String, dynamic>{
      if (mixed != null) 'mixed-port': mixed,
      if (http != null) 'port': http,
      if (socks != null) 'socks-port': socks,
      if (redir != null) 'redir-port': redir,
      if (tproxy != null) 'tproxy-port': tproxy,
    };
    if (payload.isEmpty) {
      setState(() => _applyingPorts = false);
      return;
    }
    await _patch(context, payload, '端口已更新');
    if (mounted) setState(() => _applyingPorts = false);
  }

  Future<void> _applyTun(BuildContext context) async {
    final tun = ClashState.instance.runningConfig.value?.tun ??
        const ClashTunSettings();
    final device = _tunDeviceController.text.trim();
    final dnsHijack = _tunDnsHijackController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    setState(() => _applyingTun = true);
    try {
      await ClashState.instance.applyTunSettings(
        tun.copyWith(device: device, dnsHijack: dnsHijack),
      );
      if (context.mounted) {
        nexusToast(context, 'TUN 设置已更新');
      }
    } on ClashApiException catch (error) {
      if (context.mounted) {
        nexusToast(context, 'TUN 更新失败：${error.message}', isError: true);
      }
    } catch (error) {
      if (context.mounted) {
        nexusToast(context, 'TUN 更新失败：$error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _applyingTun = false);
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    final state = ClashState.instance;
    final stamp = DateTime.now();
    final name =
        'nexus-clash-backup-${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}.json';
    const typeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
    final location = await getSaveLocation(
      suggestedName: name,
      acceptedTypeGroups: [typeGroup],
    );
    if (location == null) return;
    try {
      final json = const JsonEncoder.withIndent('  ').convert(
        state.exportBackup(),
      );
      await File(location.path).writeAsString(json);
      if (context.mounted) {
        nexusToast(context, '备份已导出');
      }
    } catch (error) {
      if (context.mounted) {
        nexusToast(context, '导出失败：$error', isError: true);
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'JSON', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('备份文件格式无效');
      }
      await ClashState.instance.importBackup(decoded);
      _userEditedPorts = false;
      _userEditedTun = false;
      _userEditedBypass = false;
      _userEditedTestUrl = false;
      if (mounted) {
        setState(() {
          _syncEndpointControllers();
          _syncPersistedControllers();
        });
      }
      if (context.mounted) {
        nexusToast(context, '备份已恢复');
      }
      unawaited(ClashState.instance.connect());
    } on FormatException catch (error) {
      if (context.mounted) {
        nexusToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (context.mounted) {
        nexusToast(context, '导入失败：$error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      final connected = state.status.value == ClashStatus.connected;
      // Sync the port fields from the running config until the user edits.
      if (connected && !_userEditedPorts) {
        final config = state.runningConfig.value;
        _mixedPortController.text = _portText(config?.mixedPort);
        _httpPortController.text = _portText(config?.port);
        _socksPortController.text = _portText(config?.socksPort);
        _redirPortController.text = _portText(config?.redirPort);
        _tproxyPortController.text = _portText(config?.tproxyPort);
      }
      _syncPersistedControllers();

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEndpointCard(context),
            const SizedBox(height: NexusSpacing.md),
            _buildGeneralCard(context, state, connected),
            const SizedBox(height: NexusSpacing.md),
            _buildPortsCard(context, connected),
            const SizedBox(height: NexusSpacing.md),
            _buildTunCard(context, state, connected),
            const SizedBox(height: NexusSpacing.md),
            _buildDnsCard(context, state),
            const SizedBox(height: NexusSpacing.md),
            _buildSystemProxyCard(context, state),
            const SizedBox(height: NexusSpacing.md),
            _buildBehaviorCard(context, state),
            const SizedBox(height: NexusSpacing.md),
            _buildBackupCard(context),
            const SizedBox(height: NexusSpacing.md),
            _buildRuntimeCard(context, state),
            const SizedBox(height: NexusSpacing.md),
            _buildAboutCard(context),
          ],
        ),
      );
    });
  }

  static String _portText(int? port) => port == null ? '' : '$port';

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colorScheme.primary),
              const SizedBox(width: NexusSpacing.sm),
              Text(title, style: NexusTypography.headlineSm),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
          const SizedBox(height: NexusSpacing.md),
          ...children,
        ],
      ),
    );
  }

  Widget _buildEndpointCard(BuildContext context) {
    final portValid = () {
      final port = int.tryParse(_portController.text.trim());
      return port != null && port >= 1 && port <= 65535;
    }();

    return _buildSectionCard(
      context,
      icon: LucideIcons.server,
      title: '核心端点',
      subtitle:
          'Clash 控制台通过 External Controller API 访问运行中的核心，'
          '默认地址为 127.0.0.1:9090（即 mihomo / FlClash 核心的 '
          'external-controller 配置项）。',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: NexusInput(
                controller: _hostController,
                labelText: '服务器地址',
                hintText: '127.0.0.1',
                onChanged: (_) => _userEditedEndpoint = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.md),
            Expanded(
              flex: 2,
              child: NexusInput(
                controller: _portController,
                labelText: '端口',
                hintText: '9090',
                keyboardType: TextInputType.number,
                validator: (value) {
                  final port = int.tryParse(value ?? '');
                  if (port == null || port < 1 || port > 65535) {
                    return '端口无效';
                  }
                  return null;
                },
                onChanged: (_) => _userEditedEndpoint = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.md),
            Expanded(
              flex: 3,
              child: NexusInput(
                controller: _secretController,
                labelText: '访问密钥（可选）',
                hintText: 'secret',
                onChanged: (_) => _userEditedEndpoint = true,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        NexusButton(
          label: '保存并连接',
          icon: LucideIcons.plug,
          isLoading: _savingEndpoint,
          onPressed: portValid && !_savingEndpoint ? _saveAndConnect : null,
        ),
      ],
    );
  }

  /// Hot-patchable general switches, ported from FlClash's
  /// `views/config/general.dart`.
  Widget _buildGeneralCard(
    BuildContext context,
    ClashState state,
    bool connected,
  ) {
    final config = state.runningConfig.value;
    if (config == null) {
      return _buildSectionCard(
        context,
        icon: LucideIcons.settings2,
        title: '常规设置',
        subtitle: '连接核心后可在此调整运行时配置。',
        children: const [SizedBox.shrink()],
      );
    }

    Widget chipRow(String label, List<(String, String, bool)> options) {
      return Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: NexusTypography.bodyMd),
          ),
          for (final (optionLabel, value, selected) in options) ...[
            _SettingsChip(
              label: optionLabel,
              selected: selected,
              onTap: connected
                  ? () => _patch(context, {
                        switch (label) {
                          '日志等级' => 'log-level',
                          '进程识别' => 'find-process-mode',
                          _ => value,
                        }: value,
                      }, '设置已更新')
                  : null,
            ),
            const SizedBox(width: NexusSpacing.xs),
          ],
        ],
      );
    }

    return _buildSectionCard(
      context,
      icon: LucideIcons.settings2,
      title: '常规设置',
      subtitle: '修改会通过 PATCH /configs 即时生效（部分选项取决于核心版本支持）。',
      children: [
        _SettingSwitchRow(
          label: '允许局域网',
          subtitle: '让同一网络内的设备使用此代理端口',
          value: config.allowLan,
          enabled: connected,
          onChanged: (value) =>
              _patch(context, {'allow-lan': value}, '设置已更新'),
        ),
        _SettingSwitchRow(
          label: 'IPv6',
          value: config.ipv6,
          enabled: connected,
          onChanged: (value) => _patch(context, {'ipv6': value}, '设置已更新'),
        ),
        _SettingSwitchRow(
          label: '统一延迟',
          subtitle: '延迟测试去掉握手时间（unified-delay）',
          value: config.unifiedDelay,
          enabled: connected,
          onChanged: (value) =>
              _patch(context, {'unified-delay': value}, '设置已更新'),
        ),
        _SettingSwitchRow(
          label: 'TCP 并发',
          subtitle: '同时尝试所有 IP 地址（tcp-concurrent）',
          value: config.tcpConcurrent,
          enabled: connected,
          onChanged: (value) =>
              _patch(context, {'tcp-concurrent': value}, '设置已更新'),
        ),
        const SizedBox(height: NexusSpacing.sm),
        chipRow('日志等级', [
          for (final level in ClashLogLevel.values)
            (level.label, level.value, config.logLevel == level),
        ]),
        const SizedBox(height: NexusSpacing.sm),
        chipRow('进程识别', [
          ('按规则', 'rule', config.findProcessMode == 'rule'),
          ('总是', 'always', config.findProcessMode == 'always'),
          ('关闭', 'off', config.findProcessMode == 'off'),
        ]),
      ],
    );
  }

  Widget _buildPortsCard(BuildContext context, bool connected) {
    return _buildSectionCard(
      context,
      icon: LucideIcons.plugZap,
      title: '入站端口',
      subtitle:
          '混合端口（mixed-port）同时支持 HTTP 与 SOCKS，是最常用的入站端口。'
          '无需手动填写：应用订阅时若配置没有端口会自动启用 7890；'
          '留空表示不修改，填 0 表示关闭该监听。',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NexusInput(
                controller: _mixedPortController,
                labelText: '混合端口',
                hintText: '7890',
                keyboardType: TextInputType.number,
                onChanged: (_) => _userEditedPorts = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: NexusInput(
                controller: _httpPortController,
                labelText: 'HTTP',
                hintText: '-',
                keyboardType: TextInputType.number,
                onChanged: (_) => _userEditedPorts = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: NexusInput(
                controller: _socksPortController,
                labelText: 'SOCKS',
                hintText: '-',
                keyboardType: TextInputType.number,
                onChanged: (_) => _userEditedPorts = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: NexusInput(
                controller: _redirPortController,
                labelText: 'Redir',
                hintText: '-',
                keyboardType: TextInputType.number,
                onChanged: (_) => _userEditedPorts = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: NexusInput(
                controller: _tproxyPortController,
                labelText: 'TProxy',
                hintText: '-',
                keyboardType: TextInputType.number,
                onChanged: (_) => _userEditedPorts = true,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        Row(
          children: [
            NexusButton(
              label: '应用端口',
              icon: LucideIcons.check,
              isLoading: _applyingPorts,
              onPressed: connected && !_applyingPorts
                  ? () => _applyPorts(context)
                  : null,
            ),
            const SizedBox(width: NexusSpacing.sm),
            NexusButton(
              label: '一键启用默认端口 (7890)',
              icon: LucideIcons.wandSparkles,
              variant: NexusButtonVariant.tonal,
              onPressed: connected && !_applyingPorts
                  ? () => _patch(
                      context,
                      {'mixed-port': ClashConfigOverwriter.defaultMixedPort},
                      '已启用混合端口 ${ClashConfigOverwriter.defaultMixedPort}',
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }

  /// TUN settings, ported from FlClash's `views/config/network.dart`. The
  /// controller replaces the whole `tun` block on every patch, so all fields
  /// ship together.
  Widget _buildTunCard(
    BuildContext context,
    ClashState state,
    bool connected,
  ) {
    final tun = state.runningConfig.value?.tun;
    if (tun == null) {
      return _buildSectionCard(
        context,
        icon: LucideIcons.router,
        title: 'TUN 模式',
        subtitle: '连接核心后可配置 TUN 虚拟网卡（需要核心以管理员权限运行）。',
        children: const [SizedBox.shrink()],
      );
    }

    return _buildSectionCard(
      context,
      icon: LucideIcons.router,
      title: 'TUN 模式',
      subtitle: '虚拟网卡接管全局流量。启用通常要求核心以管理员权限运行。',
      children: [
        _SettingSwitchRow(
          label: '启用 TUN',
          value: tun.enable,
          enabled: connected,
          onChanged: (value) async {
            try {
              await state.setTunEnabled(value);
            } on ClashApiException catch (error) {
              if (context.mounted) {
                nexusToast(
                  context,
                  'TUN 切换失败：${error.message}',
                  isError: true,
                );
              }
            }
          },
        ),
        const SizedBox(height: NexusSpacing.sm),
        Row(
          children: [
            SizedBox(
              width: 120,
              child: Text('协议栈', style: NexusTypography.bodyMd),
            ),
            for (final stack in ['system', 'gvisor', 'mixed']) ...[
              _SettingsChip(
                label: stack,
                selected: tun.stack == stack,
                onTap: connected
                    ? () => state.applyTunSettings(
                        tun.copyWith(stack: stack),
                      )
                    : null,
              ),
              const SizedBox(width: NexusSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NexusInput(
                controller: _tunDeviceController,
                labelText: '网卡名称（可选）',
                hintText: 'Meta',
                onChanged: (_) => _userEditedTun = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.md),
            Expanded(
              flex: 2,
              child: NexusInput(
                controller: _tunDnsHijackController,
                labelText: 'DNS 劫持（逗号分隔）',
                hintText: 'any:53',
                onChanged: (_) => _userEditedTun = true,
              ),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        NexusButton(
          label: '应用 TUN 设置',
          icon: LucideIcons.check,
          isLoading: _applyingTun,
          onPressed: connected && !_applyingTun ? () => _applyTun(context) : null,
        ),
      ],
    );
  }

  /// DNS override, ported from FlClash's `views/config/dns.dart` +
  /// `overrideDns`: the external controller cannot hot-patch DNS, so the
  /// override is merged into the profile YAML on every activation.
  Widget _buildDnsCard(BuildContext context, ClashState state) {
    final current = state.runningConfig.value?.dns;
    final overrideEnabled = state.dnsOverrideEnabled.value;
    final override = state.dnsOverride.value;

    final summary = overrideEnabled
        ? '覆写已开启 · ${override?.nameserver.length ?? 0} 个 nameserver · '
              '${override?.enhancedMode ?? '-'}'
        : (current == null
              ? '未读取到核心 DNS 配置'
              : '${current.enable ? '启用' : '停用'} · ${current.enhancedMode} · '
                    '${current.nameserver.length} 个 nameserver');

    return _buildSectionCard(
      context,
      icon: LucideIcons.globe,
      title: 'DNS',
      subtitle: summary,
      children: [
        _SettingSwitchRow(
          label: '覆写 DNS',
          subtitle: '应用订阅时将下面的 DNS 配置合并进配置文件',
          value: overrideEnabled,
          onChanged: (value) => state.setDnsOverrideEnabled(value),
        ),
        const SizedBox(height: NexusSpacing.sm),
        Row(
          children: [
            NexusButton(
              label: overrideEnabled ? '编辑覆写' : '配置默认覆写',
              icon: LucideIcons.penLine,
              variant: NexusButtonVariant.tonal,
              onPressed: () => _showDnsDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showDnsDialog(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => const _DnsOverrideDialog(),
      ),
    );
  }

  /// Windows system proxy, ported from FlClash's network settings.
  Widget _buildSystemProxyCard(BuildContext context, ClashState state) {
    final supported = ClashSystemProxyService.instance.isSupported;

    return _buildSectionCard(
      context,
      icon: LucideIcons.monitorSmartphone,
      title: '系统代理',
      subtitle: supported
          ? '将系统 HTTP 代理指向核心的入站端口（写入 WinINET 设置）。'
          : '当前平台不支持设置系统代理。',
      children: [
        if (supported) ...[
          _SettingSwitchRow(
            label: '启用系统代理',
            subtitle:
                '当前入站端口：${state.runningConfig.value?.inboundPort ?? '-'}',
            value: state.systemProxyEnabled.value,
            busy: state.systemProxyBusy.value,
            onChanged: (value) async {
              try {
                await state.setSystemProxy(value);
              } on ClashSystemProxyException catch (error) {
                if (context.mounted) {
                  nexusToast(context, error.message, isError: true);
                }
              }
            },
          ),
          const SizedBox(height: NexusSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: NexusInput(
                  controller: _bypassController,
                  labelText: '绕过列表（分号分隔）',
                  hintText: ClashSystemProxyService.defaultBypass,
                  onChanged: (_) => _userEditedBypass = true,
                ),
              ),
              const SizedBox(width: NexusSpacing.md),
              NexusButton(
                label: '保存绕过列表',
                icon: LucideIcons.check,
                variant: NexusButtonVariant.tonal,
                onPressed: () async {
                  await state.setSystemProxyBypass(_bypassController.text);
                  if (context.mounted) {
                    nexusToast(context, '绕过列表已保存（下次启用时生效）');
                  }
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// App behaviors, ported from FlClash's application settings.
  Widget _buildBehaviorCard(BuildContext context, ClashState state) {
    return _buildSectionCard(
      context,
      icon: LucideIcons.mousePointerClick,
      title: '应用行为',
      children: [
        _SettingSwitchRow(
          label: '切换节点时断开连接',
          subtitle: '切换代理节点后重置现有连接（让新规则立即生效）',
          value: state.closeConnectionsOnSwitch.value,
          onChanged: (value) => state.setCloseConnectionsOnSwitch(value),
        ),
        const SizedBox(height: NexusSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: NexusInput(
                controller: _testUrlController,
                labelText: '延迟测试 URL',
                hintText: ClashApiService.defaultTestUrl,
                onChanged: (_) => _userEditedTestUrl = true,
              ),
            ),
            const SizedBox(width: NexusSpacing.md),
            NexusButton(
              label: '保存',
              icon: LucideIcons.check,
              variant: NexusButtonVariant.tonal,
              onPressed: () async {
                await state.setTestUrl(_testUrlController.text);
                if (context.mounted) {
                  nexusToast(context, '测速 URL 已保存');
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  /// Backup & restore, ported from FlClash's local file backup (endpoints,
  /// subscriptions, overwrites and UI settings in one JSON file).
  Widget _buildBackupCard(BuildContext context) {
    return _buildSectionCard(
      context,
      icon: LucideIcons.databaseBackup,
      title: '备份与恢复',
      subtitle: '备份包含核心端点、全部订阅（含规则覆写与节点选择）和界面设置。',
      children: [
        Row(
          children: [
            NexusButton(
              label: '导出备份',
              icon: LucideIcons.fileDown,
              onPressed: () => _exportBackup(context),
            ),
            const SizedBox(width: NexusSpacing.sm),
            NexusButton(
              label: '从文件恢复',
              icon: LucideIcons.fileUp,
              variant: NexusButtonVariant.outlined,
              onPressed: () => _importBackup(context),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRuntimeCard(BuildContext context, ClashState state) {
    final version = state.version.value;
    final config = state.runningConfig.value;
    final connected = state.status.value == ClashStatus.connected;

    return _buildSectionCard(
      context,
      icon: LucideIcons.info,
      title: '运行时信息',
      children: [
        Row(
          children: [
            const Spacer(),
            SecondaryBadge(child: Text(connected ? '已连接' : '未连接')),
          ],
        ),
        _RuntimeRow(label: '核心版本', value: version?.version ?? '-'),
        _RuntimeRow(label: '核心类型', value: version?.meta == true ? 'mihomo' : 'clash'),
        _RuntimeRow(label: '出站模式', value: config?.mode.label ?? '-'),
        _RuntimeRow(label: '入站端口', value: config?.inboundPort ?? '-'),
        _RuntimeRow(label: 'TUN', value: config?.tun?.enable == true ? '开' : '关'),
        _RuntimeRow(
          label: '允许局域网',
          value: config == null ? '-' : (config.allowLan ? '开' : '关'),
        ),
        _RuntimeRow(label: '规则数量', value: '${state.ruleCount.value}'),
        _RuntimeRow(
          label: '活动连接',
          value: '${state.connections.value.length}',
        ),
        _RuntimeRow(
          label: '核心内存',
          value: state.memory.value > 0
              ? formatClashBytes(state.memory.value)
              : '-',
        ),
      ],
    );
  }

  Widget _buildAboutCard(BuildContext context) {
    return _buildSectionCard(
      context,
      icon: LucideIcons.shieldCheck,
      title: '关于',
      children: [
        Text(
          'Clash 控制台的核心功能（代理组与节点管理、延迟测速、订阅管理与规则覆写、'
          '连接 / 请求 / 日志 / 规则视图、流量与内存监控、TUN 与系统代理、'
          '配置热更新、备份恢复）移植自开源项目 FlClash。'
          '本应用不内置代理核心，需要系统中已运行并开启 External Controller '
          '的 Clash / mihomo 兼容核心。',
          style: NexusTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _RuntimeRow extends StatelessWidget {
  const _RuntimeRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: NexusTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + switch row used across the settings cards.
class _SettingSwitchRow extends StatelessWidget {
  const _SettingSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    this.busy = false,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: NexusTypography.bodyMd),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(size: 12),
          )
        else
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
          ),
      ],
    );
  }
}

/// Selectable option chip used for enum-ish settings.
class _SettingsChip extends StatelessWidget {
  const _SettingsChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm + 2,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.card,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.border,
            ),
          ),
          child: Text(
            label,
            style: NexusTypography.labelMd.copyWith(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.mutedForeground,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// DNS override editor, ported from FlClash's DNS config view. Lists accept
/// one entry per line.
class _DnsOverrideDialog extends StatefulWidget {
  const _DnsOverrideDialog();

  @override
  State<_DnsOverrideDialog> createState() => _DnsOverrideDialogState();
}

class _DnsOverrideDialogState extends State<_DnsOverrideDialog> {
  late bool _enable;
  late final TextEditingController _listenController;
  late final TextEditingController _rangeController;
  late final TextEditingController _filterController;
  late final TextEditingController _defaultController;
  late final TextEditingController _nameserverController;
  late final TextEditingController _fallbackController;
  late String _enhancedMode;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final current =
        ClashState.instance.dnsOverride.value ??
        ClashDnsSettings.defaultOverride();
    _enable = current.enable;
    _listenController = TextEditingController(text: current.listen);
    _rangeController = TextEditingController(text: current.fakeIpRange);
    _filterController = TextEditingController(
      text: current.fakeIpFilter.join('\n'),
    );
    _defaultController = TextEditingController(
      text: current.defaultNameserver.join('\n'),
    );
    _nameserverController = TextEditingController(
      text: current.nameserver.join('\n'),
    );
    _fallbackController = TextEditingController(
      text: current.fallback.join('\n'),
    );
    _enhancedMode = current.enhancedMode;
  }

  @override
  void dispose() {
    _listenController.dispose();
    _rangeController.dispose();
    _filterController.dispose();
    _defaultController.dispose();
    _nameserverController.dispose();
    _fallbackController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    List<String> lines(TextEditingController controller) => controller.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    setState(() => _saving = true);
    await ClashState.instance.setDnsOverride(
      ClashDnsSettings(
        enable: _enable,
        listen: _listenController.text.trim(),
        enhancedMode: _enhancedMode,
        fakeIpRange: _rangeController.text.trim(),
        fakeIpFilter: lines(_filterController),
        defaultNameserver: lines(_defaultController),
        nameserver: lines(_nameserverController),
        fallback: lines(_fallbackController),
      ),
    );
    if (mounted) closeOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('DNS 覆写', style: NexusTypography.headlineSm),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('启用 DNS 模块', style: NexusTypography.bodyMd),
                  ),
                  Switch(
                    value: _enable,
                    onChanged: (value) => setState(() => _enable = value),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.sm),
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text('解析模式', style: NexusTypography.bodyMd),
                  ),
                  for (final mode in ['fake-ip', 'redir-host']) ...[
                    _SettingsChip(
                      label: mode,
                      selected: _enhancedMode == mode,
                      onTap: () => setState(() => _enhancedMode = mode),
                    ),
                    const SizedBox(width: NexusSpacing.xs),
                  ],
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: NexusInput(
                      controller: _listenController,
                      labelText: '监听地址（可选）',
                      hintText: '0.0.0.0:1053',
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(
                    child: NexusInput(
                      controller: _rangeController,
                      labelText: 'Fake-IP 网段',
                      hintText: '198.18.0.1/16',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              _MultilineField(
                controller: _defaultController,
                label: '默认 nameserver（每行一个，用于解析 DoH 域名）',
              ),
              const SizedBox(height: NexusSpacing.md),
              _MultilineField(
                controller: _nameserverController,
                label: 'nameserver（每行一个）',
              ),
              const SizedBox(height: NexusSpacing.md),
              _MultilineField(
                controller: _fallbackController,
                label: 'fallback（每行一个，可选）',
              ),
              const SizedBox(height: NexusSpacing.md),
              _MultilineField(
                controller: _filterController,
                label: 'Fake-IP 过滤（每行一个，可选）',
              ),
              const SizedBox(height: NexusSpacing.sm),
              Text(
                '保存后在下一次"应用订阅"时合并进配置文件。',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        Button.text(
          onPressed: _saving ? null : () => closeOverlay(context),
          child: const Text('取消'),
        ),
        Button.primary(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(size: 12),
                )
              : const Text('保存'),
        ),
      ],
    );
  }
}

class _MultilineField extends StatelessWidget {
  const _MultilineField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NexusTypography.labelMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: NexusSpacing.xs),
        TextField(
          controller: controller,
          maxLines: 3,
          style: NexusTypography.labelMd.copyWith(fontFamily: 'Consolas'),
        ),
      ],
    );
  }
}
