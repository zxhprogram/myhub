import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException;
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';

/// Proxies screen, ported from FlClash's `ProxiesView`: group tabs, node
/// grid, node selection, per-node and per-group delay testing with FlClash's
/// delay coloring and "timeout last" ordering.
class ClashProxiesView extends StatefulWidget {
  const ClashProxiesView({super.key});

  @override
  State<ClashProxiesView> createState() => _ClashProxiesViewState();
}

class _ClashProxiesViewState extends State<ClashProxiesView> {
  final TextEditingController _searchController = TextEditingController();

  bool _sortByDelay = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Sort key ported from FlClash `DelayStateExt.priority`: measured delays
  /// first (ascending), untested in the middle, timeouts last.
  int _delayPriority(int delay) {
    if (delay > 0) return 0;
    if (delay == 0) return 1;
    return 2;
  }

  List<ClashProxy> _visibleNodes(
    ClashProxyGroup group,
    Map<String, int> delays,
  ) {
    final query = _searchController.text.toLowerCase().trim();
    var nodes = group.proxies.where((proxy) {
      return query.isEmpty ||
          proxy.name.toLowerCase().contains(query) ||
          proxy.type.toLowerCase().contains(query);
    }).toList();
    if (_sortByDelay) {
      int delayOf(ClashProxy proxy) =>
          delays[proxy.name] ?? proxy.latestDelay;
      nodes.sort((a, b) {
        final priorityA = _delayPriority(delayOf(a));
        final priorityB = _delayPriority(delayOf(b));
        if (priorityA != priorityB) return priorityA.compareTo(priorityB);
        return delayOf(a).compareTo(delayOf(b));
      });
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      final groups = state.proxyGroups.value;
      final selected = state.selectedGroup;
      final fromProfile = state.proxiesFromProfile.value;

      if (groups.isEmpty) {
        return NexusEmptyState(
          icon: LucideIcons.layers,
          title: '暂无代理组',
          subtitle: state.status.value == ClashStatus.connected
              ? '当前配置未包含代理组，可在"订阅"页导入并应用订阅配置。'
              : '在"订阅"页导入订阅链接后，这里会显示订阅中的全部节点，无需运行核心。',
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fromProfile) ...[
            _OfflineBanner(
              profileLabel: state.activeProfile?.label ?? '',
              coreConnected: state.status.value == ClashStatus.connected,
            ),
            const SizedBox(height: NexusSpacing.md),
          ],
          _buildGroupTabs(context, groups),
          const SizedBox(height: NexusSpacing.md),
          if (selected != null) ...[
            _buildGroupHeader(context, selected, offline: fromProfile),
            const SizedBox(height: NexusSpacing.md),
            Expanded(
              child: _buildNodeGrid(
                context,
                selected,
                state.nodeDelays.value,
                state.testingNodes.value,
                offline: fromProfile,
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _buildGroupTabs(
    BuildContext context,
    List<ClashProxyGroup> groups,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: NexusSpacing.sm),
        itemBuilder: (context, index) {
          final group = groups[index];
          final selected =
              ClashState.instance.selectedGroupName.value == group.name;
          return GestureDetector(
            onTap: () => ClashState.instance.selectedGroupName.value =
                group.name,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary.withValues(alpha: 0.12)
                    : colorScheme.card,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(
                  color: selected
                      ? colorScheme.primary.withValues(alpha: 0.6)
                      : colorScheme.border,
                ),
              ),
              child: Text(
                group.name,
                style: NexusTypography.labelMd.copyWith(
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.mutedForeground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context,
    ClashProxyGroup group, {
    bool offline = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(group.name, style: NexusTypography.headlineSm),
              const SizedBox(height: 2),
              Text(
                '${group.type.label} · ${group.proxies.length} 个节点 · 当前：'
                '${group.realNow.isEmpty ? '-' : group.realNow}',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 180,
          child: TextField(
            controller: _searchController,
            hintText: '搜索节点…',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _HeaderIconButton(
          icon: LucideIcons.filter,
          tooltip: _sortByDelay ? '恢复配置顺序' : '按延迟排序',
          active: _sortByDelay,
          onPressed: () => setState(() => _sortByDelay = !_sortByDelay),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _HeaderIconButton(
          icon: LucideIcons.refreshCw,
          tooltip: '刷新',
          onPressed: () => ClashState.instance.refreshProxies(),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _HeaderIconButton(
          icon: LucideIcons.zap,
          tooltip: offline ? '连接核心后可测延迟' : '测试本组延迟',
          // Latency probing goes through the core; without one there is
          // nothing to measure.
          onPressed: offline
              ? null
              : () {
                  final selected = ClashState.instance.selectedGroup;
                  if (selected != null) {
                    ClashState.instance.testGroupDelays(selected);
                  }
                },
        ),
      ],
    );
  }

  Widget _buildNodeGrid(
    BuildContext context,
    ClashProxyGroup group,
    Map<String, int> delays,
    Set<String> testing, {
    bool offline = false,
  }) {
    final nodes = _visibleNodes(group, delays);
    if (nodes.isEmpty) {
      return Center(
        child: Text(
          '没有匹配的节点',
          style: NexusTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 190).floor().clamp(1, 6);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: NexusSpacing.sm,
            crossAxisSpacing: NexusSpacing.sm,
            childAspectRatio: 2.4,
          ),
          itemCount: nodes.length,
          itemBuilder: (context, index) {
            final proxy = nodes[index];
            final selected = group.realNow == proxy.name;
            final delay = delays[proxy.name] ?? proxy.latestDelay;
            return _ProxyCard(
              proxy: proxy,
              selected: selected,
              selectable: group.type.isSelectable,
              testing: testing.contains(proxy.name),
              delay: delay,
              onTap: () => _handleNodeTap(group, proxy.name),
              onTestDelay: offline ? null : () => ClashState.instance.testNodeDelay(proxy.name),
            );
          },
        );
      },
    );
  }

  Future<void> _handleNodeTap(ClashProxyGroup group, String proxyName) async {
    final state = ClashState.instance;
    if (!group.type.isSelectable) return;
    if (group.realNow == proxyName) return;
    try {
      await state.selectProxy(group.name, proxyName);
    } on ClashApiException {
      // Selection rejected by the core; the periodic refresh restores the
      // previous state.
    }
  }
}

/// Notice shown above the group tabs when the list was parsed locally from
/// the stored subscription instead of read from a running core.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.profileLabel, required this.coreConnected});

  final String profileLabel;
  final bool coreConnected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = profileLabel.isEmpty ? '当前订阅' : profileLabel;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 15, color: colorScheme.primary),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Text(
              coreConnected
                  ? '核心当前配置没有代理组，以下节点解析自订阅「$label」。'
                  : '未连接 Clash 核心，以下节点解析自订阅「$label」。选择会记录在本地，'
                        '连接核心并应用订阅后生效。',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon button used in the proxies toolbar.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;

    return GestureDetector(
      onTap: onPressed,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.border,
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: active
                ? colorScheme.primary
                : colorScheme.mutedForeground
                    .withValues(alpha: enabled ? 1.0 : 0.5),
          ),
        ),
      ),
    );
  }
}

/// One node tile, ported from FlClash's `ProxyCard`: name, type, colored
/// delay (tap the bolt to test) and the selected-state highlight.
class _ProxyCard extends StatelessWidget {
  const _ProxyCard({
    required this.proxy,
    required this.selected,
    required this.selectable,
    required this.testing,
    required this.delay,
    required this.onTap,
    this.onTestDelay,
  });

  final ClashProxy proxy;
  final bool selected;
  final bool selectable;
  final bool testing;
  final int delay;
  final VoidCallback onTap;
  final VoidCallback? onTestDelay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final delayColor = clashDelayColor(delay);

    return NexusCard(
      highlight: selected,
      onTap: selectable ? onTap : null,
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.sm,
      ),
      borderRadius: 12,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    proxy.name,
                    style: NexusTypography.bodyMd.copyWith(
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: NexusSpacing.xs),
                  Icon(LucideIcons.check, size: 14, color: colorScheme.primary),
                ],
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  proxy.type,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: NexusSpacing.xs),
              GestureDetector(
                onTap: onTestDelay,
                child: MouseRegion(
                  cursor: onTestDelay != null
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: SizedBox(
                    width: 58,
                    child: testing
                        ? const Center(
                            child: CircularProgressIndicator(size: 12),
                          )
                        : Text(
                            clashDelayText(delay),
                            textAlign: TextAlign.right,
                            style: NexusTypography.labelMd.copyWith(
                              color: delayColor ?? colorScheme.mutedForeground,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
