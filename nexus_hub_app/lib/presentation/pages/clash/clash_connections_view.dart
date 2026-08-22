import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// Ordering of the connections list.
enum _ConnectionSort { start, speed, upload, download }

/// Active connections screen, ported from FlClash's `ConnectionsView`:
/// searchable, sortable connection list with chain/rule/process details,
/// per-item plus global close actions and a detail sheet. The filter is
/// ported from FlClash's `TrackerInfosStateExt.list`.
class ClashConnectionsView extends StatefulWidget {
  const ClashConnectionsView({super.key});

  @override
  State<ClashConnectionsView> createState() => _ClashConnectionsViewState();
}

class _ClashConnectionsViewState extends State<ClashConnectionsView> {
  final TextEditingController _searchController = TextEditingController();

  _ConnectionSort _sort = _ConnectionSort.start;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClashConnection> _filtered(List<ClashConnection> connections) {
    final query = _searchController.text.toLowerCase().trim();
    var result = connections.where((connection) {
      if (query.isEmpty) return true;
      final metadata = connection.metadata;
      return metadata.network.toLowerCase().contains(query) ||
          metadata.host.toLowerCase().contains(query) ||
          metadata.destinationIP.toLowerCase().contains(query) ||
          metadata.destinationPort.contains(query) ||
          metadata.process.toLowerCase().contains(query) ||
          connection.chains.any(
            (chain) => chain.toLowerCase().contains(query),
          ) ||
          connection.rule.toLowerCase().contains(query);
    }).toList();

    int speedOf(ClashConnection connection) =>
        (connection.uploadSpeed ?? 0) + (connection.downloadSpeed ?? 0);
    switch (_sort) {
      case _ConnectionSort.start:
        result.sort((a, b) => b.start.compareTo(a.start));
      case _ConnectionSort.speed:
        result.sort((a, b) => speedOf(b).compareTo(speedOf(a)));
      case _ConnectionSort.upload:
        result.sort((a, b) => b.upload.compareTo(a.upload));
      case _ConnectionSort.download:
        result.sort((a, b) => b.download.compareTo(a.download));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final connections = _filtered(state.connections.value);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('活动连接', style: NexusTypography.headlineSm),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                '${connections.length}',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              const Spacer(),
              for (final sort in _ConnectionSort.values) ...[
                _SortChip(
                  label: switch (sort) {
                    _ConnectionSort.start => '时间',
                    _ConnectionSort.speed => '速度',
                    _ConnectionSort.upload => '上传',
                    _ConnectionSort.download => '下载',
                  },
                  selected: _sort == sort,
                  onTap: () => setState(() => _sort = sort),
                ),
                const SizedBox(width: NexusSpacing.xs),
              ],
              const SizedBox(width: NexusSpacing.sm),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchController,
                  hintText: '搜索主机 / 进程 / 链路…',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: '关闭全部',
                icon: LucideIcons.x,
                variant: NexusButtonVariant.outlined,
                onPressed: () => state.closeAllConnections(),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: connections.isEmpty
                ? NexusEmptyState(
                    icon: LucideIcons.cable,
                    title: '暂无活动连接',
                    subtitle: state.status.value == ClashStatus.connected
                        ? '当前没有经过核心的连接。'
                        : '连接核心后此处显示实时连接。',
                  )
                : ListView.separated(
                    itemCount: connections.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: NexusSpacing.sm),
                    itemBuilder: (context, index) {
                      return _ConnectionCard(
                        connection: connections[index],
                        onClose: () => state.closeConnection(
                          connections[index].id,
                        ),
                        onOpenDetail: () =>
                            _showDetail(context, connections[index]),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }

  void _showDetail(BuildContext context, ClashConnection connection) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (dialogContext) => _ConnectionDetailDialog(connection: connection),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
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
            horizontal: NexusSpacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.border,
            ),
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// One connection row, ported from FlClash's `ConnectionItem`: destination,
/// network, chain (node → group), rule, traffic, live speed and process.
/// Clicking it opens the metadata detail dialog.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.onClose,
    required this.onOpenDetail,
  });

  final ClashConnection connection;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = connection.metadata;

    final networkBadge = NexusBadge(
      label: metadata.network.isEmpty ? '-' : metadata.network.toUpperCase(),
      backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
      foregroundColor: colorScheme.primary,
    );

    final speedText = [
      if (connection.uploadSpeed != null)
        '↑ ${formatClashSpeed(connection.uploadSpeed!)}',
      if (connection.downloadSpeed != null)
        '↓ ${formatClashSpeed(connection.downloadSpeed!)}',
    ].join('  ');

    return GestureDetector(
      onTap: onOpenDetail,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.all(NexusSpacing.md),
          decoration: BoxDecoration(
            color: colorScheme.card,
            borderRadius: BorderRadius.circular(12),
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
                        networkBadge,
                        const SizedBox(width: NexusSpacing.sm),
                        Expanded(
                          child: Text(
                            metadata.destination,
                            style: NexusTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        connection.chainText,
                        connection.ruleText,
                        if (metadata.process.isNotEmpty) metadata.process,
                        '开始 ${_formatClock(connection.start)}',
                        if (speedText.isNotEmpty) speedText,
                        '↑ ${formatClashBytes(connection.upload)}',
                        '↓ ${formatClashBytes(connection.download)}',
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
              IconButton.ghost(
                icon: const Icon(LucideIcons.x, size: 15),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatClock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}

/// Full metadata of one connection, ported from FlClash's connection detail
/// sheet.
class _ConnectionDetailDialog extends StatelessWidget {
  const _ConnectionDetailDialog({required this.connection});

  final ClashConnection connection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = connection.metadata;

    String clock(DateTime time) =>
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';

    final rows = <(String, String)>[
      ('目标', metadata.destination),
      ('网络', '${metadata.network} / ${metadata.type}'),
      ('代理链', connection.chainText),
      ('规则', connection.ruleText),
      ('进程', metadata.process.isEmpty ? '-' : metadata.process),
      ('进程路径', metadata.processPath.isEmpty ? '-' : metadata.processPath),
      ('源地址', '${metadata.sourceIP}:${metadata.sourcePort}'),
      ('目标地址', '${metadata.destinationIP}:${metadata.destinationPort}'),
      ('DNS 模式', metadata.dnsMode.isEmpty ? '-' : metadata.dnsMode),
      ('开始时间', clock(connection.start)),
      ('上传', formatClashBytes(connection.upload)),
      ('下载', formatClashBytes(connection.download)),
    ];

    return AlertDialog(
      title: Text('连接详情', style: NexusTypography.headlineSm),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 76,
                      child: Text(
                        label,
                        style: NexusTypography.labelMd.copyWith(
                          color: colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        value,
                        style: NexusTypography.labelMd,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        Button.text(
          onPressed: () {
            ClashState.instance.closeConnection(connection.id);
            closeOverlay(context);
          },
          child: const Text('断开此连接'),
        ),
        Button.primary(
          onPressed: () => closeOverlay(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
