import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../layout/page_scaffold.dart';
import 'stocks/eastmoney_stock_pane.dart';
import 'stocks/finance_calendar_pane.dart';
import 'stocks/fx678_news_pane.dart';

enum _StocksTab { markets, news, calendar }

class StocksPage extends StatefulWidget {
  const StocksPage({super.key});

  @override
  State<StocksPage> createState() => _StocksPageState();
}

class _StocksPageState extends State<StocksPage> {
  _StocksTab _tab = _StocksTab.markets;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTabSelector(context),
          const SizedBox(height: NexusSpacing.sm),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colorScheme.border.withValues(alpha: 0.6),
                ),
                borderRadius: NexusRadii.lgRadius,
              ),
              child: ClipRRect(
                borderRadius: NexusRadii.lgRadius,
                child: switch (_tab) {
                  _StocksTab.markets => const EastmoneyStockPane(),
                  _StocksTab.news => const Fx678NewsPane(),
                  _StocksTab.calendar => const FinanceCalendarPane(),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector(BuildContext context) {
    return Row(
      children: [
        _StocksTabChip(
          label: '市场行情',
          icon: LucideIcons.chartLine,
          isSelected: _tab == _StocksTab.markets,
          onTap: () => setState(() => _tab = _StocksTab.markets),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _StocksTabChip(
          label: '24小时快讯',
          icon: LucideIcons.zap,
          isSelected: _tab == _StocksTab.news,
          onTap: () => setState(() => _tab = _StocksTab.news),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _StocksTabChip(
          label: '财经周历',
          icon: LucideIcons.calendarDays,
          isSelected: _tab == _StocksTab.calendar,
          onTap: () => setState(() => _tab = _StocksTab.calendar),
        ),
      ],
    );
  }
}

/// Pill-style selectable chip for the 市场行情 / 24小时快讯 / 财经周历 tabs.
class _StocksTabChip extends StatelessWidget {
  const _StocksTabChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: NexusRadii.fullRadius,
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.4)
                : colorScheme.border.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.mutedForeground,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: NexusTypography.labelSm.copyWith(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
