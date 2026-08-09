import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import '../repositories/network_traffic_repository.dart';

// FFI type definitions for the network_monitor.dll exports.
typedef NetworkMonitorStartNative = Int32 Function();
typedef NetworkMonitorStartDart = int Function();

typedef NetworkMonitorStopNative = Int32 Function();
typedef NetworkMonitorStopDart = int Function();

typedef NetworkGetUint64Native = Uint64 Function();
typedef NetworkGetUint64Dart = int Function();

/// Service for real-time network traffic monitoring backed by the Go
/// `network_monitor.dll` (gopsutil `net.IOCounters`).
///
/// The DLL keeps cumulative byte counters plus per-second deltas updated by a
/// background sampler; this service polls them once a second into cached
/// getters for live display and once a minute persists the delta since the
/// previous reading into [NetworkTrafficRepository].
class NetworkMonitorService {
  NetworkMonitorService._();

  static NetworkMonitorService? _instance;

  static NetworkMonitorService get instance {
    _instance ??= NetworkMonitorService._();
    return _instance!;
  }

  DynamicLibrary? _lib;
  bool _initialized = false;

  // Native function pointers
  NetworkMonitorStartDart? _start;
  NetworkMonitorStopDart? _stop;
  NetworkGetUint64Dart? _getTotalRecv;
  NetworkGetUint64Dart? _getTotalSent;
  NetworkGetUint64Dart? _getRecvSpeed;
  NetworkGetUint64Dart? _getSentSpeed;

  // Cached values refreshed every second
  int _totalRecvValue = 0;
  int _totalSentValue = 0;
  int _recvSpeedValue = 0;
  int _sentSpeedValue = 0;

  // Per-minute recording
  Timer? _tickTimer;
  Timer? _recordTimer;
  int _lastRecv = 0;
  int _lastSent = 0;

  int get totalRecv => _totalRecvValue;
  int get totalSent => _totalSentValue;
  int get recvSpeed => _recvSpeedValue;
  int get sentSpeed => _sentSpeedValue;

  /// Whether the DLL was loaded and sampling has started.
  bool get isRunning => _initialized;

  /// Load the DLL, start sampling and the per-minute recording timer.
  ///
  /// Safe to call from anywhere (e.g. `main`); no-ops once running and
  /// degrades gracefully when the DLL is missing.
  void start() {
    if (_initialized) return;

    try {
      _lib = Platform.isWindows
          ? DynamicLibrary.open('network_monitor.dll')
          : DynamicLibrary.process();

      _start = _lib!.lookupFunction<NetworkMonitorStartNative,
          NetworkMonitorStartDart>('NetworkMonitorStart');
      _stop = _lib!.lookupFunction<NetworkMonitorStopNative,
          NetworkMonitorStopDart>('NetworkMonitorStop');
      _getTotalRecv = _lib!.lookupFunction<NetworkGetUint64Native,
          NetworkGetUint64Dart>('NetworkGetTotalRecv');
      _getTotalSent = _lib!.lookupFunction<NetworkGetUint64Native,
          NetworkGetUint64Dart>('NetworkGetTotalSent');
      _getRecvSpeed = _lib!.lookupFunction<NetworkGetUint64Native,
          NetworkGetUint64Dart>('NetworkGetRecvSpeed');
      _getSentSpeed = _lib!.lookupFunction<NetworkGetUint64Native,
          NetworkGetUint64Dart>('NetworkGetSentSpeed');

      final result = _start!();
      if (result != 0) return;
      _initialized = true;

      // Seed baselines so the first recorded minute is not a huge boot value.
      _lastRecv = _getTotalRecv!();
      _lastSent = _getTotalSent!();

      _tick();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _recordTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => _recordMinute(),
      );
    } catch (_) {
      _initialized = false;
    }
  }

  /// Refresh cached counters/speeds from the DLL.
  void _tick() {
    _totalRecvValue = _getTotalRecv!();
    _totalSentValue = _getTotalSent!();
    _recvSpeedValue = _getRecvSpeed!();
    _sentSpeedValue = _getSentSpeed!();
  }

  /// Persist the bytes transferred since the previous recording.
  Future<void> _recordMinute() async {
    final recv = _getTotalRecv!();
    final sent = _getTotalSent!();
    final deltaRecv = recv - _lastRecv;
    final deltaSent = sent - _lastSent;
    _lastRecv = recv;
    _lastSent = sent;

    if (deltaRecv <= 0 && deltaSent <= 0) return;
    await NetworkTrafficRepository.recordMinute(
      DateTime.now(),
      deltaRecv,
      deltaSent,
    );
  }

  /// Stop sampling, cancel timers and release the native monitor.
  void dispose() {
    _tickTimer?.cancel();
    _recordTimer?.cancel();
    _tickTimer = null;
    _recordTimer = null;

    if (_initialized && _stop != null) {
      try {
        _stop!();
      } catch (_) {
        // DLL may already be gone; ignore.
      }
    }
    _initialized = false;
  }
}
