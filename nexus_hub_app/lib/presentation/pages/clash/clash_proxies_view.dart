import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException;
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_empty_state.dart';

/// Proxies screen, ported from FlClash's `ProxiesView`: two layouts (tab grid
/// / group list, FlClash `ProxiesType`), ordering modes (FlClash `SortType`),
/// node selection, per-node and per-group delay testing with FlClash's delay
/// coloring, plus the external providers management dialog.
class ClashProxiesView extends StatefulWidget {
  const ClashProxiesView({super.key});

  @override
  State<ClashProxiesView> createState() => _ClashProxiesViewState();
}

class _ClashProxiesViewState extends State<ClashProxiesView> {
  final TextEditingController _searchController = TextEditingController();

  /// Expanded groups of the list layout.
  final Set<String> _expandedGroups = {};

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
    ClashProxiesSort sort,
  ) {
    final query = _searchController.text.toLowerCase().trim();
    var nodes = group.proxies.where((proxy) {
      return query.isEmpty ||
          proxy.name.toLowerCase().contains(query) ||
          proxy.type.toLowerCase().contains(query);
    }).toList();
    int delayOf(ClashProxy proxy) => delays[proxy.name] ?? proxy.latestDelay;
    switch (sort) {
      case ClashProxiesSort.delay:
        nodes.sort((a, b) {
          final priorityA = _delayPriority(delayOf(a));
          final priorityB = _delayPriority(delayOf(b));
          if (priorityA != priorityB) return priorityA.compareTo(priorityB);
          return delayOf(a).compareTo(delayOf(b));
        });
      case ClashProxiesSort.name:
        nodes.sort((a, b) => a.name.compareTo(b.name));
      case ClashProxiesSort.defaultOrder:
        break;
    }
    return nodes;
  }

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      final groups = state.proxyGroups.value;
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
          _buildToolbar(context, state),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: switch (state.proxiesLayout.value) {
              ClashProxiesLayout.tabs => _buildTabsLayout(context, state),
              ClashProxiesLayout.list => _buildListLayout(context, state),
            },
          ),
        ],
      );
    });
  }

  Widget _buildToolbar(BuildContext context, ClashState state) {
    return Row(
      children: [
        // Layout switcher (FlClash's tab / list layout toggle).
        for (final layout in ClashProxiesLayout.values) ...[
          _ToolbarChip(
            label: layout.label,
            selected: state.proxiesLayout.value == layout,
            onTap: () => state.setProxiesLayout(layout),
          ),
          const SizedBox(width: NexusSpacing.xs),
        ],
        const SizedBox(width: NexusSpacing.sm),
        // Sort menu (FlClash's proxies settings sheet).
        for (final sort in ClashProxiesSort.values) ...[
          _ToolbarChip(
            label: sort.label,
            selected: state.proxiesSort.value == sort,
            onTap: () => state.setProxiesSort(sort),
          ),
          const SizedBox(width: NexusSpacing.xs),
        ],
        const Spacer(),
        SizedBox(
          width: 170,
          child: TextField(
            controller: _searchController,
            hintText: '搜索节点…',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _HeaderIconButton(
          icon: LucideIcons.package,
          tooltip: '外部提供者',
          onPressed: () => _showProvidersDialog(context),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _HeaderIconButton(
          icon: LucideIcons.refreshCw,
          tooltip: '刷新',
          onPressed: () => state.refreshProxies(),
        ),
      ],
    );
  }

  Widget _buildTabsLayout(BuildContext context, ClashState state) {
    final groups = state.proxyGroups.value;
    final selected = state.selectedGroup;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildGroupTabs(context, groups),
        const SizedBox(height: NexusSpacing.md),
        if (selected != null) ...[
          _buildGroupHeader(
            context,
            selected,
            offline: state.proxiesFromProfile.value,
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: _buildNodeGrid(
              context,
              selected,
              state.nodeDelays.value,
              state.testingNodes.value,
              state.proxiesSort.value,
              offline: state.proxiesFromProfile.value,
            ),
          ),
        ],
      ],
    );
  }

  /// List layout (FlClash `ProxiesType.list`): every group is an expandable
  /// section instead of one tab strip.
  Widget _buildListLayout(BuildContext context, ClashState state) {
    final groups = state.proxyGroups.value;
    if (_expandedGroups.isEmpty) {
      _expandedGroups.add(state.selectedGroupName.value ?? groups.first.name);
    }

    return ListView.separated(
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.sm),
      itemBuilder: (context, index) {
        final group = groups[index];
        final expanded = _expandedGroups.contains(group.name);
        return NexusCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ListGroupHeader(
                group: group,
                expanded: expanded,
                onToggle: () => setState(() {
                  expanded
                      ? _expandedGroups.remove(group.name)
                      : _expandedGroups.add(group.name);
                }),
                onTestDelay: state.proxiesFromProfile.value
                    ? null
                    : () => state.testGroupDelays(group),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NexusSpacing.md,
                    0,
                    NexusSpacing.md,
                    NexusSpacing.md,
                  ),
                  child: _buildNodeGrid(
                    context,
                    group,
                    state.nodeDelays.value,
                    state.testingNodes.value,
                    state.proxiesSort.value,
                    offline: state.proxiesFromProfile.value,
                  ),
                ),
            ],
          ),
        );
      },
    );
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
    Set<String> testing,
    ClashProxiesSort sort, {
    bool offline = false,
  }) {
    final nodes = _visibleNodes(group, delays, sort);
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
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
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

  void _showProvidersDialog(BuildContext context) {
    ClashState.instance.refreshProxyProviders();
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => const _ProvidersDialog(),
      ),
    );
  }
}

/// Selectable pill used in the proxies toolbar (layout / sort switcher).
class _ToolbarChip extends StatelessWidget {
  const _ToolbarChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
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

/// Collapsible group header of the list layout (FlClash's accordion groups).
class _ListGroupHeader extends StatelessWidget {
  const _ListGroupHeader({
    required this.group,
    required this.expanded,
    required this.onToggle,
    this.onTestDelay,
  });

  final ClashProxyGroup group;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback? onTestDelay;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.md),
        child: Row(
          children: [
            Icon(
              expanded
                  ? LucideIcons.chevronDown
                  : LucideIcons.chevronRight,
              size: 16,
              color: colorScheme.mutedForeground,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name, style: NexusTypography.bodyLg),
                  const SizedBox(height: 2),
                  Text(
                    '${group.type.label} · ${group.proxies.length} 个节点 · 当前：'
                    '${group.realNow.isEmpty ? '-' : group.realNow}',
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTestDelay != null) ...[
              const SizedBox(width: NexusSpacing.sm),
              GestureDetector(
                onTap: onTestDelay,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colorScheme.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.border),
                    ),
                    child: Icon(
                      LucideIcons.zap,
                      size: 14,
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

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
            color: colorScheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.border),
          ),
          child: Icon(
            icon,
            size: 15,
            color: colorScheme.mutedForeground
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

/// External proxy providers manager, ported from FlClash's `ProvidersView`:
/// every provider with its vehicle type, node count, subscription quota,
/// last update time and an update / health-check action.
class _ProvidersDialog extends StatelessWidget {
  const _ProvidersDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final providers = state.proxyProviders.value;

      return AlertDialog(
        title: Text('外部代理提供者', style: NexusTypography.headlineSm),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
          child: providers.isEmpty
              ? SizedBox(
                  height: 120,
                  child: Center(
                    child: Text(
                      '当前配置没有外部代理提供者（proxy-providers）。',
                      style: NexusTypography.bodyMd.copyWith(
                        color: colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: providers.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: NexusSpacing.sm),
                  itemBuilder: (context, index) =>
                      _ProviderRow(provider: providers[index]),
                ),
        ),
        actions: [
          Button.text(
            onPressed: () => state.refreshProxyProviders(),
            child: const Text('刷新'),
          ),
          Button.primary(
            onPressed: () => closeOverlay(context),
            child: const Text('关闭'),
          ),
        ],
      );
    });
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({required this.provider});

  final ClashProxyProvider provider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ClashState.instance;

    return Watch((_) {
      final busy = state.updatingProviders.value.contains(provider.name);
      final info = provider.subscriptionInfo;

      return Container(
        padding: const EdgeInsets.all(NexusSpacing.md),
        decoration: BoxDecoration(
          color: colorScheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          provider.name,
                          style: NexusTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      NexusBadge(
                        label: provider.vehicleType,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.1,
                        ),
                        foregroundColor: colorScheme.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      '${provider.proxyCount} 个节点',
                      if (provider.updatedAt != null)
                        '更新于 ${DateFormat('MM-dd HH:mm').format(provider.updatedAt!)}',
                      if (info != null && info.hasQuota)
                        '已用 ${formatClashBytes(info.used)} / ${formatClashBytes(info.total)}',
                    ].join('  ·  '),
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(size: 12),
                  )
                : provider.canUpdate
                    ? GestureDetector(
                        onTap: () => state.updateProxyProvider(provider.name),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              LucideIcons.refreshCw,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox(width: 30),
          ],
        ),
      );
    });
  }
}
