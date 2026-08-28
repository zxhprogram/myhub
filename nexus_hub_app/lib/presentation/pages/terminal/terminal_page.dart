import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/ssh_profile.dart';
import '../../states/terminal_state.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_toast.dart';
import '../../../theme/radii.dart';
import '../../../theme/typography.dart';
import 'session_sidebar.dart';
import 'ssh_pty_backend.dart';
import 'ssh_session_dialog.dart';
import 'terminal_session.dart';

/// A multi-session terminal embedded in a desktop window.
///
/// A sidebar lists the open sessions (local shells and SSH connections) plus
/// the saved SSH profiles; the content area shows the active session via an
/// [IndexedStack] so background sessions keep running while switched away.
/// Every session is a [TerminalSession] that owns its engine/controller and a
/// [PtyBackend] — [FlutterPtyBackend] for local shells, [SshPtyBackend] for
/// remote ones.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final List<TerminalSession> _sessions = [];
  String? _activeId;
  int _localCounter = 0;

  @override
  void initState() {
    super.initState();
    TerminalState.instance.init();
    _addLocalSession();
  }

  @override
  void dispose() {
    // Children unmount before this state disposes, so the views are already
    // gone when the sessions release their focus nodes.
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  TerminalSession? get _active => _sessions
      .where((s) => s.id == _activeId)
      .firstOrNull;

  // ── Session management ───────────────────────────────────────────────────

  void _addLocalSession() {
    final session = TerminalSession.local('本地 ${++_localCounter}');
    setState(() => _sessions.add(session));
    _activate(session);
  }

  void _addSshSession(SshProfile profile) {
    final session = TerminalSession.ssh(profile);
    setState(() => _sessions.add(session));
    _activate(session);
  }

  void _activate(TerminalSession session) {
    setState(() => _activeId = session.id);
    // Newly added sessions mount their view in this frame; existing ones can
    // be focused right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _activeId == session.id) {
        session.focusNode.requestFocus();
      }
    });
  }

  void _closeSession(TerminalSession session) {
    if (!_sessions.contains(session)) return;
    setState(() => _sessions.remove(session));
    // The view (and its focus node attachment) lives until this frame ends.
    WidgetsBinding.instance.addPostFrameCallback((_) => session.dispose());
    if (_activeId == session.id) {
      if (_sessions.isEmpty) {
        // Closing the last tab opens a fresh local one — a terminal window
        // always keeps at least one session.
        _addLocalSession();
      } else {
        _activate(_sessions.last);
      }
    }
  }

  // ── SSH profile actions ──────────────────────────────────────────────────

  Future<void> _newSshSession() async {
    final profile = await showSshSessionDialog(context);
    if (profile == null) return;
    await TerminalState.instance.addProfile(profile);
    if (!mounted) return;
    _addSshSession(profile);
  }

  Future<void> _editProfile(SshProfile profile) async {
    final updated = await showSshSessionDialog(context, initial: profile);
    if (updated == null) return;
    await TerminalState.instance.updateProfile(updated);
  }

  Future<void> _deleteProfile(SshProfile profile) async {
    final confirmed = await showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return AlertDialog(
            title: Text('删除 "${profile.name}"？', style: NexusTypography.headlineSm),
            content: Text(
              '仅删除保存的连接信息，不影响已打开的会话。',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            actions: [
              Button.text(
                onPressed: () => closeOverlay<bool>(context, false),
                child: const Text('取消'),
              ),
              Button.destructive(
                onPressed: () => closeOverlay<bool>(context, true),
                child: const Text('删除'),
              ),
            ],
          );
        },
      ),
    ).future;
    if (confirmed == true) {
      await TerminalState.instance.deleteProfile(profile.id);
    }
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final index = active == null ? 0 : _sessions.indexOf(active);
    return ColoredBox(
      // Dark terminal backdrop matching a typical alacritty palette.
      color: const Color(0xFF1A1A1E),
      child: Row(
        children: [
          TerminalSidebar(
            sessions: _sessions,
            activeId: _activeId,
            onActivate: _activate,
            onCloseSession: _closeSession,
            onNewLocal: _addLocalSession,
            onNewSsh: _newSshSession,
            onConnectProfile: _addSshSession,
            onEditProfile: _editProfile,
            onDeleteProfile: _deleteProfile,
          ),
          Expanded(
            child: _sessions.isEmpty
                ? const SizedBox.shrink()
                : IndexedStack(
                    index: index.clamp(0, _sessions.length - 1),
                    children: [
                      for (final session in _sessions) _SessionView(session: session),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// The content of one session tab: the terminal surface plus transient
/// overlays (drag-and-drop upload, SSH connecting spinner, exit/reconnect).
class _SessionView extends StatefulWidget {
  const _SessionView({required this.session});

  final TerminalSession session;

  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView> {
  TerminalSession get session => widget.session;

  /// True while OS files are being dragged over the terminal surface.
  bool _dragHovering = false;

  /// True while an SFTP batch upload is in flight.
  bool _uploading = false;

  /// Set by the cancel button; polled between chunks/files by the uploader.
  bool _cancelRequested = false;

  /// Remote directory the current batch is being written to.
  String? _targetDir;

  SftpUploadProgress? _progress;

  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _dragHovering = false);
    if (!session.canUpload || details.files.isEmpty) return;
    final paths = details.files.map((f) => f.path).toList();

    setState(() {
      _uploading = true;
      _cancelRequested = false;
      _targetDir = null;
      _progress = null;
    });
    try {
      // Probe the shell's cwd first so files land where the user is standing
      // (falls back to home when the probe times out).
      final dir = await session.resolveRemoteWorkingDirectory();
      if (!mounted) return;
      setState(() => _targetDir = dir);

      final skipped = await session.uploadFilesToRemote(
        remoteDir: dir,
        localPaths: paths,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        cancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      nexusToast(
        context,
        skipped.isEmpty
            ? '已上传 ${paths.length} 个文件到 $dir'
            : '已上传，跳过文件夹：${skipped.length} 个（暂不支持递归上传）',
      );
    } on SftpUploadCancelled {
      if (mounted) nexusToast(context, '已取消上传');
    } catch (e) {
      if (mounted) nexusToast(context, '上传失败：$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Watch((_) {
      if (session.exited.value) {
        return _buildExitLayer();
      }
      return DropTarget(
        enable: session.canUpload,
        onDragEntered: (_) => setState(() => _dragHovering = true),
        onDragExited: (_) => setState(() => _dragHovering = false),
        onDragDone: _handleDrop,
        child: Stack(
          children: [
            // The view stays mounted while connecting so its layout reports the
            // initial viewport size, which is what triggers the SSH connect.
            TerminalView(
              session.engine,
              controller: session.controller,
              focusNode: session.focusNode,
              autofocus: false,
              onPtyResize: session.onResize,
              theme: TerminalTheme.defaults,
              actions: {
                CopyIntent: CallbackAction<CopyIntent>(
                  onInvoke: (_) {
                    final text = session.engine.selectionText();
                    if (text != null && text.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: text));
                    }
                    return null;
                  },
                ),
                PasteIntent: CallbackAction<PasteIntent>(
                  onInvoke: (_) => session.paste(),
                ),
              },
            ),
            if (_dragHovering && !_uploading) _buildDragHintLayer(),
            if (_uploading) _buildUploadLayer(),
            if (session.connecting.value) _buildConnectingLayer(),
          ],
        ),
      );
    });
  }

  /// Highlight + hint while OS files hover over an SSH terminal.
  Widget _buildDragHintLayer() {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF7AA2F7), width: 2),
          color: const Color(0x337AA2F7),
        ),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xE61A1A1E),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            '松开鼠标，通过 SFTP 上传到当前目录',
            style: TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
          ),
        ),
      ),
    );
  }

  /// Progress card while a batch of dropped files is being uploaded.
  Widget _buildUploadLayer() {
    final progress = _progress;
    return ColoredBox(
      color: const Color(0xB31A1A1E),
      child: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF22222A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child:
                        CircularProgressIndicator(strokeWidth: 2.2, color: Color(0xFF7AA2F7)),
                  ),
                  SizedBox(width: 10),
                  Text('正在通过 SFTP 上传…',
                      style: TextStyle(
                          color: Color(0xFFEDEDED),
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              if (_targetDir != null) ...[
                const SizedBox(height: 8),
                Text('目标目录：$_targetDir',
                    style: const TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 14),
              if (progress != null) ...[
                LinearProgressIndicator(value: progress.fraction),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${progress.fileIndex + 1}/${progress.fileCount} · '
                        '${progress.fileName}',
                        style: const TextStyle(
                            color: Color(0xFFB9BDC7), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatBytes(progress.sentBytes)} / '
                      '${_formatBytes(progress.totalBytes)}',
                      style: const TextStyle(
                          color: Color(0xFFB9BDC7), fontSize: 12),
                    ),
                  ],
                ),
              ] else
                const LinearProgressIndicator(),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: NexusButton(
                  label: '取消上传',
                  variant: NexusButtonVariant.outlined,
                  onPressed: () => _cancelRequested = true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  /// Full-surface overlay while the SSH connection is being established.
  Widget _buildConnectingLayer() {
    final profile = session.profile;
    return ColoredBox(
      color: const Color(0xF01A1A1E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Color(0xFF7AA2F7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              profile == null
                  ? '正在连接…'
                  : '正在连接 ${profile.name}（${profile.endpoint}）…',
              style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  /// A full-surface overlay shown after the shell exits; tap to restart.
  Widget _buildExitLayer() {
    final isSsh = session.kind == TerminalSessionKind.ssh;
    return GestureDetector(
      onTap: session.restart,
      child: Container(
        color: const Color(0xFF000000).withValues(alpha: 0.7),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xCC1A1A1A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${session.exitMessage ?? 'process exited'} — 点击任意处${isSsh ? '重连' : '重启'}',
            style: const TextStyle(color: Color(0xFFEDEDED), fontSize: 14),
          ),
        ),
      ),
    );
  }
}
