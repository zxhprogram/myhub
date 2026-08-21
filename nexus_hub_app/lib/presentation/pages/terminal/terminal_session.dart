import 'dart:async';
import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/ssh_profile.dart';
import 'ssh_pty_backend.dart';

/// Whether a session runs a local shell or a remote SSH shell.
enum TerminalSessionKind { local, ssh }

/// Lifecycle owner of one terminal tab: engine + controller + backend pipes.
///
/// The session is started lazily from the first [onResize] report (the view
/// knows the viewport size before any shell should spawn — the same contract
/// the single-session page used). [restart] tears everything down and swaps in
/// a fresh engine/controller pair; [dispose] releases it for good.
class TerminalSession {
  TerminalSession._(this.kind, this.profile, this.title) {
    _controller.attach(engine);
  }

  factory TerminalSession.local(String title) =>
      TerminalSession._(TerminalSessionKind.local, null, title);

  factory TerminalSession.ssh(SshProfile profile) =>
      TerminalSession._(TerminalSessionKind.ssh, profile, profile.name);

  static int _idCounter = 0;

  final String id =
      'session_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  final TerminalSessionKind kind;

  /// Connection profile for SSH sessions; `null` for local ones. Retained so
  /// the session can reconnect after a drop without asking the user again.
  final SshProfile? profile;

  /// Sidebar/tab title: "本地 N" or the profile name.
  final String title;

  final TerminalConfig config = TerminalConfig.defaults();

  late TerminalEngine _engine = TerminalEngine(config: config);
  TerminalController _controller = TerminalController();

  TerminalEngine get engine => _engine;
  TerminalController get controller => _controller;

  /// Focus node shared with the session's [TerminalView]; the page requests
  /// focus here when the session becomes active.
  final focusNode = FocusNode();

  PtyBackend? _pty;
  StreamSubscription<Uint8List>? _ptyIn;
  StreamSubscription<Uint8List>? _ptyOut;
  bool _started = false;
  bool _disposed = false;

  /// True while an SSH connection is being established.
  final connecting = signal<bool>(false);

  /// True once the shell/process/connection has ended (overlay shown).
  final exited = signal<bool>(false);
  String? exitMessage;

  /// Viewport-size callback: starts the session on the first report, resizes
  /// the backend afterwards. Order is (columns, rows) from the view.
  void onResize(int cols, int rows) {
    final pty = _pty;
    if (pty == null) {
      if (_started || _disposed) return;
      _started = true;
      unawaited(_start(cols, rows));
    } else {
      pty.resize(rows, cols);
    }
  }

  Future<void> _start(int cols, int rows) async {
    if (kind == TerminalSessionKind.local) {
      try {
        _attach(FlutterPtyBackend(
          rows: rows,
          columns: cols,
          shell: config.shell,
        ));
      } on Object catch (e) {
        _markExited('failed to start: $e');
      }
      return;
    }

    final p = profile!;
    connecting.value = true;
    try {
      final backend = await SshPtyBackend.connect(
        host: p.host,
        port: p.port,
        username: p.username,
        password: p.password,
        rows: rows,
        columns: cols,
      );
      if (_disposed) {
        backend.kill();
        return;
      }
      _attach(backend);
    } on Object catch (e) {
      _markExited('连接失败: $e');
    } finally {
      connecting.value = false;
    }
  }

  void _attach(PtyBackend pty) {
    _pty = pty;
    _ptyOut = _engine.output.listen(pty.write);
    _ptyIn = pty.output.listen(
      _engine.feed,
      onDone: () => _onExit(pty, null),
    );
    // exitCode completes when the process/connection ends, even if the output
    // stream stays open — the reliable "session ended" signal.
    pty.exitCode.then((code) => _onExit(pty, code));
  }

  void _onExit(PtyBackend pty, int? code) {
    if (!identical(_pty, pty) || _disposed) return;
    final detail = code != null && code != 0 ? ' ($code)' : '';
    _markExited(
      kind == TerminalSessionKind.ssh ? '连接已断开$detail' : 'process exited$detail',
    );
  }

  void _markExited(String message) {
    exitMessage = message;
    exited.value = true;
  }

  /// Tear down pipes/backend and swap in a fresh engine+controller pair so
  /// the same view can host a second run.
  void _reset() {
    _ptyIn?.cancel();
    _ptyOut?.cancel();
    _ptyIn = null;
    _ptyOut = null;
    _pty?.kill();
    _pty = null;
    _started = false;
    _controller.dispose();
    _engine.dispose();
    _engine = TerminalEngine(config: config);
    _controller = TerminalController()..attach(_engine);
  }

  /// Re-run the session (respawn local shell / reconnect SSH).
  void restart() {
    if (_disposed) return;
    _reset();
    exitMessage = null;
    exited.value = false;
  }

  /// Paste text from the system clipboard into this session's shell.
  Future<void> paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _engine.write(utf8.encode(text));
  }

  /// Release everything for good. Call only after the view has been unmounted.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ptyIn?.cancel();
    _ptyOut?.cancel();
    _pty?.kill();
    _pty = null;
    _controller.dispose();
    _engine.dispose();
    focusNode.dispose();
  }
}
