import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// New-connection stream, ported from FlClash's `RequestsView`: FlClash's
/// core pushes a request event for every new connection; this hub derives
/// the same stream by diffing the periodic connection snapshots.
class ClashRequestsView extends StatefulWidget {
  const ClashRequestsView({super.key});

  @override
  State<ClashRequestsView> createState() => _ClashRequestsViewState();
}

class _ClashRequestsViewState extends State<ClashRequestsView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClashConnection> _filtered(List<ClashConnection> requests) {
    final query = _searchController.text.toLowerCase().trim();
    if (query.isEmpty) return requests;
    return requests.where((connection) {
      final metadata = connection.metadata;
      return metadata.network.toLowerCase().contains(query) ||
          metadata.host.toLowerCase().contains(query) ||
          metadata.destinationIP.toLowerCase().contains(query) ||
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
      final requests = _filtered(state.requests.value);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('请求', style: NexusTypography.headlineSm),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                '${requests.length} 条',
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
                label: '清空',
                icon: LucideIcons.trash2,
                variant: NexusButtonVariant.outlined,
                onPressed: state.requests.value.isEmpty
                    ? null
                    : () => state.clearRequests(),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: requests.isEmpty
                ? NexusEmptyState(
                    icon: LucideIcons.radioTower,
                    title: '暂无新增请求',
                    subtitle: state.status.value == ClashStatus.connected
                        ? '核心建立新连接后会实时显示在这里。'
                        : '连接核心后此处实时显示新增连接。',
                  )
                : ListView.separated(
                    itemCount: requests.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: NexusSpacing.sm),
                    itemBuilder: (context, index) =>
                        _RequestCard(connection: requests[index]),
                  ),
          ),
        ],
      );
    });
  }
}

/// One new-connection entry: time, destination, network, chain and rule.
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.connection});

  final ClashConnection connection;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final metadata = connection.metadata;

    final clock =
        '${connection.start.hour.toString().padLeft(2, '0')}:'
        '${connection.start.minute.toString().padLeft(2, '0')}:'
        '${connection.start.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(NexusSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              clock,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    NexusBadge(
                      label: metadata.network.isEmpty
                          ? '-'
                          : metadata.network.toUpperCase(),
                      backgroundColor: colorScheme.primary.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: colorScheme.primary,
                    ),
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
        ],
      ),
    );
  }
}
