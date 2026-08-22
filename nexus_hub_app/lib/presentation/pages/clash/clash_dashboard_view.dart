import 'package:fl_chart/fl_chart.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException;
import '../../../data/services/clash_system_proxy.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';
import '../../components/nexus_toast.dart';

/// Overview screen, ported from FlClash's `DashboardView`: an editable card
/// grid (core status + outbound mode, live speed, traffic chart, traffic
/// totals, connections, memory, network detection, TUN / system proxy
/// switches and quick actions).
class ClashDashboardView extends StatelessWidget {
  const ClashDashboardView({super.key, this.onOpenSettings});

  /// Jumps to the settings view (passed by the page shell).
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      if (state.status.value != ClashStatus.connected) {
        return _NotConnectedCard(onOpenSettings: onOpenSettings);
      }
      return const _DashboardContent();
    });
  }
}

/// Shown while the core is not connected.
class _NotConnectedCard extends StatelessWidget {
  const _NotConnectedCard({this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final status = state.status.value;
      final connecting = status == ClashStatus.connecting;
      final failed = status == ClashStatus.error;

      return Center(
        child: NexusCard(
          padding: const EdgeInsets.all(NexusSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.shield,
                  size: 44,
                  color: failed
                      ? colorScheme.destructive
                      : colorScheme.mutedForeground,
                ),
                const SizedBox(height: NexusSpacing.md),
                Text(
                  connecting ? '正在连接核心…' : '未连接到 Clash 核心',
                  style: NexusTypography.headlineSm,
                ),
                const SizedBox(height: NexusSpacing.sm),
                Text(
                  failed
                      ? '连接失败：${state.statusMessage.value}\n请检查核心是否运行，或在设置中调整地址。'
                      : '当前端点：${state.apiHost.value}:${state.apiPort.value}\n'
                            '请确认核心已启动并开启 External Controller。',
                  textAlign: TextAlign.center,
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: NexusSpacing.lg),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    NexusButton(
                      label: connecting ? '连接中' : (failed ? '重试' : '连接'),
                      icon: LucideIcons.plug,
                      isLoading: connecting,
                      onPressed: connecting ? null : () => state.connect(),
                    ),
                    const SizedBox(width: NexusSpacing.md),
                    NexusButton(
                      label: '打开设置',
                      icon: LucideIcons.settings,
                      variant: NexusButtonVariant.outlined,
                      onPressed: onOpenSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  /// Cards that span the full row; every other card shares a row in pairs.
  static const _fullWidth = {ClashDashboardWidget.trafficChart};

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final widgets = ClashState.instance.dashboardWidgets.value;

      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('概览', style: NexusTypography.headlineSm),
                ),
                NexusButton(
                  label: '自定义组件',
                  icon: LucideIcons.layoutGrid,
                  variant: NexusButtonVariant.outlined,
                  onPressed: () => _showCustomizeDialog(context),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            for (final row in _rowsOf(widgets)) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < row.length; i++) ...[
                    if (i > 0) const SizedBox(width: NexusSpacing.md),
                    Expanded(child: _cardFor(row[i])),
                  ],
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
            ],
          ],
        ),
      );
    });
  }

  /// Splits [widgets] into display rows: full-width cards occupy a row of
  /// their own, the rest are paired two per row.
  List<List<ClashDashboardWidget>> _rowsOf(List<ClashDashboardWidget> widgets) {
    final rows = <List<ClashDashboardWidget>>[];
    var pending = <ClashDashboardWidget>[];
    for (final widget in widgets) {
      if (_fullWidth.contains(widget)) {
        if (pending.isNotEmpty) {
          rows.add(pending);
          pending = <ClashDashboardWidget>[];
        }
        rows.add([widget]);
        continue;
      }
      pending.add(widget);
      if (pending.length == 2) {
        rows.add(pending);
        pending = <ClashDashboardWidget>[];
      }
    }
    if (pending.isNotEmpty) rows.add(pending);
    return rows;
  }

  Widget _cardFor(ClashDashboardWidget widget) {
    return switch (widget) {
      ClashDashboardWidget.status => const _StatusCard(),
      ClashDashboardWidget.speed => const _SpeedCard(),
      ClashDashboardWidget.trafficChart => const _TrafficChartCard(),
      ClashDashboardWidget.trafficUsage => const _TrafficUsageCard(),
      ClashDashboardWidget.connections => const _ConnectionsCard(),
      ClashDashboardWidget.memory => const _MemoryCard(),
      ClashDashboardWidget.network => const _NetworkCard(),
      ClashDashboardWidget.tun => const _TunCard(),
      ClashDashboardWidget.systemProxy => const _SystemProxyCard(),
      ClashDashboardWidget.actions => const _QuickActionsCard(),
    };
  }

  void _showCustomizeDialog(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => const _CustomizeDashboardDialog(),
      ),
    );
  }
}

/// Widget-grid editor, ported from FlClash's dashboard edit mode: toggle
/// cards on / off and reorder them; the layout persists immediately.
class _CustomizeDashboardDialog extends StatelessWidget {
  const _CustomizeDashboardDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final visible = state.dashboardWidgets.value;
      final hidden = ClashDashboardWidget.values
          .where((widget) => !visible.contains(widget))
          .toList();

      return AlertDialog(
        title: Text('自定义仪表盘组件', style: NexusTypography.headlineSm),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已显示（可拖动右侧按钮调整顺序）',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
              Flexible(
                child: ListView(
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      _WidgetRow(
                        label: visible[i].label,
                        canMoveUp: i > 0,
                        canMoveDown: i < visible.length - 1,
                        onMoveUp: () => _move(context, visible, i, i - 1),
                        onMoveDown: () => _move(context, visible, i, i + 1),
                        onRemove: () => ClashState.instance.setDashboardWidgets(
                          [
                            for (var j = 0; j < visible.length; j++)
                              if (j != i) visible[j],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (hidden.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.md),
                Text(
                  '可添加',
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: NexusSpacing.sm),
                for (final widget in hidden)
                  _WidgetRow(
                    label: widget.label,
                    onAdd: () => ClashState.instance.setDashboardWidgets(
                      [...visible, widget],
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          Button.primary(
            onPressed: () => closeOverlay(context),
            child: const Text('完成'),
          ),
        ],
      );
    });
  }

  void _move(
    BuildContext context,
    List<ClashDashboardWidget> widgets,
    int from,
    int to,
  ) {
    final next = [...widgets];
    final item = next.removeAt(from);
    next.insert(to, item);
    ClashState.instance.setDashboardWidgets(next);
  }
}

class _WidgetRow extends StatelessWidget {
  const _WidgetRow({
    required this.label,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
    this.onAdd,
  });

  final String label;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;

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
          color: colorScheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: NexusTypography.bodyMd),
            ),
            if (onAdd != null)
              IconButton.ghost(
                icon: const Icon(LucideIcons.plus, size: 14),
                onPressed: onAdd,
              )
            else ...[
              if (onMoveUp != null || onMoveDown != null) ...[
                GestureDetector(
                  onTap: canMoveUp ? onMoveUp : null,
                  child: MouseRegion(
                    cursor: canMoveUp
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: Icon(
                      LucideIcons.chevronUp,
                      size: 16,
                      color: canMoveUp
                          ? colorScheme.mutedForeground
                          : colorScheme.mutedForeground.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: canMoveDown ? onMoveDown : null,
                  child: MouseRegion(
                    cursor: canMoveDown
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.basic,
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 16,
                      color: canMoveDown
                          ? colorScheme.mutedForeground
                          : colorScheme.mutedForeground.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ],
              GestureDetector(
                onTap: onRemove,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    LucideIcons.x,
                    size: 15,
                    color: colorScheme.mutedForeground,
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

/// Core version, endpoint and the outbound mode switch (FlClash's
/// `OutboundModeButton`).
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final version = state.version.value;
      final config = state.runningConfig.value;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.server, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('核心状态', style: NexusTypography.headlineSm),
                const Spacer(),
                if (version?.meta == true)
                  SecondaryBadge(child: Text('meta')),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            _InfoRow(label: '核心版本', value: version?.version ?? '-'),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(
              label: '端点',
              value: '${state.apiHost.value}:${state.apiPort.value}',
            ),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(label: '入站端口', value: config?.inboundPort ?? '-'),
            const SizedBox(height: NexusSpacing.lg),
            Text(
              '出站模式',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            _ModeSwitcher(
              current: config?.mode ?? ClashProxyMode.rule,
              onSelect: (mode) => _switchMode(mode),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _switchMode(ClashProxyMode mode) async {
    try {
      await ClashState.instance.switchMode(mode);
    } on ClashApiException {
      // Mode switch rejected by the core — the next refresh restores the
      // previous mode in the UI.
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 72,
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
              color: colorScheme.foreground,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Segmented 规则 / 全局 / 直连 selector (FlClash's outbound mode switch).
class _ModeSwitcher extends StatelessWidget {
  const _ModeSwitcher({required this.current, required this.onSelect});

  final ClashProxyMode current;
  final ValueChanged<ClashProxyMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colorScheme.muted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.border),
      ),
      child: Row(
        children: [
          for (final mode in ClashProxyMode.values) ...[
            if (mode != ClashProxyMode.values.first)
              const SizedBox(width: 3),
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(mode),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: mode == current
                        ? colorScheme.background
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: mode == current
                        ? [
                            BoxShadow(
                              color: colorScheme.foreground.withValues(
                                alpha: 0.08,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    mode.label,
                    textAlign: TextAlign.center,
                    style: NexusTypography.labelMd.copyWith(
                      color: mode == current
                          ? colorScheme.foreground
                          : colorScheme.mutedForeground,
                      fontWeight: mode == current
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Live throughput (FlClash's `NetworkSpeed` dashboard widget).
class _SpeedCard extends StatelessWidget {
  const _SpeedCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final traffic = state.currentTraffic;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.activity, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('实时速率', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _SpeedTile(
                    icon: LucideIcons.arrowUp,
                    label: '上传',
                    text: formatClashSpeed(traffic.up),
                  ),
                ),
                const SizedBox(width: NexusSpacing.md),
                Expanded(
                  child: _SpeedTile(
                    icon: LucideIcons.arrowDown,
                    label: '下载',
                    text: formatClashSpeed(traffic.down),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.icon,
    required this.label,
    required this.text,
  });

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: colorScheme.mutedForeground),
              const SizedBox(width: 4),
              Text(
                label,
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: NexusTypography.headlineSm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Rolling throughput chart over the last minute (FlClash's traffic chart).
class _TrafficChartCard extends StatelessWidget {
  const _TrafficChartCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final history = ClashState.instance.trafficHistory.value;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.network, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('吞吐量(最近 60 秒)', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            SizedBox(
              height: 180,
              child: history.length < 2
                  ? Center(
                      child: Text(
                        '正在采样…',
                        style: NexusTypography.labelMd.copyWith(
                          color: colorScheme.mutedForeground,
                        ),
                      ),
                    )
                  : _buildChart(context, history),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildChart(BuildContext context, List<ClashTraffic> history) {
    var maxValue = 1024.0;
    for (final sample in history) {
      if (sample.up > maxValue) maxValue = sample.up.toDouble();
      if (sample.down > maxValue) maxValue = sample.down.toDouble();
    }

    LineChartBarData series(
      List<double> values,
      Color color,
      double alpha,
    ) {
      return LineChartBarData(
        spots: [
          for (var i = 0; i < values.length; i++)
            FlSpot(i.toDouble(), values[i]),
        ],
        color: color,
        isCurved: true,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          color: color.withValues(alpha: alpha),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (history.length - 1).toDouble(),
        minY: 0,
        maxY: maxValue * 1.15,
        lineBarsData: [
          series(
            [for (final sample in history) sample.up.toDouble()],
            const Color(0xFF3B82F6),
            0.12,
          ),
          series(
            [for (final sample in history) sample.down.toDouble()],
            const Color(0xFF22C55E),
            0.15,
          ),
        ],
        titlesData: const FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}

/// Cumulative upload / download since the core started (FlClash's
/// `TrafficUsage` widget).
class _TrafficUsageCard extends StatelessWidget {
  const _TrafficUsageCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final info = state.activeProfile?.subscriptionInfo;
      final fraction = info?.usedFraction;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.arrowUpDown,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Text('流量统计', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            _InfoRow(
              label: '总上传',
              value: formatClashBytes(state.uploadTotal.value),
            ),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(
              label: '总下载',
              value: formatClashBytes(state.downloadTotal.value),
            ),
            if (info != null && info.hasQuota) ...[
              const SizedBox(height: NexusSpacing.md),
              Progress(
                progress: fraction ?? 0,
                color: (fraction ?? 0) > 0.9
                    ? colorScheme.destructive
                    : colorScheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                '订阅已用 ${formatClashBytes(info.used)} / ${formatClashBytes(info.total)}',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    });
  }
}

/// Active connection count and rule count.
class _ConnectionsCard extends StatelessWidget {
  const _ConnectionsCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.cable, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('活动连接', style: NexusTypography.headlineSm),
                const Spacer(),
                Text(
                  '${state.connections.value.length}',
                  style: NexusTypography.headlineSm.copyWith(
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            _InfoRow(
              label: '规则数量',
              value: '${state.ruleCount.value}',
            ),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(
              label: '出站模式',
              value: state.runningConfig.value?.mode.label ?? '-',
            ),
          ],
        ),
      );
    });
  }
}

/// In-use core memory (FlClash's `MemoryInfo` widget).
class _MemoryCard extends StatelessWidget {
  const _MemoryCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final memory = ClashState.instance.memory.value;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.cpu, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('核心内存', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            Text(
              memory > 0 ? formatClashBytes(memory) : '暂无数据',
              style: NexusTypography.headlineSm.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: memory > 0
                    ? colorScheme.foreground
                    : colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '核心当前占用内存（/memory）',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Exit IP + country (FlClash's `NetworkDetection` widget); the probe goes
/// through the core so the exit node's location is shown.
class _NetworkCard extends StatelessWidget {
  const _NetworkCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final info = state.networkInfo.value;
      final checking = state.networkChecking.value;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.globe, size: 18, color: colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('网络检测', style: NexusTypography.headlineSm),
                const Spacer(),
                checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(size: 12),
                      )
                    : GestureDetector(
                        onTap: () => state.detectNetwork(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Icon(
                            LucideIcons.refreshCw,
                            size: 15,
                            color: colorScheme.mutedForeground,
                          ),
                        ),
                      ),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            _InfoRow(label: '出口 IP', value: info?.ip ?? '未检测'),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(
              label: '位置',
              value: info == null || info.country.isEmpty
                  ? (info == null ? '-' : '未知')
                  : info.country,
            ),
          ],
        ),
      );
    });
  }
}

/// TUN inbound switch (FlClash's `TUNButton` dashboard widget, expressed as
/// a hot patch of the `tun` config block).
class _TunCard extends StatelessWidget {
  const _TunCard();

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      final state = ClashState.instance;
      final tun = state.runningConfig.value?.tun;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Row(
          children: [
            Icon(LucideIcons.router, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TUN 模式', style: NexusTypography.headlineSm),
                  const SizedBox(height: 2),
                  Text(
                    '虚拟网卡接管全局流量（stack：${tun?.stack ?? '-'}）',
                    style: NexusTypography.labelMd.copyWith(
                      color: Theme.of(context).colorScheme.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Switch(
              value: tun?.enable ?? false,
              onChanged: (value) => _toggle(context, value),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    try {
      await ClashState.instance.setTunEnabled(value);
    } on ClashApiException catch (error) {
      if (context.mounted) {
        nexusToast(
          context,
          'TUN 切换失败：${error.message}（可能需要核心以管理员运行）',
          isError: true,
        );
      }
    }
  }
}

/// Windows system proxy switch (FlClash's `SystemProxyButton`): points
/// WinINET at the core's inbound port.
class _SystemProxyCard extends StatelessWidget {
  const _SystemProxyCard();

  @override
  Widget build(BuildContext context) {
    final supported = ClashSystemProxyService.instance.isSupported;
    if (!supported) return const SizedBox.shrink();

    return Watch((_) {
      final state = ClashState.instance;

      return NexusCard(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Row(
          children: [
            Icon(
              LucideIcons.monitorSmartphone,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('系统代理', style: NexusTypography.headlineSm),
                  const SizedBox(height: 2),
                  Text(
                    '将系统 HTTP 代理指向 127.0.0.1:'
                    '${state.runningConfig.value?.inboundPort ?? '-'}',
                    style: NexusTypography.labelMd.copyWith(
                      color: Theme.of(context).colorScheme.mutedForeground,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            state.systemProxyBusy.value
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(size: 12),
                  )
                : Switch(
                    value: state.systemProxyEnabled.value,
                    onChanged: (value) => _toggle(context, value),
                  ),
          ],
        ),
      );
    });
  }

  Future<void> _toggle(BuildContext context, bool value) async {
    try {
      await ClashState.instance.setSystemProxy(value);
    } on ClashSystemProxyException catch (error) {
      if (context.mounted) {
        nexusToast(context, error.message, isError: true);
      }
    }
  }
}

/// Refresh / close-all quick actions.
class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    return NexusCard(
      padding: const EdgeInsets.all(NexusSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('快捷操作', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.md),
          Wrap(
            spacing: NexusSpacing.md,
            runSpacing: NexusSpacing.sm,
            children: [
              NexusButton(
                label: '刷新代理',
                icon: LucideIcons.refreshCw,
                variant: NexusButtonVariant.tonal,
                onPressed: () => ClashState.instance.refreshProxies(),
              ),
              NexusButton(
                label: '刷新连接',
                icon: LucideIcons.cable,
                variant: NexusButtonVariant.tonal,
                onPressed: () => ClashState.instance.refreshConnections(),
              ),
              NexusButton(
                label: '断开全部连接',
                icon: LucideIcons.x,
                variant: NexusButtonVariant.outlined,
                onPressed: () => ClashState.instance.closeAllConnections(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
