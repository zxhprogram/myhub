import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_hub_app/presentation/states/pomodoro_state.dart';

/// Guards the Pomodoro timer state machine: durations, session flow,
/// auto-advance, and the long-break cadence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  PomodoroState fresh() => PomodoroState.instance;

  void resetState(PomodoroState state) {
    state.pause();
    state.completedFocus.value = 0;
    state.mode.value = PomodoroMode.focus;
    state.remainingSeconds.value = state.totalSeconds;
  }

  setUp(() => resetState(fresh()));
  tearDown(() => fresh().pause());

  test('focus session defaults to 25 minutes', () {
    final state = fresh();
    expect(state.mode.value, PomodoroMode.focus);
    expect(state.totalSeconds, 25 * 60);
    expect(state.remainingSeconds.value, 25 * 60);
  });

  testWidgets('running countdown decrements once per second',
      (tester) async {
    final state = fresh();
    state.remainingSeconds.value = 30;
    state.start();
    expect(state.isRunning.value, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(state.remainingSeconds.value, 27);

    state.pause();
    final pausedAt = state.remainingSeconds.value;
    await tester.pump(const Duration(seconds: 5));
    expect(state.remainingSeconds.value, pausedAt);
  });

  test('pause stops the timer and start resumes it', () {
    final state = fresh();
    state.start();
    state.pause();
    expect(state.isRunning.value, isFalse);
    state.start();
    expect(state.isRunning.value, isTrue);
    state.pause();
  });

  test('reset restores the full session duration', () {
    final state = fresh();
    state.remainingSeconds.value = 60;
    state.reset();
    expect(state.remainingSeconds.value, state.totalSeconds);
    expect(state.isRunning.value, isFalse);
  });

  test('selectMode resets the countdown to the chosen duration', () {
    final state = fresh();
    state.remainingSeconds.value = 1;
    state.selectMode(PomodoroMode.shortBreak);
    expect(state.mode.value, PomodoroMode.shortBreak);
    expect(state.remainingSeconds.value, 5 * 60);
    expect(state.isRunning.value, isFalse);
  });

  test('progress reflects elapsed fraction of the current session', () {
    final state = fresh();
    expect(state.progress, 0);
    state.remainingSeconds.value = state.totalSeconds ~/ 2;
    expect(state.progress, closeTo(0.5, 0.001));
  });

  testWidgets('a completed focus session counts, auto-advances and restarts',
      (tester) async {
    final state = fresh();
    state.remainingSeconds.value = 2;
    state.start();

    await tester.pump(const Duration(seconds: 2));

    expect(state.completedFocus.value, 1);
    expect(state.mode.value, PomodoroMode.shortBreak);
    expect(state.remainingSeconds.value, 5 * 60);
    // The next session auto-starts to keep the flow uninterrupted.
    expect(state.isRunning.value, isTrue);

    state.pause(); // Stop the auto-started timer before teardown.
  });

  testWidgets('fourth focus session earns a long break', (tester) async {
    final state = fresh();
    for (var i = 1; i <= 4; i++) {
      // Return from the previous break back to focus.
      if (i > 1) state.skip();
      state.remainingSeconds.value = 1; // Finish this focus session shortly.
      state.start();
      await tester.pump(const Duration(seconds: 1));
      expect(state.completedFocus.value, i);
    }
    // After the 4th completed focus we land directly on the long break.
    expect(state.mode.value, PomodoroMode.longBreak);
    expect(state.remainingSeconds.value, 15 * 60);

    state.pause(); // Clean up the auto-running timer before teardown.
  });

  test('skip advances a focus session without counting it', () {
    final state = fresh();
    state.start();
    state.skip();
    expect(state.completedFocus.value, 0);
    expect(state.mode.value, PomodoroMode.shortBreak);
    expect(state.isRunning.value, isFalse);
  });

  testWidgets('a finished break returns to a focus session', (tester) async {
    final state = fresh();
    state.selectMode(PomodoroMode.shortBreak);
    state.remainingSeconds.value = 1;
    state.start();

    await tester.pump(const Duration(seconds: 1));

    expect(state.mode.value, PomodoroMode.focus);
    expect(state.completedFocus.value, 0);
    expect(state.remainingSeconds.value, 25 * 60);

    state.pause(); // Clean up the auto-running timer before teardown.
  });
}