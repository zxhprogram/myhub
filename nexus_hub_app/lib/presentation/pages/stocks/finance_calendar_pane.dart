import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/finance_calendar_model.dart';
import '../../../data/services/finance_calendar_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// Weekly financial-calendar pane backed by rl.fx678.com (汇通财经周历).
class FinanceCalendarPane extends StatefulWidget {
  const FinanceCalendarPane({super.key});

  @override
  State<FinanceCalendarPane> createState() => _FinanceCalendarPaneState();
}

class _FinanceCalendarPaneState extends State<FinanceCalendarPane> {
  final _service = FinanceCalendarService();

  List<FinanceCalendarDay> _days = const [];
  int _selectedDay = 0;
  bool _isLoading = true;
  bool _hasError = false;
  bool _onlyImportant = false;

  /// Monotonic request counter; completions of superseded loads never
  /// update the state.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => _guard(_service.fetchWeek());

  Future<void> _refresh() => _guard(_service.refreshWeek());

  Future<void> _guard(Future<List<FinanceCalendarDay>> future) async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final days = await future;
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _days = days;
        _selectedDay = _indexOfToday(days);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  int _indexOfToday(List<FinanceCalendarDay> days) {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final index = days.indexWhere((d) => d.dateLabel == today);
    return index >= 0 ? index : 0;
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: NexusSpacing.md),
        if (!_isLoading && !_hasError && _days.isNotEmpty) ...[
          _buildDaySelector(context),
          const SizedBox(height: NexusSpacing.md),
        ],
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final range = _days.length >= 2
        ? '${_days.first.dateLabel} ~ ${_days.last.dateLabel}'
        : '';
    return Row(
      children: [
        Text('财经周历', style: NexusTypography.headlineSm),
        const SizedBox(width: NexusSpacing.sm),
        if (range.isNotEmpty)
          Text(
            range,
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        const Spacer(),
        _filterChip(
          context,
          label: '只看重要',
          selected: _onlyImportant,
          onTap: () => setState(() => _onlyImportant = !_onlyImportant),
        ),
        const SizedBox(width: NexusSpacing.md),
        NexusButton(
          label: '刷新',
          icon: Icons.refresh,
          variant: NexusButtonVariant.outlined,
          isLoading: _isLoading,
          onPressed: _refresh,
        ),
      ],
    );
  }

  Widget _buildDaySelector(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _days.length,
        separatorBuilder: (_, _) => const SizedBox(width: NexusSpacing.sm),
        itemBuilder: (context, index) {
          final day = _days[index];
          return _DayChip(
            day: day,
            selected: index == _selectedDay,
            onTap: () => setState(() => _selectedDay = index),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (_hasError) {
      return NexusEmptyState(
        icon: Icons.cloud_off,
        title: '周历加载失败',
        subtitle: '请检查网络后重试',
        action: NexusButton(
          label: '重试',
          icon: Icons.refresh,
          variant: NexusButtonVariant.outlined,
          onPressed: _load,
        ),
      );
    }

    if (_days.isEmpty) {
      return const NexusEmptyState(
        icon: Icons.event_busy,
        title: '本周暂无财经数据',
      );
    }

    final day = _days[_selectedDay.clamp(0, _days.length - 1)];
    final events = _onlyImportant
        ? day.events.where((e) => e.isImportant).toList()
        : day.events;

    if (events.isEmpty) {
      return NexusEmptyState(
        icon: Icons.event_available,
        title: '${day.weekday}（${day.dateLabel}）暂无${_onlyImportant ? '重要' : ''}数据',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: NexusSpacing.lg),
        itemCount: events.length,
        separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.xs),
        itemBuilder: (context, index) =>
            _CalendarEventCard(event: events[index], onOpen: _openInBrowser),
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primary : Colors.transparent,
      borderRadius: NexusRadii.fullRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.fullRadius,
        hoverColor: selected
            ? null
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.fullRadius,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Selectable weekday chip; carries the date and important-event count.
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final FinanceCalendarDay day;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final importantCount =
        day.events.where((e) => e.isImportant).length;
    final parts = day.dateLabel.split('-');
    final mmdd = parts.length == 3 ? '${parts[1]}/${parts[2]}' : day.dateLabel;

    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final isToday = day.dateLabel == today;

    return Material(
      color: selected
          ? colorScheme.primary
          : colorScheme.surfaceContainerLowest,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.mdRadius,
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: NexusSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.mdRadius,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? '今天' : day.weekday,
                    style: NexusTypography.labelMd.copyWith(
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (importantCount > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.onPrimary.withValues(alpha: 0.25)
                            : NexusColors.stockDown.withValues(alpha: 0.12),
                        borderRadius: NexusRadii.fullRadius,
                      ),
                      child: Text(
                        '$importantCount',
                        style: NexusTypography.labelSm.copyWith(
                          color: selected
                              ? colorScheme.onPrimary
                              : NexusColors.stockDown,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                mmdd,
                style: NexusTypography.labelSm.copyWith(
                  color: selected
                      ? colorScheme.onPrimary.withValues(alpha: 0.8)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One calendar row: time, country badge, indicator name and the
/// previous / survey / actual value triplet.
class _CalendarEventCard extends StatelessWidget {
  const _CalendarEventCard({required this.event, required this.onOpen});

  final FinanceCalendarEvent event;
  final void Function(String url) onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: NexusRadii.lgRadius,
      child: InkWell(
        onTap: event.detailUrl.isEmpty ? null : () => onOpen(event.detailUrl),
        borderRadius: NexusRadii.lgRadius,
        child: Container(
          padding: const EdgeInsets.all(NexusSpacing.md),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.lgRadius,
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      event.time,
                      style: NexusTypography.labelMd.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.xs),
                  if (event.countryName.isNotEmpty) ...[
                    _CountryBadge(label: event.countryName),
                    const SizedBox(width: NexusSpacing.sm),
                  ],
                  Expanded(
                    child: Text(
                      event.name,
                      style: NexusTypography.labelMd.copyWith(
                        fontWeight: event.isImportant
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: event.isImportant
                            ? NexusColors.stockDown
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (event.isImportant) ...[
                    const SizedBox(width: NexusSpacing.sm),
                    _ImportanceBadge(),
                  ],
                  if (event.isKeyEvent) ...[
                    const SizedBox(width: NexusSpacing.sm),
                    _KeyEventBadge(),
                  ],
                  const SizedBox(width: NexusSpacing.sm),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(left: 44 + NexusSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: _ValueColumn(
                        label: '前值',
                        value: event.previousValue,
                      ),
                    ),
                    Expanded(
                      child: _ValueColumn(
                        label: '预测值',
                        value: event.surveyValue,
                      ),
                    ),
                    Expanded(
                      child: _ValueColumn(
                        label: '公布值',
                        value: event.actualValue,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueColumn extends StatelessWidget {
  const _ValueColumn({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasValue = value.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          hasValue ? value : (highlight ? '待公布' : '—'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.bodyMd.copyWith(
            fontWeight: highlight && hasValue ? FontWeight.w700 : FontWeight.w500,
            color: !hasValue
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                : highlight
                    ? colorScheme.primary
                    : colorScheme.onSurface,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CountryBadge extends StatelessWidget {
  const _CountryBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Text(
        label,
        style: NexusTypography.labelSm.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ImportanceBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: NexusColors.stockDown.withValues(alpha: 0.12),
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Text(
        '高',
        style: NexusTypography.labelSm.copyWith(
          color: NexusColors.stockDown,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _KeyEventBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.secondary.withValues(alpha: 0.12),
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Text(
        '事件',
        style: NexusTypography.labelSm.copyWith(
          color: colorScheme.secondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
