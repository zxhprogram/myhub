import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../layout/page_scaffold.dart';
import '../states/pomodoro_state.dart';

/// Pomodoro timer page.
///
/// A macOS-style timer with a progress ring, session presets, and controls.
/// The countdown lives in the [PomodoroState] singleton, so it keeps running
/// while other applications are used and between desktop window closures.
class PomodoroPage extends StatefulWidget {
  const PomodoroPage({super.key});

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
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
              Text('Pomodoro', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'Focus sessions with scheduled breaks',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const _CompletedFocusBadge(),
        ],
      ),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _ModeSelector(),
              const SizedBox(height: NexusSpacing.xl),
              const _TimerRing(),
              const SizedBox(height: NexusSpacing.xl),
              const _TimerControls(),
              const SizedBox(height: NexusSpacing.xl),
              const _DailyGoal(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered, seamless segmented pill above the ring to switch session types.
class _ModeSelector extends StatelessWidget {
  const _ModeSelector();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mode in PomodoroMode.values) ...[
            if (mode != PomodoroMode.values.first)
              const SizedBox(width: NexusSpacing.xs),
            _ModeChip(mode: mode),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.mode});

  final PomodoroMode mode;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = PomodoroState.instance;
    state.mode.watch(context);
    final selected = state.mode.value == mode;
    return InkWell(
      onTap: () => state.selectMode(mode),
      borderRadius: NexusRadii.fullRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.lg,
          vertical: NexusSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.surfaceContainerLowest
              : Colors.transparent,
          borderRadius: NexusRadii.fullRadius,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colorScheme.onSurface.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          _label(mode),
          style: NexusTypography.labelMd.copyWith(
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  static String _label(PomodoroMode mode) => switch (mode) {
    PomodoroMode.focus => 'Focus',
    PomodoroMode.shortBreak => 'Short Break',
    PomodoroMode.longBreak => 'Long Break',
  };
}

/// Animated circular progress ring around the remaining time.
class _TimerRing extends StatelessWidget {
  const _TimerRing();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = PomodoroState.instance;
    state.mode.watch(context);
    state.remainingSeconds.watch(context);
    final progress = state.progress.clamp(0.0, 1.0).toDouble();
    final color = _modeColor(state.mode.value);
    final remaining = state.remainingSeconds.value;
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return SizedBox(
          width: 300,
          height: 300,
          child: CustomPaint(
            painter: _RingPainter(
              progress: value,
              color: color,
              trackColor: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$minutes:$seconds',
                    style: NexusTypography.headlineXl.copyWith(
                      fontSize: 52,
                      height: 1,
                      fontWeight: FontWeight.w300,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: NexusSpacing.sm),
                  Text(
                    _modeLabel(state.mode.value),
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _modeLabel(PomodoroMode mode) => switch (mode) {
    PomodoroMode.focus => 'FOCUS',
    PomodoroMode.shortBreak => 'SHORT BREAK',
    PomodoroMode.longBreak => 'LONG BREAK',
  };

  static Color _modeColor(PomodoroMode mode) => switch (mode) {
    PomodoroMode.focus => const Color(0xFFE74C3C),
    PomodoroMode.shortBreak => const Color(0xFF2196F3),
    PomodoroMode.longBreak => const Color(0xFF43A047),
  };
}

/// Draws the countdown progress ring (fills as the session elapses).
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 14.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start at 12 o'clock.
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

/// Start/Pause, Reset and Skip controls.
class _TimerControls extends StatelessWidget {
  const _TimerControls();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = PomodoroState.instance;
    state.isRunning.watch(context);
    final running = state.isRunning.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlButton(
          icon: Icons.skip_next_rounded,
          tooltip: 'Skip to next session',
          onTap: state.skip,
        ),
        const SizedBox(width: NexusSpacing.lg),
        _PrimaryControlButton(
          icon: running ? Icons.pause_rounded : Icons.play_arrow_rounded,
          label: running ? 'Pause' : 'Start',
          onTap: state.toggle,
        ),
        const SizedBox(width: NexusSpacing.lg),
        _ControlButton(
          icon: Icons.restart_alt_rounded,
          tooltip: 'Reset timer',
          onTap: state.reset,
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: colorScheme.onSurface, size: 22),
        ),
      ),
    );
  }
}

class _PrimaryControlButton extends StatelessWidget {
  const _PrimaryControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: NexusRadii.fullRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.xl,
          vertical: NexusSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colorScheme.secondary,
          boxShadow: [
            BoxShadow(
              color: colorScheme.secondary.withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          borderRadius: NexusRadii.fullRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.onSecondary, size: 22),
            const SizedBox(width: NexusSpacing.sm),
            Text(
              label,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the focus session goal (defaults to 4 per day).
class _DailyGoal extends StatelessWidget {
  const _DailyGoal();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final completed = PomodoroState.instance.completedFocus.watch(context);
    const target = 4;
    final reached = completed >= target;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.lg,
        vertical: NexusSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: NexusRadii.lgRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            reached ? Icons.emoji_events : Icons.local_fire_department,
            size: 18,
            color: reached
                ? const Color(0xFFFF9500)
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: NexusSpacing.sm),
          Text(
            '$completed / $target',
            style: NexusTypography.bodyMd.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: NexusSpacing.xs),
          Text('focus sessions today', style: NexusTypography.labelMd),
        ],
      ),
    );
  }
}

/// Decorative header badge showing focus sessions completed today.
class _CompletedFocusBadge extends StatelessWidget {
  const _CompletedFocusBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((_) {
      final completed = PomodoroState.instance.completedFocus.value;
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: NexusRadii.fullRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_fire_department,
              size: 16,
              color: Color(0xFFFF9500),
            ),
            const SizedBox(width: NexusSpacing.xs),
            Text(
              '$completed today',
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    });
  }
}
