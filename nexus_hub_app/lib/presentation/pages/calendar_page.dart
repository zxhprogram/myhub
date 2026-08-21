import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../utils/lunar_calendar.dart';
import '../layout/page_scaffold.dart';

/// Calendar application page with a month grid and lunar (Chinese
/// traditional) calendar annotations, including ganzhi year, zodiac and
/// traditional festivals.
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _focusedMonth;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _goToMonth(int delta) {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _focusedMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _selectDay(DateTime day, bool inCurrentMonth) {
    setState(() {
      _selectedDay = day;
      if (!inCurrentMonth) {
        _focusedMonth = DateTime(day.year, day.month);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Calendar', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                '月历视图 · 含农历、干支与节日',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          _MonthNav(
            month: _focusedMonth,
            onPrev: () => _goToMonth(-1),
            onNext: () => _goToMonth(1),
            onToday: _goToToday,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: _MonthGrid(
                    focusedMonth: _focusedMonth,
                    selectedDay: _selectedDay,
                    onSelect: _selectDay,
                  ),
                ),
                const SizedBox(width: NexusSpacing.lg),
                SizedBox(width: 300, child: _DetailPanel(day: _selectedDay)),
              ],
            );
          }
          return Column(
            children: [
              _DetailPanel(day: _selectedDay),
              const SizedBox(height: NexusSpacing.lg),
              Expanded(
                child: _MonthGrid(
                  focusedMonth: _focusedMonth,
                  selectedDay: _selectedDay,
                  onSelect: _selectDay,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Top-right month navigation controls.
class _MonthNav extends StatelessWidget {
  const _MonthNav({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _NavButton(icon: RadixIcons.chevronLeft, onTap: onPrev),
        const SizedBox(width: NexusSpacing.sm),
        SizedBox(
          width: 140,
          child: Text(
            '${month.year}年${month.month}月',
            textAlign: TextAlign.center,
            style: NexusTypography.headlineSm.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: NexusSpacing.sm),
        _NavButton(icon: RadixIcons.chevronRight, onTap: onNext),
        const SizedBox(width: NexusSpacing.md),
        GestureDetector(
  onTap: onToday,
  child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
              vertical: NexusSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: colorScheme.accent,
              borderRadius: NexusRadii.fullRadius,
            ),
            child: Text(
              '今天',
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
),
      ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: onTap,
  child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colorScheme.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: colorScheme.foreground),
      ),
);
  }
}

/// Month grid showing weekday headers and day cells with lunar labels.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.focusedMonth,
    required this.selectedDay,
    required this.onSelect,
  });

  final DateTime focusedMonth;
  final DateTime? selectedDay;
  final void Function(DateTime day, bool inCurrentMonth) onSelect;

  // Week starts on Monday for the Chinese calendar convention.
  static const List<String> _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cells = _buildCells();
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: NexusRadii.lgRadius,
        border: Border.all(color: colorScheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
                      child: Text(
                        w,
                        style: NexusTypography.labelMd.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Expanded(
            child: GridView.count(
              crossAxisCount: 7,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              childAspectRatio: 1,
              physics: const NeverScrollableScrollPhysics(),
              children: cells,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCells() {
    final month = focusedMonth;
    final firstDay = DateTime(month.year, month.month, 1);
    // DateTime.weekday: Monday = 1 .. Sunday = 7. Convert to Monday-first
    // column index (0..6).
    final leadingBlanks = firstDay.weekday - 1;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final total = leadingBlanks + daysInMonth;
    // Pad to fill complete weeks.
    final trailingBlanks = (7 - (total % 7)) % 7;

    final cells = <Widget>[];

    // Leading days from the previous month (rendered greyed out).
    final prevMonthDays = DateTime(month.year, month.month, 0).day;
    for (int i = leadingBlanks - 1; i >= 0; i--) {
      final day = DateTime(month.year, month.month - 1, prevMonthDays - i);
      cells.add(
        _DayCell(
          day: day,
          inCurrentMonth: false,
          isSelected: _isSelected(day),
          onSelect: onSelect,
        ),
      );
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final day = DateTime(month.year, month.month, d);
      cells.add(
        _DayCell(
          day: day,
          inCurrentMonth: true,
          isSelected: _isSelected(day),
          onSelect: onSelect,
        ),
      );
    }

    // Trailing days from next month.
    for (int d = 1; d <= trailingBlanks; d++) {
      final day = DateTime(month.year, month.month + 1, d);
      cells.add(
        _DayCell(
          day: day,
          inCurrentMonth: false,
          isSelected: _isSelected(day),
          onSelect: onSelect,
        ),
      );
    }
    return cells;
  }

  bool _isSelected(DateTime day) {
    final sel = selectedDay;
    if (sel == null) return false;
    return day.year == sel.year && day.month == sel.month && day.day == sel.day;
  }
}

/// A single day cell. Renders the Gregorian day number plus a short lunar
/// label, and highlights today / the selected day.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inCurrentMonth,
    required this.isSelected,
    required this.onSelect,
  });

  final DateTime day;
  final bool inCurrentMonth;
  final bool isSelected;
  final void Function(DateTime day, bool inCurrentMonth) onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    final lunar = solarToLunar(day);
    final lunarFest = lunar != null ? lunarFestival(lunar) : null;
    final solarFest = solarFestival(day);

    // Festival label takes priority for the small text; otherwise show the
    // lunar short label (month name on day 1, day name otherwise).
    final String subLabel;
    final Color subColor;
    if (lunarFest != null) {
      subLabel = lunarFest;
      subColor = colorScheme.secondary;
    } else if (solarFest != null && !isToday) {
      subLabel = solarFest;
      subColor = colorScheme.secondary;
    } else if (lunar != null) {
      subLabel = lunar.shortLabel;
      subColor = colorScheme.mutedForeground;
    } else {
      subLabel = '';
      subColor = colorScheme.mutedForeground;
    }

    final bg = isSelected
        ? colorScheme.secondary
        : isToday
        ? colorScheme.accent
        : const Color(0x00000000);

    return GestureDetector(
  onTap: () => onSelect(day, inCurrentMonth),
  child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: NexusRadii.mdRadius,
          border: isToday && !isSelected
              ? Border.all(color: colorScheme.secondary, width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: NexusTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? colorScheme.secondaryForeground
                    : inCurrentMonth
                    ? colorScheme.foreground
                    : colorScheme.border,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.labelSm.copyWith(
                fontSize: 10,
                letterSpacing: 0,
                color: isSelected
                    ? colorScheme.secondaryForeground.withValues(alpha: 0.9)
                    : subColor,
                fontWeight: lunarFest != null || solarFest != null
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
);
  }
}

/// Right-hand detail panel for the selected day.
class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.day});

  final DateTime? day;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = day ?? DateTime.now();
    final lunar = solarToLunar(selected);
    final weekday = _weekdaysFull[selected.weekday - 1];

    return Container(
      padding: const EdgeInsets.all(NexusSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.card,
        borderRadius: NexusRadii.lgRadius,
        border: Border.all(color: colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '所选日期',
            style: NexusTypography.labelSm.copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: NexusSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${selected.day}',
                style: NexusTypography.headlineXl.copyWith(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  height: 1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${selected.month}月 · $weekday',
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          Text(
            '${selected.year}年${selected.month}月${selected.day}日',
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: NexusSpacing.lg),
          Divider(height: 1, color: colorScheme.border),
          const SizedBox(height: NexusSpacing.lg),
          if (lunar != null) ...[
            _InfoRow(label: '农历', value: lunar.display),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(label: '干支', value: '${lunar.ganzhiYear}年'),
            const SizedBox(height: NexusSpacing.sm),
            _InfoRow(label: '生肖', value: '${lunar.zodiac}年'),
            const SizedBox(height: NexusSpacing.lg),
            _FestivalBadges(day: selected, lunar: lunar),
          ] else
            Text(
              '农历数据超出支持范围（1900-2099）',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
        ],
      ),
    );
  }

  static const List<String> _weekdaysFull = [
    '星期一',
    '星期二',
    '星期三',
    '星期四',
    '星期五',
    '星期六',
    '星期日',
  ];
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: NexusTypography.labelMd),
        Text(
          value,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _FestivalBadges extends StatelessWidget {
  const _FestivalBadges({required this.day, required this.lunar});

  final DateTime day;
  final LunarDate lunar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final festivals = <String>[];
    final lf = lunarFestival(lunar);
    if (lf != null) festivals.add(lf);
    final sf = solarFestival(day);
    if (sf != null) festivals.add(sf);

    if (festivals.isEmpty) {
      return Text(
        '今日无传统节日',
        style: NexusTypography.labelMd.copyWith(
          color: colorScheme.mutedForeground,
        ),
      );
    }

    return Wrap(
      spacing: NexusSpacing.xs,
      runSpacing: NexusSpacing.xs,
      children: [
        for (final f in festivals)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: colorScheme.secondary.withValues(alpha: 0.4),
              borderRadius: NexusRadii.fullRadius,
            ),
            child: Text(
              f,
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.secondaryForeground,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
      ],
    );
  }
}
