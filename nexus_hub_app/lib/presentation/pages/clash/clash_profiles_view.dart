import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException;
import '../../../data/services/clash_subscription_service.dart'
    show ClashSubscriptionException;
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';
import '../../components/nexus_input.dart';

/// Subscription manager, ported from FlClash's profiles view: import a
/// subscription URL, inspect its traffic quota, push it to the running core
/// and refresh / delete stored profiles. After a profile is applied the
/// proxies view offers the group → node selection.
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
          subtitle: '导入机场订阅链接，应用后即可在代理页选择节点运行。',
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
                '导入订阅链接后点击"应用"，配置会推送到运行中的核心。',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
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
}

/// One subscription card: label, URL, traffic quota (FlClash's
/// `SubscriptionInfoView`), last update time and the apply / update / delete
/// actions.
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
              profile.url,
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
        NexusButton(
          label: '更新',
          icon: LucideIcons.refreshCw,
          variant: NexusButtonVariant.tonal,
          onPressed: () => state.updateProfile(profile.id),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _DeleteButton(profileId: profile.id, profileLabel: profile.label),
      ],
    );
  }

  Future<void> _apply(BuildContext context, ClashState state) async {
    try {
      await state.activateProfile(profile.id);
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

  String _formatTime(DateTime time) => DateFormat('yyyy-MM-dd HH:mm').format(time);
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
