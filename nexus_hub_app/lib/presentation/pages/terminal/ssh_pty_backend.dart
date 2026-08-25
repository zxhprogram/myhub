import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:path/path.dart' as p;

/// Progress snapshot for one file being uploaded over SFTP.
class SftpUploadProgress {
  const SftpUploadProgress({
    required this.fileIndex,
    required this.fileCount,
    required this.fileName,
    required this.sentBytes,
    required this.totalBytes,
  });

  /// Zero-based index of the current file within the whole batch.
  final int fileIndex;
  final int fileCount;

  /// Remote file name being written.
  final String fileName;

  /// Bytes acknowledged by the server so far.
  final int sentBytes;
  final int totalBytes;

  double get fraction =>
      totalBytes <= 0 ? 0 : (sentBytes / totalBytes).clamp(0.0, 1.0);
}

/// Thrown when the user cancels an in-flight batch upload.
class SftpUploadCancelled implements Exception {}

/// A [PtyBackend] whose byte source is a remote SSH shell instead of a local
/// PTY — the engine and view are unchanged, only the transport differs (the
/// exact swap the [PtyBackend] interface was designed for).
///
/// Construct via [connect]; the constructor is private because the SSH
/// handshake must complete before the backend can serve bytes.
class SshPtyBackend implements PtyBackend {
  SshPtyBackend._(this._client, this._session) {
    _exitCode = Completer<int>();
    // Broadcast so the cwd probe can listen alongside the session's main
    // pipe without a single-subscription StateError.
    _output = StreamController<Uint8List>.broadcast();
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

  // ── SFTP upload support ──────────────────────────────────────────────────

  /// The interactive shell's current working directory, probed through the
  /// PTY so a user's `cd` is respected (a fresh exec channel would only ever
  /// report the login home).
  ///
  /// A `printf '\001%s\001' "$PWD"` line is injected into the shell: the
  /// terminal echo of the typed command contains the literal four characters
  /// `\001`, while printf emits real 0x01 control bytes — so scanning for
  /// actual 0x01 pairs unambiguously finds the expanded path. Returns null
  /// when no answer arrives within the timeout (callers fall back to home).
  Future<String?> resolveWorkingDirectory({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (_killed || _output.isClosed) return null;

    final completer = Completer<String?>();
    final buffer = BytesBuilder(copy: false);
    late final StreamSubscription<Uint8List> sub;
    sub = _output.stream.listen((chunk) {
      if (completer.isCompleted) return;
      buffer.add(chunk);
      final data = buffer.toBytes();
      final start = data.indexOf(0x01);
      if (start < 0) return;
      final end = data.indexOf(0x01, start + 1);
      if (end <= start + 1) return;
      completer.complete(
        utf8.decode(data.sublist(start + 1, end), allowMalformed: true),
      );
    });

    // Leading space keeps the command out of history on shells with
    // HISTCONTROL=ignorespace; harmless elsewhere.
    write(utf8.encode(" printf '\\001%s\\001' \"\$PWD\"\r"));

    var timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(null);
    });
    final result = await completer.future;
    timer.cancel();
    await sub.cancel();
    final cwd = result?.trim();
    return (cwd == null || cwd.isEmpty) ? null : cwd;
  }

  /// Uploads local files into [remoteDir] over SFTP, sequentially, reporting
  /// per-file progress to [onProgress]. [cancelled] is polled between chunks
  /// and between files; when it turns true, [SftpUploadCancelled] is thrown.
  ///
  /// Non-regular-file paths (folders) are skipped and reported back via the
  /// returned list of skipped names.
  Future<List<String>> uploadFiles({
    required List<String> localPaths,
    required String remoteDir,
    void Function(SftpUploadProgress progress)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (_killed) {
      throw Exception('SSH 连接已断开，无法上传。');
    }
    final sftp = await _client.sftp();
    try {
      final separator = remoteDir.endsWith('/') ? '' : '/';
      final skipped = <String>[];
      for (var i = 0; i < localPaths.length; i++) {
        if (cancelled?.call() ?? false) throw SftpUploadCancelled();
        final localPath = localPaths[i];
        final file = File(localPath);
        if (!file.existsSync()) {
          skipped.add(localPath);
          continue;
        }
        final fileName = p.basename(localPath);
        final remotePath = '$remoteDir$separator$fileName';
        final total = file.lengthSync();

        final remote = await sftp.open(
          remotePath,
          mode: SftpFileOpenMode.create |
              SftpFileOpenMode.truncate |
              SftpFileOpenMode.write,
        );
        try {
          final writer = remote.write(
            file.openRead().map((chunk) {
              // Checked per chunk so even a huge single file can be aborted
              // mid-transfer; the throw fails writer.done below.
              if (cancelled?.call() ?? false) throw SftpUploadCancelled();
              return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
            }),
            onProgress: (sent) => onProgress?.call(SftpUploadProgress(
              fileIndex: i,
              fileCount: localPaths.length,
              fileName: fileName,
              sentBytes: sent,
              totalBytes: total,
            )),
          );
          await writer.done;
        } finally {
          await remote.close();
        }
      }
      return skipped;
    } finally {
      sftp.close();
    }
  }
}
