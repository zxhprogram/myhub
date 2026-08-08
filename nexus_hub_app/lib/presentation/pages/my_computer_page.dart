import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/key_stat_model.dart';
import '../../data/repositories/key_stats_repository.dart';
import '../../data/services/input_hook_service.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_card.dart';
import '../layout/page_scaffold.dart';

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
  final Set<int> _pressedKeys = {};
  bool _mouseLeft = false;
  bool _mouseRight = false;
  bool _mouseMiddle = false;
  int _mouseX = 0;
  int _mouseY = 0;
  int _scrollDelta = 0;

  // Key press detection
  final Set<int> _previousKeys = {};
  bool _firstPoll = true;

  // Tab state
  int _selectedTab = 0;

  // Stats state
  DailyKeyStats? _dailyStats;
  DateTime _selectedDate = DateTime.now();
  List<String> _availableDates = [];

  @override
  void initState() {
    super.initState();
    _initialized = _service.initialize();
    if (_initialized) {
      _pollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
        _pollState();
      });
    }
    _loadStats();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _service.dispose();
    super.dispose();
  }

  void _pollState() {
    // Poll keys
    final keys = <int>{};
    for (var code = 0; code < 256; code++) {
      if (_service.isKeyDown(code)) {
        keys.add(code);
      }
    }

    // Detect new key presses (skip first poll to avoid counting held keys)
    if (!_firstPoll) {
      for (final code in keys) {
        if (!_previousKeys.contains(code)) {
          KeyStatsRepository.recordKeyPress(code);
        }
      }
    }
    _firstPoll = false;
    _previousKeys.clear();
    _previousKeys.addAll(keys);

    // Poll mouse
    final x = _service.mouseX;
    final y = _service.mouseY;
    final left = _service.isMouseButtonDown(0);
    final right = _service.isMouseButtonDown(1);
    final middle = _service.isMouseButtonDown(2);
    final scroll = _service.scrollDelta;
    _service.resetScrollDelta();

    setState(() {
      _pressedKeys.clear();
      _pressedKeys.addAll(keys);
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
                ? 'Real-time keyboard and mouse input monitor'
                : 'Key press statistics with date filtering',
            style: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
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
                Icons.warning_amber_rounded,
                size: 48,
                color: NexusColors.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: NexusSpacing.md),
              Text(
                'Input Hook DLL not available',
                style: NexusTypography.headlineSm.copyWith(
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
              Text(
                'This feature requires the input_hook.dll to be installed.\n'
                'Please run the application on Windows with the DLL present.',
                textAlign: TextAlign.center,
                style: NexusTypography.bodyMd.copyWith(
                  color: NexusColors.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWithTabs() {
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: NexusColors.surfaceContainerLow,
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            children: [
              _buildTab(0, Icons.monitor_heart_outlined, 'Live Monitor'),
              SizedBox(
                height: 24,
                child: VerticalDivider(
                  width: 1,
                  color: NexusColors.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              _buildTab(1, Icons.bar_chart_outlined, 'Key Statistics'),
            ],
          ),
        ),
        const SizedBox(height: NexusSpacing.md),
        Expanded(
          child: _selectedTab == 0 ? _buildContent() : _buildStatsContent(),
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
                ? NexusColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected
                    ? NexusColors.primary
                    : NexusColors.onSurfaceVariant,
              ),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                label,
                style: NexusTypography.labelMd.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? NexusColors.primary
                      : NexusColors.onSurfaceVariant,
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
          _buildKeyboardSection(),
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
                Icon(Icons.mouse, size: 20, color: NexusColors.primary),
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
                    icon: Icons.my_location,
                    label: 'Position',
                    value: '($_mouseX, $_mouseY)',
                  ),
                ),
                const SizedBox(width: NexusSpacing.md),
                // Scroll
                Expanded(
                  child: _buildMetricCard(
                    icon: Icons.swap_vert,
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
                color: NexusColors.onSurfaceVariant,
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
        color: NexusColors.surfaceContainerLow,
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(
          color: NexusColors.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: NexusColors.onSurfaceVariant),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: NexusTypography.labelSm.copyWith(
                    color: NexusColors.onSurfaceVariant,
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
    final color = pressed ? NexusColors.stockUp : NexusColors.onSurfaceVariant;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: NexusSpacing.sm,
          horizontal: NexusSpacing.md,
        ),
        decoration: BoxDecoration(
          color: pressed
              ? color.withValues(alpha: 0.1)
              : NexusColors.surfaceContainerLow,
          borderRadius: NexusRadii.mdRadius,
          border: Border.all(
            color: pressed
                ? color.withValues(alpha: 0.3)
                : NexusColors.outlineVariant.withValues(alpha: 0.15),
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
                color: pressed ? color : NexusColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboardSection() {
    // Define modifier keys to show separately
    final modifiers = [
      VirtualKey.shift,
      VirtualKey.control,
      VirtualKey.menu,
      VirtualKey.lWin,
    ];
    final pressedModifiers = modifiers.where((k) => _pressedKeys.contains(k));

    // Currently pressed keys (excluding modifiers already shown)
    final otherKeys = _pressedKeys.where((k) => !modifiers.contains(k)).toList()
      ..sort();

    // Common keys to always show in the grid
    final commonKeys = [
      VirtualKey.escape,
      VirtualKey.f1,
      VirtualKey.f2,
      VirtualKey.f3,
      VirtualKey.f4,
      VirtualKey.f5,
      VirtualKey.f6,
      VirtualKey.f7,
      VirtualKey.f8,
      VirtualKey.f9,
      VirtualKey.f10,
      VirtualKey.f11,
      VirtualKey.f12,
    ];
    final row1 = [
      VirtualKey.key0,
      VirtualKey.key1,
      VirtualKey.key2,
      VirtualKey.key3,
      VirtualKey.key4,
      VirtualKey.key5,
      VirtualKey.key6,
      VirtualKey.key7,
      VirtualKey.key8,
      VirtualKey.key9,
    ];

    return NexusCard(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.keyboard, size: 20, color: NexusColors.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('Keyboard', style: NexusTypography.headlineSm),
                const Spacer(),
                if (pressedModifiers.isNotEmpty)
                  Text(
                    pressedModifiers.map((k) => VirtualKey.name(k)).join(' + '),
                    style: NexusTypography.labelMd.copyWith(
                      color: NexusColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: NexusSpacing.lg),
            // Modifier keys
            Wrap(
              spacing: NexusSpacing.sm,
              runSpacing: NexusSpacing.sm,
              children: [
                for (final code in modifiers)
                  _buildKeyChip(code, _pressedKeys.contains(code)),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            const Divider(height: 1, color: NexusColors.outlineVariant),
            const SizedBox(height: NexusSpacing.md),
            // Function keys
            Text(
              'Function Keys',
              style: NexusTypography.labelSm.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Wrap(
              spacing: NexusSpacing.sm,
              runSpacing: NexusSpacing.sm,
              children: [
                for (final code in commonKeys)
                  _buildKeyChip(code, _pressedKeys.contains(code)),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            // Number row
            Text(
              'Number Row',
              style: NexusTypography.labelSm.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            Wrap(
              spacing: NexusSpacing.sm,
              runSpacing: NexusSpacing.sm,
              children: [
                for (final code in row1)
                  _buildKeyChip(code, _pressedKeys.contains(code)),
              ],
            ),
            const SizedBox(height: NexusSpacing.md),
            // Letter rows
            Text(
              'Letters',
              style: NexusTypography.labelSm.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            ..._buildLetterRows(),
            const SizedBox(height: NexusSpacing.md),
            // Other pressed keys
            if (otherKeys.isNotEmpty) ...[
              const Divider(height: 1, color: NexusColors.outlineVariant),
              const SizedBox(height: NexusSpacing.md),
              Text(
                'Other Pressed Keys',
                style: NexusTypography.labelSm.copyWith(
                  color: NexusColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: NexusSpacing.sm),
              Wrap(
                spacing: NexusSpacing.sm,
                runSpacing: NexusSpacing.sm,
                children: [
                  for (final code in otherKeys) _buildKeyChip(code, true),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLetterRows() {
    final rows = [
      [
        VirtualKey.q,
        VirtualKey.w,
        VirtualKey.e,
        VirtualKey.r,
        VirtualKey.t,
        VirtualKey.y,
        VirtualKey.u,
        VirtualKey.i,
        VirtualKey.o,
        VirtualKey.p,
      ],
      [
        VirtualKey.a,
        VirtualKey.s,
        VirtualKey.d,
        VirtualKey.f,
        VirtualKey.g,
        VirtualKey.h,
        VirtualKey.j,
        VirtualKey.k,
        VirtualKey.l,
      ],
      [
        VirtualKey.z,
        VirtualKey.x,
        VirtualKey.c,
        VirtualKey.v,
        VirtualKey.b,
        VirtualKey.n,
        VirtualKey.m,
      ],
    ];
    return rows.map((row) {
      return Padding(
        padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
        child: Wrap(
          spacing: NexusSpacing.sm,
          runSpacing: NexusSpacing.sm,
          children: row.map((code) {
            return _buildKeyChip(code, _pressedKeys.contains(code));
          }).toList(),
        ),
      );
    }).toList();
  }

  Widget _buildKeyChip(int code, bool pressed) {
    final name = VirtualKey.name(code);
    final color = pressed ? NexusColors.primary : NexusColors.onSurfaceVariant;
    final bg = pressed
        ? NexusColors.primary.withValues(alpha: 0.12)
        : NexusColors.surfaceContainerLow;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: NexusSpacing.sm,
        horizontal: NexusSpacing.md,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(
          color: pressed
              ? color.withValues(alpha: 0.4)
              : NexusColors.outlineVariant.withValues(alpha: 0.1),
          width: pressed ? 1.5 : 1,
        ),
      ),
      child: Text(
        name.length > 5 ? name.substring(0, 5) : name,
        style: NexusTypography.labelMd.copyWith(
          fontWeight: pressed ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      ),
    );
  }

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
                  Icons.calendar_today,
                  size: 20,
                  color: NexusColors.primary,
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
                IconButton(
                  onPressed: () {
                    final prev = _selectedDate.subtract(
                      const Duration(days: 1),
                    );
                    _selectDate(prev);
                  },
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous day',
                ),
                // Date display + picker
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
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
                        color: NexusColors.surfaceContainerLow,
                        borderRadius: NexusRadii.mdRadius,
                        border: Border.all(
                          color: NexusColors.outlineVariant.withValues(
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
                            Icons.arrow_drop_down,
                            size: 20,
                            color: NexusColors.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Next day (only if not today)
                IconButton(
                  onPressed:
                      _formatDate(_selectedDate) != _formatDate(DateTime.now())
                      ? () {
                          final next = _selectedDate.add(
                            const Duration(days: 1),
                          );
                          _selectDate(next);
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next day',
                ),
                // Today
                TextButton(
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
                              ? NexusColors.primary.withValues(alpha: 0.1)
                              : NexusColors.surfaceContainerLow,
                          borderRadius: NexusRadii.mdRadius,
                          border: Border.all(
                            color: isSelected
                                ? NexusColors.primary.withValues(alpha: 0.3)
                                : NexusColors.outlineVariant.withValues(
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
                                  ? NexusColors.primary
                                  : NexusColors.onSurfaceVariant,
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
                  Icons.keyboard_outlined,
                  size: 20,
                  color: NexusColors.secondary,
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
                NexusColors.secondary.withValues(alpha: 0.2),
                NexusColors.secondary,
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
      bg = NexusColors.surfaceContainerLow;
      fg = NexusColors.onSurfaceVariant;
    } else {
      bg = Color.lerp(
        NexusColors.secondary.withValues(alpha: 0.25),
        NexusColors.secondary,
        t,
      )!;
      fg = t > 0.45 ? NexusColors.onSecondary : NexusColors.onSurface;
    }

    return Tooltip(
      message: count > 0 ? '${key.label} · $count' : key.label,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: NexusRadii.smRadius,
          border: Border.all(
            color: NexusColors.outlineVariant.withValues(alpha: 0.2),
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
                  Icons.bar_chart_outlined,
                  size: 48,
                  color: NexusColors.onSurfaceVariant.withValues(alpha: 0.3),
                ),
                const SizedBox(height: NexusSpacing.md),
                Text(
                  'No key press data for this date',
                  style: NexusTypography.bodyMd.copyWith(
                    color: NexusColors.onSurfaceVariant,
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
                Icon(Icons.bar_chart, size: 20, color: NexusColors.primary),
                const SizedBox(width: NexusSpacing.sm),
                Text('Key Press Statistics', style: NexusTypography.headlineSm),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.md,
                    vertical: NexusSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: NexusColors.primary.withValues(alpha: 0.1),
                    borderRadius: NexusRadii.mdRadius,
                  ),
                  child: Text(
                    'Total: ${stats.totalPresses}',
                    style: NexusTypography.labelMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: NexusColors.primary,
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
                color: NexusColors.onSurfaceVariant,
              ),
            ),
          ),
          // Key cap
          Container(
            width: 64,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainerHigh,
              borderRadius: NexusRadii.smRadius,
              border: Border.all(
                color: NexusColors.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Tooltip(
              message:
                  '0x${stat.keyCode.toRadixString(16).toUpperCase().padLeft(2, '0')}',
              child: Text(
                stat.keyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.labelSm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: NexusColors.onSurface,
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
                backgroundColor: NexusColors.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color.lerp(
                    NexusColors.secondary.withValues(alpha: 0.4),
                    NexusColors.secondary,
                    ratio,
                  )!,
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
                color: NexusColors.onSurface,
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
