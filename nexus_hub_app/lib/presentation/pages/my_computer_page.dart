

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../data/models/key_stat_model.dart';
import '../../data/models/network_traffic_model.dart';
import '../../data/repositories/key_stats_repository.dart';
import '../../data/repositories/network_traffic_repository.dart';
import '../../data/services/input_hook_service.dart';
import '../../data/services/network_monitor_service.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

/// Aggregation window used by the network statistics tab.
enum _TrafficRange { today, week, month, all }

/// Page that displays real-time keyboard and mouse state using the Windows
/// input hook DLL, along with persistent key press statistics.
class MyComputerPage extends StatefulWidget {
  const MyComputerPage({super.key});

  @override
  State<MyComputerPage> createState() => _MyComputerPageState();
}

class _MyComputerPageState extends State<MyComputerPage> {
  final _service = InputHookService.instance;
  bool _initialized = false;
  Timer? _pollTimer;

  // Tracked state for display
  bool _mouseLeft = false;
  bool _mouseRight = false;
  bool _mouseMiddle = false;
  int _mouseX = 0;
  int _mouseY = 0;
  int _scrollDelta = 0;

  // Tab state
  int _selectedTab = 0;

  // Stats state
  DailyKeyStats? _dailyStats;
  DateTime _selectedDate = DateTime.now();
  List<String> _availableDates = [];

  // Network live state
  Timer? _netTimer;
  DateTime _lastStatsLoad = DateTime.now();
  final List<double> _liveSamples = [];

  // Network statistics state
  _TrafficRange _selectedRange = _TrafficRange.today;
  DateTime _trafficDay = DateTime.now();
  NetworkTrafficSummary? _trafficSummary;
  List<DailyTraffic> _dailyTotals = [];
  List<HourlyTraffic> _hourlyTotals = [];
  int _todayRecv = 0;
  int _todaySent = 0;

  @override
  void initState() {
    super.initState();
    _initialized = _service.initialize();
    if (_initialized) {
      _pollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        _pollState();
      });
    }
    // Network monitor is started app-wide in main(); calling again is a no-op
    // but keeps the service alive when the page is opened in isolation.
    NetworkMonitorService.instance.start();
    _netTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollNetwork();
    });
    _loadStats();
    _loadNetworkStats();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _netTimer?.cancel();
    super.dispose();
  }

  void _pollState() {
    // Key press recording is handled app-wide by InputHookService.start()
    // (invoked in main); this poll only refreshes the live mouse display.
    final x = _service.mouseX;
    final y = _service.mouseY;
    final left = _service.isMouseButtonDown(0);
    final right = _service.isMouseButtonDown(1);
    final middle = _service.isMouseButtonDown(2);
    final scroll = _service.scrollDelta;
    _service.resetScrollDelta();

    setState(() {
      _mouseX = x;
      _mouseY = y;
      _mouseLeft = left;
      _mouseRight = right;
      _mouseMiddle = middle;
      _scrollDelta += scroll;
    });
  }

  Future<void> _loadStats() async {
    final dates = await KeyStatsRepository.getAvailableDates();
    final stats = await KeyStatsRepository.getStatsForDate(_selectedDate);
    if (mounted) {
      setState(() {
        _availableDates = dates;
        _dailyStats = stats;
      });
    }
  }

  Future<void> _selectDate(DateTime date) async {
    setState(() {
      _selectedDate = date;
    });
    await _loadStats();
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // ==================== Network traffic state ====================

  /// Refresh live network samples every second and reload persisted stats
  /// roughly once a minute so recorded totals stay current.
  void _pollNetwork() {
    final service = NetworkMonitorService.instance;
    if (!service.isRunning) return;

    if (DateTime.now().difference(_lastStatsLoad) >=
        const Duration(seconds: 60)) {
      _lastStatsLoad = DateTime.now();
      _loadNetworkStats();
    }

    if (_selectedTab != 0) return;
    _liveSamples.add((service.recvSpeed + service.sentSpeed).toDouble());
    if (_liveSamples.length > 60) _liveSamples.removeAt(0);
    if (mounted) setState(() {});
  }

  Future<void> _loadNetworkStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final summary = await NetworkTrafficRepository.getSummary();

    DateTime? rangeStart;
    switch (_selectedRange) {
      case _TrafficRange.today:
        rangeStart = todayStart;
        break;
      case _TrafficRange.week:
        rangeStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));
        break;
      case _TrafficRange.month:
        rangeStart = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 29));
        break;
      case _TrafficRange.all:
        rangeStart = null;
        break;
    }

    final daily = await NetworkTrafficRepository.getDailyTotals(
      start: rangeStart,
      end: null,
    );
    final hourly = await NetworkTrafficRepository.getHourlyTotals(_trafficDay);

    var todayRecv = 0;
    var todaySent = 0;
    for (final d in daily) {
      if (d.date.year == todayStart.year &&
          d.date.month == todayStart.month &&
          d.date.day == todayStart.day) {
        todayRecv += d.recvBytes;
        todaySent += d.sentBytes;
      }
    }

    if (!mounted) return;
    setState(() {
      _trafficSummary = summary;
      _dailyTotals = daily;
      _hourlyTotals = hourly;
      _todayRecv = todayRecv;
      _todaySent = todaySent;
    });
  }

  void _selectTrafficRange(_TrafficRange range) {
    setState(() => _selectedRange = range);
    _loadNetworkStats();
  }

  Future<void> _selectTrafficDay(DateTime day) async {
    setState(() => _trafficDay = day);
    await _loadNetworkStats();
  }

  /// shadcn date-picker overlay returning the picked day (or null).
  Future<DateTime?> _pickDate(DateTime initial) async {
    DateTime? picked;
    await showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (ctx) => AlertDialog(
          content: DatePickerDialog(
            initialViewType: CalendarViewType.date,
            selectionMode: CalendarSelectionMode.single,
            initialValue: SingleCalendarValue(initial),
            onChanged: (value) {
              if (value is SingleCalendarValue) {
                picked = value.date;
              }
            },
          ),
          actions: [
            Button.text(
              onPressed: () => closeOverlay<bool>(ctx, false),
              child: const Text('取消'),
            ),
            Button.primary(
              onPressed: () => closeOverlay<bool>(ctx, true),
              child: const Text('选择'),
            ),
          ],
        ),
      ),
    ).future;
    return picked;
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My Computer', style: NexusTypography.headlineXl),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            _selectedTab == 0
                ? 'Real-time keyboard, mouse and network monitor'
                : _selectedTab == 1
                ? 'Key press statistics with date filtering'
                : 'Network traffic statistics with time filtering',
            style: NexusTypography.bodyMd.copyWith(
              color: Theme.of(context).colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
      child: _initialized ? _buildWithTabs() : _buildUnavailable(),
    );
  }

  Widget _buildUnavailable() {
    return NexusCard(
      child: SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.triangleAlert,
                size: 48,
                color: Theme.of(context).colorScheme.mutedForeground.withValues(alpha: 0.4),
              ),
              const SizedBox(height: NexusSpacing.md),
              Text(
                'Input Hook DLL not available',
                style: NexusTypography.headlineSm.copyWith(
                  color: Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
              Text(
                'This feature requires the input_hook.dll to be installed.\n'
                    'Please run the application on Windows with the DLL present.',
                textAlign: TextAlign.center,
                style: NexusTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.mutedForeground.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWithTabs() {
    const tabs = <(int, IconData, String)>[
      (0, LucideIcons.heartPulse, 'Live Monitor'),
      (1, LucideIcons.chartColumn, 'Key Statistics'),
      (2, LucideIcons.network, 'Network Statistics'),
    ];
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.muted,
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i > 0)
                  SizedBox(
                    height: 24,
                    child: VerticalDivider(
                      width: 1,
                      color: Theme.of(context).colorScheme.border.withValues(alpha: 0.3),
                    ),
                  ),
                _buildTab(tabs[i].$1, tabs[i].$2, tabs[i].$3),
              ],
            ],
          ),
        ),
        const SizedBox(height: NexusSpacing.md),
        Expanded(
          child: switch (_selectedTab) {
            0 => _buildContent(),
            1 => _buildStatsContent(),
            _ => _buildNetworkStatsContent(),
          },
        ),
      ],
    );
  }

  Widget _buildTab(int index, IconData icon, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: NexusSpacing.sm,
            horizontal: NexusSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.foreground.withValues(alpha: 0.1)
                : const Color(0x00000000),
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? Theme.of(context).colorScheme.foreground
                    : Theme.of(context).colorScheme.mutedForeground,
              ),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                label,
                style: NexusTypography.labelMd.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? Theme.of(context).colorScheme.foreground
                      : Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== Live Monitor Tab ====================

  Widget _buildContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildMouseSection(),
          const SizedBox(height: NexusSpacing.md),
          _buildNetworkSection(),
        ],
      ),
    );
  }

  Widget _buildMouseSection() {
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.mouse, size: 20, color: Theme.of(context).colorScheme.foreground),
                const SizedBox(width: NexusSpacing.sm),
                Text('Mouse', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.lg),
            // Position
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    icon: LucideIcons.crosshair,
                    label: 'Position',
                    value: '($_mouseX, $_mouseY)',
                  ),
                ),
                const SizedBox(width: NexusSpacing.md),
                // Scroll
                Expanded(
                  child: _buildMetricCard(
                    icon: LucideIcons.arrowUpDown,
                    label: 'Scroll Delta',
                    value: '${_scrollDelta >= 0 ? '+' : ''}$_scrollDelta',
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            // Buttons
            Text(
              'Buttons',
              style: NexusTypography.labelMd.copyWith(
                color: Theme.of(context).colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Row(
              children: [
                _buildButtonIndicator('Left', _mouseLeft),
                const SizedBox(width: NexusSpacing.sm),
                _buildButtonIndicator('Middle', _mouseMiddle),
                const SizedBox(width: NexusSpacing.sm),
                _buildButtonIndicator('Right', _mouseRight),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.muted,
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(
          color: Theme.of(context).colorScheme.border.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.mutedForeground),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: NexusTypography.labelSm.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
                Text(
                  value,
                  style: NexusTypography.headlineSm.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtonIndicator(String label, bool pressed) {
    final color = pressed ? NexusColors.stockUp : Theme.of(context).colorScheme.mutedForeground;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: NexusSpacing.sm,
          horizontal: NexusSpacing.md,
        ),
        decoration: BoxDecoration(
          color: pressed
              ? color.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.muted,
          borderRadius: NexusRadii.mdRadius,
          border: Border.all(
            color: pressed
                ? color.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.border.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(
              label,
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w600,
                color: pressed ? color : Theme.of(context).colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSection() {
    final service = NetworkMonitorService.instance;
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.network,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Text('Network Traffic', style: NexusTypography.headlineSm),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: service.isRunning
                        ? NexusColors.stockUp.withValues(alpha: 0.12)
                        : NexusColors.stockDown.withValues(alpha: 0.12),
                    borderRadius: NexusRadii.fullRadius,
                  ),
                  child: Text(
                    service.isRunning ? 'Live' : 'Offline',
                    style: NexusTypography.labelSm.copyWith(
                      color: service.isRunning
                          ? NexusColors.stockUp
                          : NexusColors.stockDown,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.lg),
            if (!service.isRunning)
              SizedBox(
                height: 140,
                child: Center(
                  child: Text(
                    'network_monitor.dll not available',
                    style: NexusTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.mutedForeground,
                    ),
                  ),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      icon: LucideIcons.download,
                      label: 'Download Speed',
                      value: formatBytes(service.recvSpeed, perSecond: true),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(
                    child: _buildMetricCard(
                      icon: LucideIcons.upload,
                      label: 'Upload Speed',
                      value: formatBytes(service.sentSpeed, perSecond: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      icon: LucideIcons.hardDrive,
                      label: 'Session Downloaded',
                      value: formatBytes(service.totalRecv),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(
                    child: _buildMetricCard(
                      icon: LucideIcons.cloudUpload,
                      label: 'Session Uploaded',
                      value: formatBytes(service.totalSent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      icon: LucideIcons.calendarCheck,
                      label: "Today's Download",
                      value: formatBytes(_todayRecv),
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(
                    child: _buildMetricCard(
                      icon: LucideIcons.calendarCheck,
                      label: "Today's Upload",
                      value: formatBytes(_todaySent),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: NexusSpacing.md),
              Text(
                'Traffic Speed (last 60 seconds)',
                style: NexusTypography.labelMd.copyWith(
                  color: Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
              SizedBox(height: 120, child: _buildLiveMiniChart()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMiniChart() {
    final samples = _liveSamples;
    if (samples.length < 2) {
      return Center(
        child: Text(
          'Collecting live traffic samples…',
          style: NexusTypography.labelMd.copyWith(
            color: Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
      );
    }
    var maxV = 1.0;
    for (final s in samples) {
      if (s > maxV) maxV = s;
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (samples.length - 1).toDouble(),
        minY: 0,
        maxY: maxV * 1.15,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < samples.length; i++)
                FlSpot(i.toDouble(), samples[i]),
            ],
            color: Theme.of(context).colorScheme.primary,
            isCurved: true,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            ),
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

  // ==================== Network Statistics Tab ====================

  Widget _buildNetworkStatsContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildNetworkSummaryCard(),
          const SizedBox(height: NexusSpacing.md),
          _buildRangeSelector(),
          const SizedBox(height: NexusSpacing.md),
          _buildDailyTrafficCard(),
          const SizedBox(height: NexusSpacing.md),
          _buildHourlyDetailCard(),
          const SizedBox(height: NexusSpacing.md),
          _buildDailyDetailCard(),
        ],
      ),
    );
  }

  Widget _buildNetworkSummaryCard() {
    final s = _trafficSummary;
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.network, size: 20, color: Theme.of(context).colorScheme.foreground),
                const SizedBox(width: NexusSpacing.sm),
                Text('Traffic Summary', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            Wrap(
              spacing: NexusSpacing.md,
              runSpacing: NexusSpacing.md,
              children: [
                _buildTrafficMetric(
                  'Total Downloaded',
                  formatBytes(s?.totalRecv ?? 0),
                  LucideIcons.download,
                  Theme.of(context).colorScheme.primary,
                ),
                _buildTrafficMetric(
                  'Total Uploaded',
                  formatBytes(s?.totalSent ?? 0),
                  LucideIcons.upload,
                  Theme.of(context).colorScheme.foreground,
                ),
                _buildTrafficMetric(
                  'Total Combined',
                  formatBytes(s?.totalBytes ?? 0),
                  LucideIcons.arrowUpDown,
                  Theme.of(context).colorScheme.foreground,
                ),
                _buildTrafficMetric(
                  'Records',
                  '${s?.recordCount ?? 0} minutes',
                  LucideIcons.clock,
                  NexusColors.stockUp,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficMetric(
      String label,
      String value,
      IconData icon,
      Color color,
      ) {
    return SizedBox(
      width: 220,
      child: Container(
        padding: const EdgeInsets.all(NexusSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.muted,
          borderRadius: NexusRadii.mdRadius,
          border: Border.all(
            color: Theme.of(context).colorScheme.border.withValues(alpha: 0.15),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: NexusSpacing.xs),
                Text(
                  label,
                  style: NexusTypography.labelSm.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              value,
              style: NexusTypography.headlineSm.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeSelector() {
    const ranges = <(_TrafficRange, String)>[
      (_TrafficRange.today, 'Today'),
      (_TrafficRange.week, '7 Days'),
      (_TrafficRange.month, '30 Days'),
      (_TrafficRange.all, 'All Time'),
    ];
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.md),
        child: Wrap(
          spacing: NexusSpacing.sm,
          runSpacing: NexusSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.calendarRange,
                  size: 18,
                  color: Theme.of(context).colorScheme.mutedForeground,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Text('Period', style: NexusTypography.labelMd),
              ],
            ),
            for (final (range, label) in ranges) _buildRangeChip(range, label),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeChip(_TrafficRange range, String label) {
    final isSelected = _selectedRange == range;
    return GestureDetector(
      onTap: () => _selectTrafficRange(range),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.foreground.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.muted,
          borderRadius: NexusRadii.mdRadius,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.foreground.withValues(alpha: 0.3)
                : Theme.of(context).colorScheme.border.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: NexusTypography.labelMd.copyWith(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? Theme.of(context).colorScheme.foreground
                : Theme.of(context).colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }

  Widget _buildDailyTrafficCard() {
    final data = _dailyTotals;
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.chartColumn, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('Daily Traffic', style: NexusTypography.headlineSm),
                const Spacer(),
                _buildTrafficLegend(),
              ],
            ),
            const SizedBox(height: NexusSpacing.lg),
            if (data.isEmpty)
              _buildChartEmpty('No traffic recorded in this period')
            else
              SizedBox(height: 240, child: _buildDailyBarChart(data)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyBarChart(List<DailyTraffic> data) {
    var maxBytes = 0;
    for (final d in data) {
      if (d.totalBytes > maxBytes) maxBytes = d.totalBytes;
    }
    final maxY = (maxBytes <= 0 ? 1 : maxBytes * 1.2).toDouble();
    final labelStep = (data.length / 8).ceil().clamp(1, data.length);

    return BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final d = data[group.x];
              final label = rodIndex == 0 ? 'Download' : 'Upload';
              return BarTooltipItem(
                '${_formatShortDate(d.date)}\n$label '
                    '${formatBytes(rod.toY.toInt())}',
                const TextStyle(color: const Color(0xFFFFFFFF), fontSize: 11),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).colorScheme.border.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) => Text(
                formatBytes(value.toInt()),
                style: NexusTypography.labelSm.copyWith(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length || i % labelStep != 0) {
                  return const SizedBox.shrink();
                }
                final d = data[i].date;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${d.month}/${d.day}',
                    style: NexusTypography.labelSm.copyWith(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.mutedForeground,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].recvBytes.toDouble(),
                  color: Theme.of(context).colorScheme.primary,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
                BarChartRodData(
                  toY: data[i].sentBytes.toDouble(),
                  color: Theme.of(context).colorScheme.foreground,
                  width: 8,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHourlyDetailCard() {
    final data = _hourlyTotals;
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.clock, size: 20, color: Theme.of(context).colorScheme.foreground),
                const SizedBox(width: NexusSpacing.sm),
                Text('Hourly Detail', style: NexusTypography.headlineSm),
                const Spacer(),
                _buildTrafficLegend(),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            _buildTrafficDaySelector(),
            const SizedBox(height: NexusSpacing.md),
            if (data.every((h) => h.totalBytes == 0))
              _buildChartEmpty(
                'No traffic recorded on ${_formatDate(_trafficDay)}',
              )
            else
              SizedBox(height: 200, child: _buildHourlyLineChart(data)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrafficDaySelector() {
    final isToday = _formatDate(_trafficDay) == _formatDate(DateTime.now());
    return Row(
      children: [
        IconButton.ghost(
  onPressed: () =>
              _selectTrafficDay(_trafficDay.subtract(const Duration(days: 1))),
  icon: const Icon(RadixIcons.chevronLeft),
),
        Expanded(
          child: GestureDetector(
            onTap: () async {
              final picked = await _pickDate(_trafficDay);
              if (picked != null) _selectTrafficDay(picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: NexusSpacing.sm,
                horizontal: NexusSpacing.md,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.muted,
                borderRadius: NexusRadii.mdRadius,
                border: Border.all(
                  color: Theme.of(context).colorScheme.border.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDate(_trafficDay),
                    style: NexusTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                   Icon(
                    RadixIcons.chevronDown,
                    size: 20,
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton.ghost(
  onPressed: isToday
              ? null
              : () =>
              _selectTrafficDay(_trafficDay.add(const Duration(days: 1))),
  icon: const Icon(RadixIcons.chevronRight),
),
        Button.text(
  onPressed: () => _selectTrafficDay(DateTime.now()),
  child: const Text('Today'),
),
      ],
    );
  }

  Widget _buildHourlyLineChart(List<HourlyTraffic> data) {
    var maxBytes = 0;
    for (final h in data) {
      if (h.totalBytes > maxBytes) maxBytes = h.totalBytes;
    }
    final maxY = (maxBytes <= 0 ? 1 : maxBytes * 1.2).toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 23,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var h = 0; h < 24; h++)
                FlSpot(h.toDouble(), data[h].recvBytes.toDouble()),
            ],
            color: Theme.of(context).colorScheme.primary,
            isCurved: true,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
          LineChartBarData(
            spots: [
              for (var h = 0; h < 24; h++)
                FlSpot(h.toDouble(), data[h].sentBytes.toDouble()),
            ],
            color: Theme.of(context).colorScheme.foreground,
            isCurved: true,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.foreground.withValues(alpha: 0.15),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).colorScheme.border.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              getTitlesWidget: (value, meta) => Text(
                formatBytes(value.toInt()),
                style: NexusTypography.labelSm.copyWith(
                  fontSize: 9,
                  color: Theme.of(context).colorScheme.mutedForeground,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 3,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${value.toInt()}h',
                  style: NexusTypography.labelSm.copyWith(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDailyDetailCard() {
    final data = _dailyTotals.reversed.toList();
    if (data.isEmpty) return const SizedBox.shrink();
    var maxBytes = 0;
    for (final d in data) {
      if (d.totalBytes > maxBytes) maxBytes = d.totalBytes;
    }
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.listChecks, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('Daily Breakdown', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            ...data.map((d) => _buildDailyRow(d, maxBytes)),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyRow(DailyTraffic d, int maxBytes) {
    final ratio = maxBytes > 0 ? d.totalBytes / maxBytes : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              '${d.date.month}/${d.date.day}',
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.foreground,
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: ClipRRect(
              borderRadius: NexusRadii.smRadius,
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 14,
                backgroundColor: Theme.of(context).colorScheme.muted,
                color: Color.lerp(
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  Theme.of(context).colorScheme.primary,
                  ratio,
                ),
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '↓ ${formatBytes(d.recvBytes)}',
                  style: NexusTypography.labelSm.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '↑ ${formatBytes(d.sentBytes)}',
                  style: NexusTypography.labelSm.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLegendDot(Theme.of(context).colorScheme.primary, 'Download'),
        const SizedBox(width: NexusSpacing.md),
        _buildLegendDot(Theme.of(context).colorScheme.foreground, 'Upload'),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: NexusRadii.smRadius,
          ),
        ),
        const SizedBox(width: NexusSpacing.xs),
        Text(label, style: NexusTypography.labelSm),
      ],
    );
  }

  Widget _buildChartEmpty(String message) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.network,
              size: 40,
              color: Theme.of(context).colorScheme.mutedForeground.withValues(alpha: 0.25),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: NexusTypography.bodyMd.copyWith(
                color: Theme.of(context).colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatShortDate(DateTime date) => '${date.month}/${date.day}';

  // ==================== Key Statistics Tab ====================

  Widget _buildStatsContent() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildDateSelector(),
          const SizedBox(height: NexusSpacing.md),
          _buildKeyboardHeatmap(),
          const SizedBox(height: NexusSpacing.md),
          _buildStatsCard(),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.calendar,
                  size: 20,
                  color: Theme.of(context).colorScheme.foreground,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Text('Date', style: NexusTypography.headlineSm),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            // Date picker row
            Row(
              children: [
                // Previous day
                IconButton.ghost(
  onPressed: () {
                    final prev = _selectedDate.subtract(
                      const Duration(days: 1),
                    );
                    _selectDate(prev);
                  },
  icon: const Icon(RadixIcons.chevronLeft),
),
                // Date display + picker
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await _pickDate(_selectedDate);
                      if (picked != null) {
                        _selectDate(picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: NexusSpacing.sm,
                        horizontal: NexusSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.muted,
                        borderRadius: NexusRadii.mdRadius,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.border.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatDate(_selectedDate),
                            style: NexusTypography.bodyMd.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: NexusSpacing.sm),
                          Icon(
                            RadixIcons.chevronDown,
                            size: 20,
                            color: Theme.of(context).colorScheme.mutedForeground,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Next day (only if not today)
                IconButton.ghost(
  onPressed:
                  _formatDate(_selectedDate) != _formatDate(DateTime.now())
                      ? () {
                    final next = _selectedDate.add(
                      const Duration(days: 1),
                    );
                    _selectDate(next);
                  }
                      : null,
  icon: const Icon(RadixIcons.chevronRight),
),
                // Today
                Button.text(
  onPressed: () => _selectDate(DateTime.now()),
  child: const Text('Today'),
),
              ],
            ),
            // Available dates chips
            if (_availableDates.isNotEmpty) ...[
              const SizedBox(height: NexusSpacing.sm),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableDates.length,
                  separatorBuilder: (_, _) =>
                  const SizedBox(width: NexusSpacing.sm),
                  itemBuilder: (context, index) {
                    final date = _availableDates[index];
                    final isSelected = date == _formatDate(_selectedDate);
                    return GestureDetector(
                      onTap: () {
                        final parts = date.split('-');
                        _selectDate(
                          DateTime(
                            int.parse(parts[0]),
                            int.parse(parts[1]),
                            int.parse(parts[2]),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: NexusSpacing.md,
                          vertical: NexusSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.foreground.withValues(alpha: 0.1)
                              : Theme.of(context).colorScheme.muted,
                          borderRadius: NexusRadii.mdRadius,
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.foreground.withValues(alpha: 0.3)
                                : Theme.of(context).colorScheme.border.withValues(
                              alpha: 0.1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            date,
                            style: NexusTypography.labelMd.copyWith(
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.foreground
                                  : Theme.of(context).colorScheme.mutedForeground,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboardHeatmap() {
    final stats = _dailyStats;
    var maxCount = 0;
    if (stats != null) {
      for (final row in _keyboardRows) {
        for (final key in row) {
          if (key.codes.isEmpty) continue;
          final count = key.codes
              .map((c) => stats.stats[c]?.pressCount ?? 0)
              .fold(0, (a, b) => a + b);
          if (count > maxCount) maxCount = count;
        }
      }
    }

    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.keyboard,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Text('Keyboard Heatmap', style: NexusTypography.headlineSm),
                const Spacer(),
                _buildHeatLegend(),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final unit = constraints.maxWidth / 15.0;
                return Column(
                  children: [
                    for (final row in _keyboardRows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            for (final key in row)
                              SizedBox(
                                width: key.width * unit,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                    vertical: 2,
                                  ),
                                  child: _buildKeyCap(key, stats, maxCount),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeatLegend() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Less',
          style: NexusTypography.labelSm.copyWith(
            fontSize: 9,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 4),
        for (var i = 0; i < 5; i++)
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: Color.lerp(
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                Theme.of(context).colorScheme.primary,
                i / 4,
              ),
              borderRadius: NexusRadii.smRadius,
            ),
          ),
        const SizedBox(width: 2),
        Text(
          'More',
          style: NexusTypography.labelSm.copyWith(
            fontSize: 9,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildKeyCap(_KeyDef key, DailyKeyStats? stats, int maxCount) {
    if (key.codes.isEmpty) return const SizedBox.shrink();
    final count = stats == null
        ? 0
        : key.codes
        .map((c) => stats.stats[c]?.pressCount ?? 0)
        .fold(0, (a, b) => a + b);
    final t = maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;

    final Color bg;
    final Color fg;
    if (count == 0) {
      bg = Theme.of(context).colorScheme.muted;
      fg = Theme.of(context).colorScheme.mutedForeground;
    } else {
      bg = Color.lerp(
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
        Theme.of(context).colorScheme.primary,
        t,
      )!;
      fg = t > 0.45 ? Theme.of(context).colorScheme.primaryForeground : Theme.of(context).colorScheme.foreground;
    }

    return Tooltip(
  tooltip: (context) => Text(count > 0 ? '${key.label} · $count' : key.label),
  child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: NexusRadii.smRadius,
          border: Border.all(
            color: Theme.of(context).colorScheme.border.withValues(alpha: 0.2),
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text(
          key.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: NexusTypography.labelSm.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
            fontSize: key.label.length > 4
                ? 8
                : (key.label.length > 1 ? 9 : 11),
            letterSpacing: 0,
          ),
        ),
      ),
);
  }

  Widget _buildStatsCard() {
    if (_dailyStats == null || _dailyStats!.stats.isEmpty) {
      return NexusCard(
        child: SizedBox(
          height: 200,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.chartColumn,
                  size: 48,
                  color: Theme.of(context).colorScheme.mutedForeground.withValues(alpha: 0.3),
                ),
                const SizedBox(height: NexusSpacing.md),
                Text(
                  'No key press data for this date',
                  style: NexusTypography.bodyMd.copyWith(
                    color: Theme.of(context).colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final stats = _dailyStats!;
    final sortedStats = stats.stats.values.toList()
      ..sort((a, b) => b.pressCount.compareTo(a.pressCount));

    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.chartColumn, size: 20, color: Theme.of(context).colorScheme.foreground),
                const SizedBox(width: NexusSpacing.sm),
                Text('Key Press Statistics', style: NexusTypography.headlineSm),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.md,
                    vertical: NexusSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.foreground.withValues(alpha: 0.1),
                    borderRadius: NexusRadii.mdRadius,
                  ),
                  child: Text(
                    'Total: ${stats.totalPresses}',
                    style: NexusTypography.labelMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NexusSpacing.lg),
            // Key stat rows
            ...sortedStats.asMap().entries.map(
                  (e) => _buildStatRow(e.value, e.key + 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(KeyStatModel stat, int rank) {
    final maxCount = _dailyStats!.stats.values.fold(
      0,
          (max, s) => s.pressCount > max ? s.pressCount : max,
    );
    final ratio = maxCount > 0 ? stat.pressCount / maxCount : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: NexusTypography.labelSm.copyWith(
                color: Theme.of(context).colorScheme.mutedForeground,
              ),
            ),
          ),
          // Key cap
          Container(
            width: 64,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.accent,
              borderRadius: NexusRadii.smRadius,
              border: Border.all(
                color: Theme.of(context).colorScheme.border.withValues(alpha: 0.2),
              ),
            ),
            child: Tooltip(
  tooltip: (context) => Text('0x${stat.keyCode.toRadixString(16).toUpperCase().padLeft(2, '0')}'),
  child: Text(
                stat.keyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.foreground,
                  fontSize: stat.keyName.length > 4 ? 9 : 11,
                  letterSpacing: 0,
                ),
              ),
),
          ),
          const SizedBox(width: NexusSpacing.sm),
          // Progress bar
          Expanded(
            child: ClipRRect(
              borderRadius: NexusRadii.smRadius,
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 18,
                backgroundColor: Theme.of(context).colorScheme.muted,
                color: Color.lerp(
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  Theme.of(context).colorScheme.primary,
                  ratio,
                ),
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          // Count
          SizedBox(
            width: 56,
            child: Text(
              '${stat.pressCount}',
              textAlign: TextAlign.right,
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Theme.of(context).colorScheme.foreground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Definition of a single key on the visual keyboard layout.
class _KeyDef {
  const _KeyDef(this.label, this.codes, {this.width = 1.0});

  final String label;

  /// All virtual key codes aggregated into this key cell.
  final List<int> codes;

  /// Width in key units (1.0 = standard key).
  final double width;
}

/// Visual keyboard layout; each row sums to 15 key units so the layout fills
/// the available card width uniformly.
const _keyboardRows = <List<_KeyDef>>[
  // Function key row
  [
    _KeyDef('Esc', [0x1B]),
    _KeyDef('', [], width: 0.5),
    _KeyDef('F1', [0x70]),
    _KeyDef('F2', [0x71]),
    _KeyDef('F3', [0x72]),
    _KeyDef('F4', [0x73]),
    _KeyDef('', [], width: 0.5),
    _KeyDef('F5', [0x74]),
    _KeyDef('F6', [0x75]),
    _KeyDef('F7', [0x76]),
    _KeyDef('F8', [0x77]),
    _KeyDef('', [], width: 0.5),
    _KeyDef('F9', [0x78]),
    _KeyDef('F10', [0x79]),
    _KeyDef('F11', [0x7A]),
    _KeyDef('F12', [0x7B]),
  ],
  // Number row
  [
    _KeyDef('`', [0xC0]),
    _KeyDef('1', [0x31]),
    _KeyDef('2', [0x32]),
    _KeyDef('3', [0x33]),
    _KeyDef('4', [0x34]),
    _KeyDef('5', [0x35]),
    _KeyDef('6', [0x36]),
    _KeyDef('7', [0x37]),
    _KeyDef('8', [0x38]),
    _KeyDef('9', [0x39]),
    _KeyDef('0', [0x30]),
    _KeyDef('-', [0xBD]),
    _KeyDef('=', [0xBB]),
    _KeyDef('⌫', [0x08], width: 2.0),
  ],
  // QWERTY row
  [
    _KeyDef('Tab', [0x09], width: 1.5),
    _KeyDef('Q', [0x51]),
    _KeyDef('W', [0x57]),
    _KeyDef('E', [0x45]),
    _KeyDef('R', [0x52]),
    _KeyDef('T', [0x54]),
    _KeyDef('Y', [0x59]),
    _KeyDef('U', [0x55]),
    _KeyDef('I', [0x49]),
    _KeyDef('O', [0x4F]),
    _KeyDef('P', [0x50]),
    _KeyDef('[', [0xDB]),
    _KeyDef(']', [0xDD]),
    _KeyDef('\\', [0xDC], width: 1.5),
  ],
  // ASDF row
  [
    _KeyDef('Caps', [0x14], width: 1.75),
    _KeyDef('A', [0x41]),
    _KeyDef('S', [0x53]),
    _KeyDef('D', [0x44]),
    _KeyDef('F', [0x46]),
    _KeyDef('G', [0x47]),
    _KeyDef('H', [0x48]),
    _KeyDef('J', [0x4A]),
    _KeyDef('K', [0x4B]),
    _KeyDef('L', [0x4C]),
    _KeyDef(';', [0xBA]),
    _KeyDef("'", [0xDE]),
    _KeyDef('Enter', [0x0D], width: 2.25),
  ],
  // ZXCV row
  [
    _KeyDef('Shift', [0xA0, 0x10, 0x2A], width: 2.25),
    _KeyDef('Z', [0x5A]),
    _KeyDef('X', [0x58]),
    _KeyDef('C', [0x43]),
    _KeyDef('V', [0x56]),
    _KeyDef('B', [0x42]),
    _KeyDef('N', [0x4E]),
    _KeyDef('M', [0x4D]),
    _KeyDef(',', [0xBC]),
    _KeyDef('.', [0xBE]),
    _KeyDef('/', [0xBF]),
    _KeyDef('Shift', [0xA1, 0x36], width: 2.75),
  ],
  // Space row
  [
    _KeyDef('Ctrl', [0xA2, 0x11, 0x1D], width: 1.25),
    _KeyDef('Win', [0x5B], width: 1.25),
    _KeyDef('Alt', [0xA4, 0x12, 0x38], width: 1.25),
    _KeyDef('Space', [0x20], width: 6.25),
    _KeyDef('Alt', [0xA5], width: 1.25),
    _KeyDef('Win', [0x5C], width: 1.25),
    _KeyDef('Menu', [0x5D], width: 1.25),
    _KeyDef('Ctrl', [0xA3], width: 1.25),
  ],
];
