import 'package:fl_chart/fl_chart.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../../data/services/clash_api_service.dart'
    show ClashApiException;
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_card.dart';

/// Overview screen, ported from FlClash's `DashboardView`: core status,
/// outbound mode switch, live throughput, traffic chart and quick actions.
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

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StatusCard()),
              SizedBox(width: NexusSpacing.md),
              Expanded(child: _SpeedCard()),
            ],
          ),
          SizedBox(height: NexusSpacing.md),
          _TrafficChartCard(),
          SizedBox(height: NexusSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _ConnectionsCard()),
              SizedBox(width: NexusSpacing.md),
              Expanded(child: _QuickActionsCard()),
            ],
          ),
        ],
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

/// Live throughput and transferred totals (FlClash's `NetworkSpeedView`).
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
            const SizedBox(height: NexusSpacing.lg),
            _InfoRow(label: '总上传', value: formatClashBytes(state.uploadTotal.value)),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(
              label: '总下载',
              value: formatClashBytes(state.downloadTotal.value),
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

/// Rolling throughput chart over the last minute, built like the hub's
/// my-computer live chart but with the up/down pair FlClash shows.
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

/// Active connection count and totals.
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
