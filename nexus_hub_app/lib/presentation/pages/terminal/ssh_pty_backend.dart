import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

/// A [PtyBackend] whose byte source is a remote SSH shell instead of a local
/// PTY — the engine and view are unchanged, only the transport differs (the
/// exact swap the [PtyBackend] interface was designed for).
///
/// Construct via [connect]; the constructor is private because the SSH
/// handshake must complete before the backend can serve bytes.
class SshPtyBackend implements PtyBackend {
  SshPtyBackend._(this._client, this._session) {
    _exitCode = Completer<int>();
    _output = StreamController<Uint8List>();
    // With a PTY the remote side usually merges stderr into stdout, but pipe
    // both so servers that keep them separate still render.
    _stdoutSub = _session.stdout.listen(
      _output.add,
      onDone: _closeOutput,
      onError: (Object _) => _closeOutput,
    );
    _stderrSub = _session.stderr.listen(
      _output.add,
      onError: (Object _) {},
    );
    // The channel-close future is the reliable "session ended" signal; the
    // transport-done future is a safety net for socket-level failures.
    _session.done.then(
      (_) => _completeExit(_session.exitCode),
      onError: (Object _) => _completeExit(null),
    );
    _client.done.then(
      (_) => _completeExit(null),
      onError: (Object _) => _completeExit(null),
    );
  }

  final SSHClient _client;
  final SSHSession _session;

  late final Completer<int> _exitCode;
  late final StreamController<Uint8List> _output;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  bool _killed = false;

  /// Connects to [host]:[port], authenticates with password auth, and opens
  /// an interactive shell sized to the initial viewport.
  ///
  /// Throws on connection/auth/shell failure — callers surface the error in
  /// the terminal's exit overlay so the user can retry.
  static Future<SshPtyBackend> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    int rows = 24,
    int columns = 80,
  }) async {
    final socket = await SSHSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 15),
    );
    // onVerifyHostKey left null → unknown host keys are accepted (there is
    // no known_hosts store yet).
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
      keepAliveInterval: const Duration(seconds: 15),
      handshakeTimeout: const Duration(seconds: 20),
      authTimeout: const Duration(seconds: 20),
    );
    try {
      final session = await client.shell(
        pty: SSHPtyConfig(width: columns, height: rows),
      );
      return SshPtyBackend._(client, session);
    } on Object {
      client.close();
      rethrow;
    }
  }

  void _completeExit(int? code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code ?? 0);
    }
  }

  void _closeOutput() {
    if (!_output.isClosed) {
      _output.close();
    }
  }

  @override
  Stream<Uint8List> get output => _output.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  ValueListenable<bool>? get isForegroundProcessRunning => null;

  @override
  void write(Uint8List data) {
    if (!_killed && !_output.isClosed) {
      try {
        _session.write(data);
      } on StateError {
        // Channel already closed — a race with disconnect; ignore.
      }
    }
  }

  @override
  void resize(int rows, int columns) {
    if (_killed) return;
    try {
      // SSHSession's argument order is (columns, rows).
      _session.resizeTerminal(columns, rows);
    } on StateError {
      // Channel already closed — ignore.
    }
  }

  @override
  void kill() {
    if (_killed) return;
    _killed = true;
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _closeOutput();
    _completeExit(null);
    _client.close();
  }
}
