import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_input.dart';

/// Settings screen: external controller endpoint (persisted like FlClash's
/// app settings) plus the runtime readout of the attached core.
class ClashSettingsView extends StatefulWidget {
  const ClashSettingsView({super.key});

  @override
  State<ClashSettingsView> createState() => _ClashSettingsViewState();
}

class _ClashSettingsViewState extends State<ClashSettingsView> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _secretController = TextEditingController();

  bool _userEdited = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _syncControllers();
    // The persisted endpoint loads asynchronously — refresh the fields once
    // it lands unless the user already started editing.
    ClashState.instance.init().then((_) {
      if (mounted && !_userEdited) {
        setState(_syncControllers);
      }
    });
  }

  void _syncControllers() {
    final state = ClashState.instance;
    _hostController.text = state.apiHost.value;
    _portController.text = '${state.apiPort.value}';
    _secretController.text = state.apiSecret.value;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _saveAndConnect() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final state = ClashState.instance;
    await state.updateEndpoint(
      host: _hostController.text.trim(),
      port: port,
      secret: _secretController.text.trim(),
    );
    await state.connect();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildEndpointCard(context),
          const SizedBox(height: NexusSpacing.md),
          _buildRuntimeCard(context),
          const SizedBox(height: NexusSpacing.md),
          _buildAboutCard(context),
        ],
      ),
    );
  }

  Widget _buildEndpointCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final portValid = () {
      final port = int.tryParse(_portController.text.trim());
      return port != null && port >= 1 && port <= 65535;
    }();

    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.server, size: 18, color: colorScheme.primary),
              const SizedBox(width: NexusSpacing.sm),
              Text('核心端点', style: NexusTypography.headlineSm),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Text(
            'Clash 控制台通过 External Controller API 访问运行中的核心，'
            '默认地址为 127.0.0.1:9090（即 mihomo / FlClash 核心的 '
            'external-controller 配置项）。',
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: NexusSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: NexusInput(
                  controller: _hostController,
                  labelText: '服务器地址',
                  hintText: '127.0.0.1',
                  onChanged: (_) => _userEdited = true,
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
                  onChanged: (_) => _userEdited = true,
                ),
              ),
              const SizedBox(width: NexusSpacing.md),
              Expanded(
                flex: 3,
                child: NexusInput(
                  controller: _secretController,
                  labelText: '访问密钥（可选）',
                  hintText: 'secret',
                  onChanged: (_) => _userEdited = true,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          NexusButton(
            label: '保存并连接',
            icon: LucideIcons.plug,
            isLoading: _saving,
            onPressed: portValid && !_saving ? _saveAndConnect : null,
          ),
        ],
      ),
    );
  }

  Widget _buildRuntimeCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final version = state.version.value;
      final config = state.runningConfig.value;
      final connected = state.status.value == ClashStatus.connected;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.info, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('运行时信息', style: NexusTypography.headlineSm),
                const Spacer(),
                SecondaryBadge(
                  child: Text(connected ? '已连接' : '未连接'),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            _RuntimeRow(label: '核心版本', value: version?.version ?? '-'),
            _RuntimeRow(label: '核心类型', value: version?.meta == true ? 'mihomo' : 'clash'),
            _RuntimeRow(label: '出站模式', value: config?.mode.label ?? '-'),
            _RuntimeRow(label: '入站端口', value: config?.inboundPort ?? '-'),
            _RuntimeRow(
              label: '允许局域网',
              value: config == null ? '-' : (config.allowLan ? '开' : '关'),
            ),
            _RuntimeRow(label: '规则数量', value: '${state.ruleCount.value}'),
            _RuntimeRow(
              label: '活动连接',
              value: '${state.connections.value.length}',
            ),
          ],
        ),
      );
    });
  }

  Widget _buildAboutCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, size: 18, color: colorScheme.primary),
              const SizedBox(width: NexusSpacing.sm),
              Text('关于', style: NexusTypography.headlineSm),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Text(
            'Clash 控制台的核心功能（代理组与节点管理、延迟测速、连接管理、'
            '实时日志、流量监控、模式切换）移植自开源项目 FlClash。'
            '本应用不内置代理核心，需要系统中已运行并开启 External Controller '
            '的 Clash / mihomo 兼容核心。',
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
              height: 1.6,
            ),
          ),
        ],
      ),
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
