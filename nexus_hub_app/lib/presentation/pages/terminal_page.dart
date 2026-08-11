import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// A full-featured terminal embedded in a desktop window.
///
/// Runs a real shell (`cmd.exe` on Windows) via [FlutterPtyBackend], driven by
/// the Alacritty Rust engine, rendered by [TerminalView]. The engine is created
/// lazily on first use, so the page stays `const`-buildable (matching the
/// other desktop app pages).
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final TerminalConfig _config = TerminalConfig.defaults();
  late TerminalEngine _engine = TerminalEngine(config: _config);
  late TerminalController _controller = TerminalController()..attach(_engine);

  PtyBackend? _pty;
  StreamSubscription<Uint8List>? _ptyIn;
  StreamSubscription<Uint8List>? _ptyOut;

  /// Whether the shell process has exited (restart overlay shown).
  final _exited = signal<bool>(false);
  String? _exitMessage;

  void _onPtyResize(int cols, int rows) {
    if (_pty == null) {
      _startSession(cols, rows);
    } else {
      _pty!.resize(rows, cols);
    }
  }

  void _startSession(int cols, int rows) {
    try {
      final pty = FlutterPtyBackend(
        rows: rows,
        columns: cols,
        shell: _config.shell,
      );
      _pty = pty;
      _ptyOut = _engine.output.listen(pty.write);
      _ptyIn = pty.output.listen(
        _engine.feed,
        onDone: () => _onPtyExit(pty, null),
      );
      // exitCode completes when the process ends, even if the output stream
      // stays open — that is the reliable "session ended" signal.
      pty.exitCode.then((code) => _onPtyExit(pty, code));
    } catch (e) {
      _exited.value = true;
      _exitMessage = 'failed to start: $e';
    }
  }

  void _onPtyExit(PtyBackend pty, int? code) {
    if (!identical(_pty, pty)) return;
    if (mounted) {
      _exited.value = true;
      _exitMessage = 'process exited${code != null ? ' ($code)' : ''}';
    }
  }

  void _restartSession() {
    _tearDown();
    _exited.value = false;
    _exitMessage = null;
    setState(() {});
  }

  void _tearDown() {
    _ptyIn?.cancel();
    _ptyOut?.cancel();
    _pty?.kill();
    _controller.dispose();
    _engine.dispose();
    _pty = null;
    _ptyIn = null;
    _ptyOut = null;
    // Re-create a fresh controller+engine pair so a second session works.
    final engine = TerminalEngine(config: _config);
    _engine = engine;
    _controller = TerminalController()..attach(engine);
  }

  /// Paste text from the system clipboard into the terminal.
  Future<void> _paste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    _engine.write(utf8.encode(text));
  }

  @override
  void dispose() {
    _tearDown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Dark terminal backdrop matching a typical alacritty palette.
    return ColoredBox(
      color: const Color(0xFF1A1A1E),
      child: Watch((_) {
        if (_exited.value) {
          return _buildRestartLayer();
        }
        return TerminalView(
          _engine,
          controller: _controller,
          onPtyResize: _onPtyResize,
          autofocus: true,
          theme: TerminalTheme.defaults,
          actions: {
            CopyIntent: CallbackAction<CopyIntent>(
              onInvoke: (_) {
                final text = _engine.selectionText();
                if (text != null && text.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: text));
                }
                return null;
              },
            ),
            PasteIntent: CallbackAction<PasteIntent>(
              onInvoke: (_) => _paste(),
            ),
          },
        );
      }),
    );
  }

  /// A full-surface overlay shown after the shell exits; tap to restart.
  Widget _buildRestartLayer() {
    return GestureDetector(
      onTap: _restartSession,
      child: Container(
        color: Colors.black.withValues(alpha: 0.7),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC1A1A1A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_exitMessage ?? 'process exited'} — 点击任意处重启',
            style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
          ),
        ),
      ),
    );
  }
}