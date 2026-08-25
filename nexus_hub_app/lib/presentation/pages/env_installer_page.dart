import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/services/dev_env_installer_service.dart';
import '../../theme/density.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/app_squircle_icon.dart';
import '../components/nexus_button.dart';
import '../components/nexus_toast.dart';

/// Amber used for "not installed" hints (no warning token in ColorScheme).
const Color _warningColor = Color(0xFFF59E0B);

/// 开发环境安装助手 — 选择语言环境与版本，确认后自动安装并配置环境变量。
///
/// 实际的检测 / winget 安装 / 环境变量配置由 [DevEnvInstallerService] 完成，
/// 本页面负责环境列表、版本选择、确认对话框与实时安装日志展示。
class EnvInstallerPage extends StatefulWidget {
  const EnvInstallerPage({super.key});

  @override
  State<EnvInstallerPage> createState() => _EnvInstallerPageState();
}

class _EnvInstallerPageState extends State<EnvInstallerPage> {
  final DevEnvInstallerService _service = DevEnvInstallerService.instance;
  final ScrollController _logScrollController = ScrollController();

  /// Per-environment detection results keyed by [LanguageEnv.id].
  final Map<String, EnvDetection> _detections = {};

  String? _selectedEnvId;
  String? _selectedVersionLabel;

  bool _installing = false;
  bool _installFailed = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _selectedEnvId = DevEnvInstallerService.environments.first.id;
    _refreshDetections();
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  LanguageEnv? get _selectedEnv {
    for (final env in DevEnvInstallerService.environments) {
      if (env.id == _selectedEnvId) return env;
    }
    return null;
  }

  Future<void> _refreshDetections() async {
    for (final env in DevEnvInstallerService.environments) {
      setState(() {
        _detections[env.id] = const EnvDetection(
          status: EnvDetectStatus.checking,
        );
      });
      final detection = await _service.detect(env);
      if (!mounted) return;
      setState(() => _detections[env.id] = detection);
    }
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      if (_logs.isNotEmpty && _logs.last.startsWith('下载进度') &&
          line.startsWith('下载进度')) {
        _logs[_logs.length - 1] = line;
      } else {
        _logs.add(line);
      }
    });
    // Keep the newest log lines visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) return;
      _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
    });
  }

  Future<void> _confirmAndInstall(LanguageEnv env, EnvVersion version) async {
    final confirmed = await showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) => AlertDialog(
          title: Text('安装 ${env.name} 环境'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('版本：${version.label}'),
              const SizedBox(height: 4),
              Text('组件：${env.components}'),
              const SizedBox(height: 12),
              Text(
                '将通过 winget（或官方压缩包）下载并安装所选版本，'
                '随后自动配置 JAVA_HOME、GOPATH、PATH 等用户环境变量。'
                '安装过程可能需要几分钟，请保持网络畅通。',
                style: NexusTypography.labelSm.copyWith(
                  color: Theme.of(ctx).colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          actions: [
            Button.text(
              onPressed: () => closeOverlay<bool>(ctx, false),
              child: const Text('取消'),
            ),
            Button.primary(
              onPressed: () => closeOverlay<bool>(ctx, true),
              child: const Text('开始安装'),
            ),
          ],
        ),
      ),
    ).future;

    if (confirmed != true || !mounted) return;
    await _startInstall(env, version);
  }

  Future<void> _startInstall(LanguageEnv env, EnvVersion version) async {
    setState(() {
      _installing = true;
      _installFailed = false;
      _logs.clear();
    });
    try {
      await _service.install(env: env, version: version, onLog: _appendLog);
      if (!mounted) return;
      nexusToast(context, '${env.name} 环境安装完成');
    } catch (e) {
      if (!mounted) return;
      setState(() => _installFailed = true);
      _appendLog('安装失败：$e');
      nexusToast(context, '${env.name} 环境安装失败', isError: true);
    } finally {
      if (mounted) {
        setState(() => _installing = false);
      }
      await _refreshDetections();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.card,
      child: Column(
        children: [
          _buildToolbar(context),
          if (!_service.isSupported)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.lg,
                vertical: NexusSpacing.sm,
              ),
              color: _warningColor.withValues(alpha: 0.12),
              child: Text(
                '当前平台不支持自动安装，环境安装助手仅支持 Windows。',
                style: NexusTypography.labelSm.copyWith(
                  color: _warningColor,
                ),
              ),
            ),
          Divider(height: 1, color: colorScheme.border),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEnvList(context),
                VerticalDivider(width: 1, color: colorScheme.border),
                Expanded(child: _buildDetailPane(context)),
              ],
            ),
          ),
          if (_logs.isNotEmpty) ...[
            Divider(height: 1, color: colorScheme.border),
            _buildLogConsole(context),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.lg,
        vertical: NexusSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(LucideIcons.packageOpen, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text('环境安装助手', style: NexusTypography.headlineSm),
          const Spacer(),
          NexusButton(
            label: '重新检测',
            icon: LucideIcons.refreshCw,
            variant: NexusButtonVariant.outlined,
            onPressed: _installing ? null : _refreshDetections,
          ),
        ],
      ),
    );
  }

  Widget _buildEnvList(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: ListView.builder(
        padding: const EdgeInsets.all(NexusSpacing.sm),
        itemCount: DevEnvInstallerService.environments.length,
        itemBuilder: (context, index) {
          final env = DevEnvInstallerService.environments[index];
          final selected = env.id == _selectedEnvId;
          final detection = _detections[env.id];
          final colors = _envColors(env.id);

          return Padding(
            padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
            child: GestureDetector(
              onTap: _installing
                  ? null
                  : () => setState(() {
                      _selectedEnvId = env.id;
                      _selectedVersionLabel = null;
                    }),
              child: Container(
                padding: const EdgeInsets.all(NexusSpacing.sm),
                decoration: BoxDecoration(
                  color: selected
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(NexusDensityController.cardRadius),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary.withValues(alpha: 0.5)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  children: [
                    AppSquircleIcon(
                      gradientStart: colors.$1,
                      gradientEnd: colors.$2,
                      size: 32,
                      child: Icon(_envIcon(env.id), size: 17),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(env.name, style: NexusTypography.bodyMd),
                    ),
                    _statusBadge(context, detection),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusBadge(BuildContext context, EnvDetection? detection) {
    final colorScheme = Theme.of(context).colorScheme;
    final (label, color) = switch (detection?.status) {
      EnvDetectStatus.installed => ('已装', const Color(0xFF30D158)),
      EnvDetectStatus.checking => ('检测中', colorScheme.mutedForeground),
      EnvDetectStatus.notInstalled => ('未安装', _warningColor),
      EnvDetectStatus.unknown => ('未知', colorScheme.mutedForeground),
      null => ('—', colorScheme.mutedForeground),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: NexusTypography.labelSm.copyWith(color: color),
      ),
    );
  }

  Widget _buildDetailPane(BuildContext context) {
    final env = _selectedEnv;
    if (env == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final detection = _detections[env.id];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(NexusSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(env.name, style: NexusTypography.headlineLg),
              const SizedBox(width: 12),
              if (detection?.status == EnvDetectStatus.installed)
                Text(
                  '当前已安装 v${detection!.version ?? '?'}',
                  style: NexusTypography.labelSm.copyWith(
                    color: const Color(0xFF30D158),
                  ),
                )
              else if (detection?.status == EnvDetectStatus.notInstalled)
                Text(
                  '未检测到安装',
                  style: NexusTypography.labelSm.copyWith(
                    color: _warningColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            env.description,
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: NexusSpacing.lg),
          Text('选择版本', style: NexusTypography.labelMd),
          const SizedBox(height: NexusSpacing.sm),
          ...env.versions.map((v) => _versionOption(context, env, v)),
          const SizedBox(height: NexusSpacing.lg),
          NexusButton(
            label: '安装此版本',
            icon: LucideIcons.download,
            isLoading: _installing,
            onPressed: (_installing || !_service.isSupported)
                ? null
                : () {
                    final version = _resolveSelectedVersion(env);
                    _confirmAndInstall(env, version);
                  },
          ),
          if (_installing) ...[
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '正在安装，请勿关闭窗口…',
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ] else if (_logs.isNotEmpty) ...[
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                Icon(
                  _installFailed ? LucideIcons.circleX : LucideIcons.circleCheck,
                  size: 15,
                  color: _installFailed
                      ? colorScheme.destructive
                      : const Color(0xFF30D158),
                ),
                const SizedBox(width: 8),
                Text(
                  _installFailed ? '安装失败，详见下方日志' : '最近一次任务已结束，详见下方日志',
                  style: NexusTypography.labelSm.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.ghost(
                  icon: const Icon(LucideIcons.copy, size: 14),
                  onPressed: _copyLogs,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _versionOption(BuildContext context, LanguageEnv env, EnvVersion v) {
    final colorScheme = Theme.of(context).colorScheme;
    final effective = _selectedVersionLabel ?? env.versions.first.label;
    final selected = v.label == effective;

    return GestureDetector(
      onTap: _installing
          ? null
          : () => setState(() => _selectedVersionLabel = v.label),
      child: Container(
        margin: const EdgeInsets.only(bottom: NexusSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                : colorScheme.border.withValues(alpha: 0.6),
          ),
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.06)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? LucideIcons.circleCheckBig
                  : LucideIcons.circle,
              size: 16,
              color: selected ? colorScheme.primary : colorScheme.mutedForeground,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(v.label, style: NexusTypography.bodyMd)),
            if (v.wingetId != null)
              Text(
                'winget',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              )
            else
              Icon(LucideIcons.globe, size: 13, color: colorScheme.mutedForeground),
          ],
        ),
      ),
    );
  }

  Widget _buildLogConsole(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    return Container(
      height: 180,
      width: double.infinity,
      color: isDark ? const Color(0xFF141414) : const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.sm,
      ),
      child: SingleChildScrollView(
        controller: _logScrollController,
        child: Text.rich(
          TextSpan(
            children: [
              for (final line in _logs)
                TextSpan(
                  text: '$line\n',
                  style: TextStyle(
                    fontFamily: 'Consolas, monospace',
                    fontSize: 11.5,
                    height: 1.45,
                    color: _logColor(line, isDark),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _logColor(String line, bool isDark) {
    if (line.startsWith('===')) return const Color(0xFF569CD6);
    if (line.startsWith('>')) return const Color(0xFFDCDCAA);
    if (line.contains('失败') ||
        line.contains('警告') ||
        line.startsWith('winget 退出码')) {
      return const Color(0xFFF48771);
    }
    if (line.contains('成功') || line.contains('完成')) {
      return const Color(0xFF6A9955);
    }
    return isDark ? const Color(0xFFCCCCCC) : const Color(0xFFD4D4D4);
  }

  EnvVersion _resolveSelectedVersion(LanguageEnv env) {
    final label = _selectedVersionLabel ?? env.versions.first.label;
    for (final v in env.versions) {
      if (v.label == label) return v;
    }
    return env.versions.first;
  }

  Future<void> _copyLogs() async {
    await Clipboard.setData(ClipboardData(text: _logs.join('\n')));
    if (!mounted) return;
    nexusToast(context, '已复制安装日志到剪贴板');
  }

  // ── Visual identity per environment ──────────────────────────────────────

  static (Color, Color) _envColors(String id) => switch (id) {
        'java' => (const Color(0xFFF89820), const Color(0xFF5382A1)),
        'go' => (const Color(0xFF00ACD7), const Color(0xFF00758F)),
        'rust' => (const Color(0xFFDEA584), const Color(0xFFB7410E)),
        'flutter' => (const Color(0xFF47C5FB), const Color(0xFF02569B)),
        'nodejs' => (const Color(0xFF8CC84B), const Color(0xFF43853D)),
        'python' => (const Color(0xFFFFD43B), const Color(0xFF3776AB)),
        _ => (const Color(0xFF9AA0A6), const Color(0xFF5F6368)),
      };

  static IconData _envIcon(String id) => switch (id) {
        'java' => LucideIcons.coffee,
        'go' => LucideIcons.box,
        'rust' => LucideIcons.settings2,
        'flutter' => LucideIcons.smartphone,
        'nodejs' => LucideIcons.hexagon,
        'python' => LucideIcons.codeXml,
        _ => LucideIcons.package,
      };
}
