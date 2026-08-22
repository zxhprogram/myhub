import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// Active connections screen, ported from FlClash's `ConnectionsView`:
/// searchable connection list with chain/rule/process details and per-item
/// plus global close actions. The filter is ported from FlClash's
/// `TrackerInfosStateExt.list`.
class ClashConnectionsView extends StatefulWidget {
  const ClashConnectionsView({super.key});

  @override
  State<ClashConnectionsView> createState() => _ClashConnectionsViewState();
}

class _ClashConnectionsViewState extends State<ClashConnectionsView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClashConnection> _filtered(List<ClashConnection> connections) {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return connections;
    return connections.where((connection) {
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
              SizedBox(
                width: 220,
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
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}

/// One connection row, ported from FlClash's `ConnectionItem`: destination,
/// network, chain (node → group), rule, traffic and process.
class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.connection, required this.onClose});

  final ClashConnection connection;
  final VoidCallback onClose;

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

    return Container(
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
    );
  }

  static String _formatClock(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:'
      '${time.second.toString().padLeft(2, '0')}';
}
