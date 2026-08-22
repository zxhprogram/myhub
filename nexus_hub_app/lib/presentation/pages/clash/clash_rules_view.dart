import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_badge.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// Routing rules screen: the core's active rule table (`GET /rules`) with a
/// type filter and search, plus the external rule providers panel
/// (FlClash's resources management: provider update / last update time).
class ClashRulesView extends StatefulWidget {
  const ClashRulesView({super.key});

  @override
  State<ClashRulesView> createState() => _ClashRulesViewState();
}

class _ClashRulesViewState extends State<ClashRulesView> {
  final TextEditingController _searchController = TextEditingController();

  String? _typeFilter;

  @override
  void initState() {
    super.initState();
    ClashState.instance.refreshRules();
    ClashState.instance.refreshRuleProviders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final rules = state.rules.value;
      final types = _distinctTypes(rules);
      final filtered = _filtered(rules);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('规则', style: NexusTypography.headlineSm),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                '${filtered.length} / ${rules.length} 条',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _searchController,
                  hintText: '搜索规则 / 目标…',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: '刷新',
                icon: LucideIcons.refreshCw,
                variant: NexusButtonVariant.tonal,
                onPressed: () {
                  state.refreshRules();
                  state.refreshRuleProviders();
                },
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          if (types.isNotEmpty)
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final type in [
                    null,
                    ...types,
                  ]) ...[
                    _TypeChip(
                      label: type ?? '全部',
                      selected: _typeFilter == type,
                      onTap: () => setState(() => _typeFilter = type),
                    ),
                    const SizedBox(width: NexusSpacing.xs),
                  ],
                ],
              ),
            ),
          const SizedBox(height: NexusSpacing.md),
          if (state.ruleProviders.value.isNotEmpty) ...[
            _RuleProvidersPanel(),
            const SizedBox(height: NexusSpacing.md),
          ],
          Expanded(
            child: rules.isEmpty
                ? NexusEmptyState(
                    icon: LucideIcons.listOrdered,
                    title: '暂无规则',
                    subtitle: state.status.value == ClashStatus.connected
                        ? '当前配置没有路由规则。'
                        : '连接核心后此处显示当前的路由规则表。',
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: NexusSpacing.xs),
                    itemBuilder: (context, index) =>
                        _RuleRow(rule: filtered[index]),
                  ),
          ),
        ],
      );
    });
  }

  List<String> _distinctTypes(List<ClashRule> rules) {
    final types = <String>{};
    for (final rule in rules) {
      if (rule.type.isNotEmpty) types.add(rule.type);
    }
    final sorted = types.toList()..sort();
    return sorted.length > 1 ? sorted : const [];
  }

  List<ClashRule> _filtered(List<ClashRule> rules) {
    final query = _searchController.text.toLowerCase().trim();
    return rules.where((rule) {
      if (_typeFilter != null && rule.type != _typeFilter) return false;
      if (query.isEmpty) return true;
      return rule.type.toLowerCase().contains(query) ||
          rule.payload.toLowerCase().contains(query) ||
          rule.proxy.toLowerCase().contains(query);
    }).toList();
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
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

/// One rule entry: type + payload on the left, target proxy on the right.
class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final ClashRule rule;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 150,
            child: Text(
              rule.type,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              rule.payload,
              style: NexusTypography.bodyMd,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Text(
            rule.proxy,
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// External rule providers panel with per-provider update actions.
class _RuleProvidersPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final state = ClashState.instance;
      final providers = state.ruleProviders.value;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('规则提供者', style: NexusTypography.headlineSm),
          const SizedBox(height: NexusSpacing.sm),
          for (final provider in providers)
            Container(
              margin: const EdgeInsets.only(bottom: NexusSpacing.xs),
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.md,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: colorScheme.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.border),
              ),
              child: Row(
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
                    label: provider.behavior.isEmpty
                        ? provider.vehicleType
                        : '${provider.behavior} · ${provider.ruleCount}',
                    backgroundColor: colorScheme.primary.withValues(alpha: 0.1),
                    foregroundColor: colorScheme.primary,
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  SizedBox(
                    width: 140,
                    child: Text(
                      provider.updatedAt != null
                          ? '更新于 ${DateFormat('MM-dd HH:mm').format(provider.updatedAt!)}'
                          : '从未更新',
                      style: NexusTypography.labelMd.copyWith(
                        color: colorScheme.mutedForeground,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  state.updatingProviders.value.contains(provider.name)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(size: 12),
                        )
                      : provider.canUpdate
                          ? IconButton.ghost(
                              icon: const Icon(
                                LucideIcons.refreshCw,
                                size: 15,
                              ),
                              onPressed: () =>
                                  state.updateRuleProvider(provider.name),
                            )
                          : const SizedBox(width: 30),
                ],
              ),
            ),
        ],
      );
    });
  }
}
