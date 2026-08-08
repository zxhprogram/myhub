import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// A Pomodoro session type, each with a different duration.
enum PomodoroMode {
  focus,
  shortBreak,
  longBreak;

  int get minutes => switch (this) {
    PomodoroMode.focus => 25,
    PomodoroMode.shortBreak => 5,
    PomodoroMode.longBreak => 15,
  };
}

/// Signals-backed singleton state for the Pomodoro timer.
///
/// Lives outside the page widget so the countdown keeps running even when the
/// desktop window is closed and reopened within the same session.
class PomodoroState {
  PomodoroState._();

  /// The singleton instance used across the app.
  static final PomodoroState instance = PomodoroState._();

  static const _countKey = 'nexus_pomodoro_focus_count_v1';
  static const _dateKey = 'nexus_pomodoro_focus_date_v1';

  /// The currently selected session type.
  final mode = signal<PomodoroMode>(PomodoroMode.focus);

  /// Whole seconds left in the current session.
  final remainingSeconds = signal<int>(PomodoroMode.focus.minutes * 60);

  /// Whether the countdown is currently running.
  final isRunning = signal<bool>(false);

  /// Number of completed focus sessions today (drives the long break cadence).
  final completedFocus = signal<int>(0);

  Timer? _timer;

  int get totalSeconds => _totalFor(mode.value);

  static int _totalFor(PomodoroMode mode) => mode.minutes * 60;

  /// Progress 0..1 of the current session (fills as time elapses).
  double get progress =>
      (totalSeconds - remainingSeconds.value) / totalSeconds;

  /// Restores the focus count saved on a previous day, if any.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_dateKey);
      final count = prefs.getInt(_countKey) ?? 0;
      if (savedDate == _dayKey(DateTime.now())) {
        completedFocus.value = count;
      } else {
        completedFocus.value = 0;
      }
    } catch (_) {
      // Storage unavailable (e.g. in tests); start from zero.
    }
  }

  /// Toggles the countdown between running and paused.
  void toggle() {
    if (isRunning.value) {
      pause();
    } else {
      start();
    }
  }

  void start() {
    if (isRunning.value || _timer != null) return;
    isRunning.value = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;
  }

  /// Restarts the current session from its full duration.
  void reset() {
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;
    remainingSeconds.value = totalSeconds;
  }

  /// Switches to a different session type and resets the countdown.
  void selectMode(PomodoroMode next) {
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;
    mode.value = next;
    remainingSeconds.value = _totalFor(next);
  }

  /// Ends the current session immediately, moving to the next one without
  /// counting the focus session as completed.
  void skip() {
    _completeSession(completed: false, autoStart: false);
  }

  void _tick() {
    final next = remainingSeconds.value - 1;
    if (next <= 0) {
      remainingSeconds.value = 0;
      _completeSession(completed: true, autoStart: true);
    } else {
      remainingSeconds.value = next;
    }
  }

  /// Advances to the next session and optionally starts it immediately.
  ///
  /// [completed] indicates the focus session finished naturally; skipped
  /// sessions advance to a short break without counting it in the daily total.
  void _completeSession({required bool completed, required bool autoStart}) {
    _timer?.cancel();
    _timer = null;
    isRunning.value = false;

    if (mode.value == PomodoroMode.focus) {
      if (completed) {
        // Audible cue so the countdown is noticeable while working elsewhere.
        try {
          SystemSound.play(SystemSoundType.alert);
        } catch (_) {
          // No audio platform (e.g. tests) — the transition still proceeds.
        }
        completedFocus.value += 1;
        _persistCount();
        // Every 4th focus session earns a long break.
        final next = completedFocus.value % 4 == 0
            ? PomodoroMode.longBreak
            : PomodoroMode.shortBreak;
        mode.value = next;
        remainingSeconds.value = _totalFor(next);
      } else {
        mode.value = PomodoroMode.shortBreak;
        remainingSeconds.value = _totalFor(PomodoroMode.shortBreak);
      }
    } else {
      mode.value = PomodoroMode.focus;
      remainingSeconds.value = _totalFor(PomodoroMode.focus);
    }

    if (autoStart) {
      start();
    }
  }

  Future<void> _persistCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_dateKey, _dayKey(DateTime.now()));
      await prefs.setInt(_countKey, completedFocus.value);
    } catch (_) {
      // Persistence is best-effort.
    }
  }

  static String _dayKey(DateTime time) =>
      '${time.year}-${time.month}-${time.day}';
}