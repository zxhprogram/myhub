import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException;
import '../../../data/services/clash_overwrite_service.dart';
import '../../../data/services/clash_subscription_service.dart'
    show ClashSubscriptionException;
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';
import '../../components/nexus_input.dart';
import '../../components/nexus_toast.dart';

/// Subscription manager, ported from FlClash's profiles view: import from a
/// subscription URL or a local YAML file, inspect the traffic quota, edit the
/// profile metadata (auto-update), preview / overwrite the rules, push the
/// config to the running core and refresh (single / all) stored profiles.
class ClashProfilesView extends StatelessWidget {
  const ClashProfilesView({super.key, this.onOpenProxies});

  /// Jumps to the proxies view (passed by the page shell).
  final VoidCallback? onOpenProxies;

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      final items = state.profiles.value;

      if (items.isEmpty) {
        return NexusEmptyState(
          icon: LucideIcons.cloudDownload,
          title: '暂无订阅',
          subtitle: '导入机场订阅链接或本地配置文件，应用后即可在代理页选择节点运行。',
          action: NexusButton(
            label: '导入订阅',
            icon: LucideIcons.plus,
            onPressed: () => _showAddDialog(context),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.sm),
              itemBuilder: (context, index) =>
                  _ProfileCard(profile: items[index], onOpenProxies: onOpenProxies),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('订阅配置', style: NexusTypography.headlineSm),
              const SizedBox(height: 2),
              Text(
                '导入订阅链接后点击"应用"，配置会推送到运行中的核心。'
                '规则覆写与 DNS 覆写在应用时自动合并。',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        NexusButton(
          label: '全部更新',
          icon: LucideIcons.refreshCw,
          variant: NexusButtonVariant.tonal,
          onPressed: () => ClashState.instance.updateAllProfiles(),
        ),
        const SizedBox(width: NexusSpacing.sm),
        NexusButton(
          label: '导入文件',
          icon: LucideIcons.fileUp,
          variant: NexusButtonVariant.outlined,
          onPressed: () => _importFromFile(context),
        ),
        const SizedBox(width: NexusSpacing.sm),
        NexusButton(
          label: '导入订阅',
          icon: LucideIcons.plus,
          onPressed: () => _showAddDialog(context),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => const _AddSubscriptionDialog(),
      ),
    );
  }

  /// Local YAML import (FlClash `addProfileFromFile`).
  Future<void> _importFromFile(BuildContext context) async {
    const typeGroup = XTypeGroup(
      label: 'Clash 配置',
      extensions: ['yaml', 'yml', 'txt'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;
    try {
      final content = await file.readAsString();
      final name = file.name.split('.').first;
      await ClashState.instance.addLocalProfile(
        config: content,
        label: name,
      );
      if (context.mounted) {
        nexusToast(context, '已导入本地配置「$name」');
      }
    } on ClashSubscriptionException catch (error) {
      if (context.mounted) {
        nexusToast(context, error.message, isError: true);
      }
    } catch (error) {
      if (context.mounted) {
        nexusToast(context, '导入失败：$error', isError: true);
      }
    }
  }
}

/// One subscription card: label, URL, traffic quota (FlClash's
/// `SubscriptionInfoView`), auto-update state, last update time and the
/// apply / update / edit / preview / overwrite / delete actions.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, this.onOpenProxies});

  final ClashProfile profile;
  final VoidCallback? onOpenProxies;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final active = state.activeProfileId.value == profile.id;
      final busy = state.busyProfileIds.value.contains(profile.id);

      return NexusCard(
        highlight: active,
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.label.isEmpty ? profile.url : profile.label,
                    style: NexusTypography.headlineSm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: active ? colorScheme.primary : colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!profile.isFromUrl) ...[
                  SecondaryBadge(child: Text('本地')),
                  const SizedBox(width: NexusSpacing.sm),
                ],
                if (profile.autoUpdate) ...[
                  NexusBadge(
                    label: '自动 ${_intervalLabel(profile)}',
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                    foregroundColor: colorScheme.primary,
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                ],
                if (active) ...[
                  PrimaryBadge(child: Text('运行中')),
                  const SizedBox(width: NexusSpacing.sm),
                ],
                SizedBox(
                  width: 18,
                  height: 18,
                  child: busy
                      ? const CircularProgressIndicator(size: 14)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              profile.isFromUrl
                  ? profile.url
                  : '本地导入 · ${DateFormat('yyyy-MM-dd').format(profile.addedAt)}',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_hasSubscriptionInfo) ...[
              const SizedBox(height: NexusSpacing.md),
              _SubscriptionInfoBar(info: profile.subscriptionInfo!),
            ],
            if (profile.addedRules.isNotEmpty ||
                profile.disabledRules.isNotEmpty) ...[
              const SizedBox(height: NexusSpacing.sm),
              Text(
                '规则覆写：附加 ${profile.addedRules.length} 条 / 禁用 ${profile.disabledRules.length} 条',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '上次更新：'
                    '${profile.lastUpdateAt != null ? _formatTime(profile.lastUpdateAt!) : '从未'}',
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
                _buildActions(context, state, active),
              ],
            ),
          ],
        ),
      );
    });
  }

  static String _intervalLabel(ClashProfile profile) {
    final minutes = profile.autoUpdateIntervalMinutes;
    if (minutes >= 1440 && minutes % 1440 == 0) {
      return '${minutes ~/ 1440} 天';
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      return '${minutes ~/ 60} 小时';
    }
    return '$minutes 分钟';
  }

  bool get _hasSubscriptionInfo =>
      profile.subscriptionInfo != null &&
      (profile.subscriptionInfo!.hasQuota ||
          profile.subscriptionInfo!.expireDate != null);

  Widget _buildActions(
    BuildContext context,
    ClashState state,
    bool active,
  ) {
    return Row(
      children: [
        if (!active)
          NexusButton(
            label: '应用',
            icon: LucideIcons.play,
            onPressed: () => _apply(context, state),
          )
        else
          NexusButton(
            label: '已应用',
            icon: LucideIcons.circleCheck,
            variant: NexusButtonVariant.outlined,
            onPressed: onOpenProxies,
          ),
        const SizedBox(width: NexusSpacing.sm),
        if (profile.isFromUrl)
          NexusButton(
            label: '更新',
            icon: LucideIcons.refreshCw,
            variant: NexusButtonVariant.tonal,
            onPressed: () => state.updateProfile(profile.id),
          ),
        const SizedBox(width: NexusSpacing.sm),
        _MenuIconButton(
          icon: LucideIcons.penLine,
          tooltip: '编辑',
          onPressed: () => _showEditDialog(context),
        ),
        const SizedBox(width: NexusSpacing.xs),
        _MenuIconButton(
          icon: LucideIcons.eye,
          tooltip: '预览配置',
          onPressed: () => _showPreviewDialog(context),
        ),
        const SizedBox(width: NexusSpacing.xs),
        _MenuIconButton(
          icon: LucideIcons.listFilter,
          tooltip: '规则覆写',
          onPressed: () => _showOverwriteDialog(context),
        ),
        const SizedBox(width: NexusSpacing.xs),
        _DeleteButton(profileId: profile.id, profileLabel: profile.label),
      ],
    );
  }

  Future<void> _apply(BuildContext context, ClashState state) async {
    try {
      await state.activateProfile(profile.id);
      if (context.mounted) {
        nexusToast(context, '已应用「${profile.label}」');
      }
    } on ClashApiException catch (error) {
      if (context.mounted) {
        showOverlay(
          context,
          DialogConfiguration(
            barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
            builder: (dialogContext) => AlertDialog(
              title: Text('应用失败', style: NexusTypography.headlineSm),
              content: Text(
                error.message,
                style: NexusTypography.bodyMd,
              ),
              actions: [
                Button.primary(
                  onPressed: () => closeOverlay(dialogContext),
                  child: const Text('知道了'),
                ),
              ],
            ),
          ),
        );
      }
    }
  }

  void _showEditDialog(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => _EditProfileDialog(profile: profile),
      ),
    );
  }

  void _showPreviewDialog(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => _PreviewConfigDialog(profile: profile),
      ),
    );
  }

  void _showOverwriteDialog(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => _OverwriteRulesDialog(profile: profile),
      ),
    );
  }

  String _formatTime(DateTime time) => DateFormat('yyyy-MM-dd HH:mm').format(time);
}

/// Icon button of the profile card action row.
class _MenuIconButton extends StatelessWidget {
  const _MenuIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colorScheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.border),
          ),
          child: Icon(icon, size: 15, color: colorScheme.mutedForeground),
        ),
      ),
    );
  }
}

/// Quota progress bar + expiry, ported from FlClash's `SubscriptionInfoView`
/// (hidden entirely when the server reports no `subscription-userinfo`).
class _SubscriptionInfoBar extends StatelessWidget {
  const _SubscriptionInfoBar({required this.info});

  final ClashSubscriptionInfo info;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fraction = info.usedFraction ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Progress(
          progress: fraction,
          color: fraction > 0.9 ? colorScheme.destructive : colorScheme.primary,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                info.hasQuota
                    ? '已用 ${formatClashBytes(info.used)} / ${formatClashBytes(info.total)}'
                    : '',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ),
            if (info.expireDate != null)
              Text(
                info.isExpired ? '已过期' : '${DateFormat('yyyy-MM-dd').format(info.expireDate!)} 到期',
                style: NexusTypography.labelMd.copyWith(
                  color: info.isExpired
                      ? colorScheme.destructive
                      : colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Icon button with a confirm dialog before deleting a subscription.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.profileId, required this.profileLabel});

  final String profileId;
  final String profileLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _confirm(context),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: colorScheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.border),
          ),
          child: Icon(
            LucideIcons.trash2,
            size: 15,
            color: colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('删除订阅？', style: NexusTypography.headlineSm),
            content: Text(
              '确定要删除 "$profileLabel" 吗？核心将继续使用当前配置运行。',
              style: NexusTypography.bodyMd,
            ),
            actions: [
              Button.text(
                onPressed: () => closeOverlay<bool>(dialogContext, false),
                child: const Text('取消'),
              ),
              Button.destructive(
                onPressed: () => closeOverlay<bool>(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          );
        },
      ),
    ).future;
    if (confirmed == true) {
      await ClashState.instance.deleteProfile(profileId);
    }
  }
}

/// URL import dialog, ported from FlClash's "import from URL" input dialog
/// with an optional custom display name added.
class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog();

  @override
  State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final _urlController = TextEditingController();
  final _labelController = TextEditingController();

  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _urlController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  bool _isValidUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (!_isValidUrl(url)) {
      setState(() => _error = '请输入有效的 http(s) 订阅链接');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ClashState.instance.addProfile(
        url: url,
        label: _labelController.text,
      );
      if (mounted) closeOverlay(context);
    } on ClashSubscriptionException catch (error) {
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } on ClashApiException catch (error) {
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (error) {
      setState(() {
        _loading = false;
        _error = '导入失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('导入订阅', style: NexusTypography.headlineSm),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NexusInput(
              controller: _urlController,
              labelText: '订阅链接',
              hintText: 'https://example.com/api/v1/client/subscribe?token=…',
              autofocus: true,
              onSubmitted: (_) => _loading ? null : _submit(),
            ),
            const SizedBox(height: NexusSpacing.md),
            NexusInput(
              controller: _labelController,
              labelText: '名称（可选）',
              hintText: '默认使用订阅返回的文件名',
            ),
            if (_error != null) ...[
              const SizedBox(height: NexusSpacing.sm),
              Text(
                _error!,
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.destructive,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Button.text(
          onPressed: _loading ? null : () => closeOverlay(context),
          child: const Text('取消'),
        ),
        Button.primary(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(size: 12),
                )
              : const Text('导入'),
        ),
      ],
    );
  }
}

/// Profile metadata editor, ported from FlClash's profile edit sheet: label,
/// subscription URL and the auto-update schedule.
class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({required this.profile});

  final ClashProfile profile;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  late final TextEditingController _intervalController;

  late bool _autoUpdate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.profile.label);
    _urlController = TextEditingController(text: widget.profile.url);
    _intervalController = TextEditingController(
      text: '${widget.profile.autoUpdateIntervalMinutes}',
    );
    _autoUpdate = widget.profile.autoUpdate;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty) {
        setState(() => _error = '订阅链接格式无效');
        return;
      }
    }
    final interval = int.tryParse(_intervalController.text.trim());
    if (interval == null || interval < 0) {
      setState(() => _error = '自动更新间隔必须是分钟数（0 为关闭）');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    await ClashState.instance.updateProfileMeta(
      widget.profile.id,
      label: _labelController.text,
      url: url,
      autoUpdate: _autoUpdate,
      autoUpdateIntervalMinutes: interval,
    );
    if (mounted) closeOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text('编辑订阅', style: NexusTypography.headlineSm),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NexusInput(
              controller: _labelController,
              labelText: '名称',
              hintText: '订阅显示名称',
            ),
            const SizedBox(height: NexusSpacing.md),
            NexusInput(
              controller: _urlController,
              labelText: widget.profile.isFromUrl ? '订阅链接' : '订阅链接（补充后可在线更新）',
              hintText: 'https://example.com/subscribe?token=…',
            ),
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '自动更新订阅',
                    style: NexusTypography.bodyMd,
                  ),
                ),
                Switch(
                  value: _autoUpdate,
                  onChanged: (value) => setState(() => _autoUpdate = value),
                ),
              ],
            ),
            if (_autoUpdate) ...[
              const SizedBox(height: NexusSpacing.sm),
              NexusInput(
                controller: _intervalController,
                labelText: '更新间隔（分钟）',
                hintText: '360',
                keyboardType: TextInputType.number,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: NexusSpacing.sm),
              Text(
                _error!,
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.destructive,
                ),
              ),
            ],
          ],
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

/// Shows the final config that would be pushed to the core (stored YAML +
/// rule overwrite + DNS override), FlClash's profile preview.
class _PreviewConfigDialog extends StatelessWidget {
  const _PreviewConfigDialog({required this.profile});

  final ClashProfile profile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final config = ClashState.instance.finalConfigOf(profile);

    return AlertDialog(
      title: Text('预览「${profile.label}」', style: NexusTypography.headlineSm),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 520),
        child: Container(
          width: 640,
          padding: const EdgeInsets.all(NexusSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.muted.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.border),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              config,
              style: NexusTypography.labelMd.copyWith(
                fontFamily: 'Consolas',
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
      actions: [
        Button.primary(
          onPressed: () => closeOverlay(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

/// Rule overwrite editor, ported from FlClash's standard overwrite scene:
/// "added rules" (free-form lines prepended to the profile rules) and
/// "disabled rules" (checkbox selection of the profile's own rules).
class _OverwriteRulesDialog extends StatefulWidget {
  const _OverwriteRulesDialog({required this.profile});

  final ClashProfile profile;

  @override
  State<_OverwriteRulesDialog> createState() => _OverwriteRulesDialogState();
}

class _OverwriteRulesDialogState extends State<_OverwriteRulesDialog> {
  late List<String> _addedRules;
  late Set<String> _disabledRules;
  late final List<String> _profileRules;

  final _addController = TextEditingController();
  final _searchController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _addedRules = [...widget.profile.addedRules];
    _disabledRules = {...widget.profile.disabledRules};
    _profileRules = ClashConfigOverwriter.rulesOf(widget.profile.config);
  }

  @override
  void dispose() {
    _addController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ClashState.instance.setProfileOverwrite(
      widget.profile.id,
      addedRules: _addedRules,
      disabledRules: _disabledRules.toList(),
    );
    if (mounted) closeOverlay(context);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final query = _searchController.text.toLowerCase().trim();
    final filteredRules = query.isEmpty
        ? _profileRules
        : _profileRules
              .where((rule) => rule.toLowerCase().contains(query))
              .toList();

    return AlertDialog(
      title: Text('规则覆写「${widget.profile.label}」', style: NexusTypography.headlineSm),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '附加规则（优先于订阅规则）',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addController,
                    hintText: 'DOMAIN-SUFFIX,example.com,DIRECT',
                    onSubmitted: (value) => _addRule(value),
                  ),
                ),
                const SizedBox(width: NexusSpacing.sm),
                NexusButton(
                  label: '添加',
                  icon: LucideIcons.plus,
                  variant: NexusButtonVariant.tonal,
                  onPressed: () => _addRule(_addController.text),
                ),
              ],
            ),
            if (_addedRules.isNotEmpty) ...[
              const SizedBox(height: NexusSpacing.sm),
              for (var i = 0; i < _addedRules.length; i++)
                _RuleLine(
                  rule: _addedRules[i],
                  onRemove: () => setState(() => _addedRules.removeAt(i)),
                ),
            ],
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '禁用订阅规则（勾选后应用时移除）',
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _searchController,
                    hintText: '搜索规则…',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.sm),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.border),
                ),
                child: _profileRules.isEmpty
                    ? Center(
                        child: Text(
                          '订阅中没有可禁用的规则。',
                          style: NexusTypography.labelMd.copyWith(
                            color: colorScheme.mutedForeground,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: NexusSpacing.xs,
                        ),
                        itemCount: filteredRules.length,
                        itemBuilder: (context, index) {
                          final rule = filteredRules[index];
                          final checked = _disabledRules.contains(rule);
                          return GestureDetector(
                            onTap: () => setState(() {
                              checked
                                  ? _disabledRules.remove(rule)
                                  : _disabledRules.add(rule);
                            }),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: NexusSpacing.sm,
                                vertical: 1,
                              ),
                            child: Row(
                              children: [
                                Checkbox(
                                  state: checked
                                      ? CheckboxState.checked
                                      : CheckboxState.unchecked,
                                  onChanged: (state) => setState(() {
                                    state == CheckboxState.checked
                                        ? _disabledRules.add(rule)
                                        : _disabledRules.remove(rule);
                                  }),
                                ),
                                  Expanded(
                                    child: Text(
                                      rule,
                                      style: NexusTypography.labelMd,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
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
              : const Text('保存并应用'),
        ),
      ],
    );
  }

  void _addRule(String value) {
    final rule = value.trim();
    if (rule.isEmpty) return;
    if (_addedRules.contains(rule)) return;
    setState(() => _addedRules.add(rule));
    _addController.clear();
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.rule, required this.onRemove});

  final String rule;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                rule,
                style: NexusTypography.labelMd,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onRemove,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(
                  LucideIcons.x,
                  size: 14,
                  color: colorScheme.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
