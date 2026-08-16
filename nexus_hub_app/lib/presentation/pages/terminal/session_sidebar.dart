import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/ssh_profile.dart';
import '../../states/terminal_state.dart';
import 'terminal_session.dart';

/// Side panel of the Terminal app: active session tabs on top, saved SSH
/// connection profiles below. Always rendered in a dark palette that matches
/// the terminal surface, regardless of the app theme.
class TerminalSidebar extends StatelessWidget {
  const TerminalSidebar({
    super.key,
    required this.sessions,
    required this.activeId,
    required this.onActivate,
    required this.onCloseSession,
    required this.onNewLocal,
    required this.onNewSsh,
    required this.onConnectProfile,
    required this.onEditProfile,
    required this.onDeleteProfile,
  });

  final List<TerminalSession> sessions;
  final String? activeId;
  final ValueChanged<TerminalSession> onActivate;
  final ValueChanged<TerminalSession> onCloseSession;
  final VoidCallback onNewLocal;
  final VoidCallback onNewSsh;
  final ValueChanged<SshProfile> onConnectProfile;
  final ValueChanged<SshProfile> onEditProfile;
  final ValueChanged<SshProfile> onDeleteProfile;

  static const _background = Color(0xFF1E1E24);
  static const _divider = Color(0xFF2B2B33);
  static const _textPrimary = Color(0xFFE6E6EC);
  static const _textSecondary = Color(0xFF9B9BA6);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _background,
      child: SizedBox(
        width: 232,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const Divider(color: _divider, height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  ...sessions.map(
                    (s) => _SessionRow(
                      session: s,
                      active: s.id == activeId,
                      onTap: () => onActivate(s),
                      onClose: () => onCloseSession(s),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: _divider, height: 1, indent: 12, endIndent: 12),
                  const SizedBox(height: 8),
                  _buildSectionLabel('SSH 连接'),
                  Watch((_) {
                    final profiles = TerminalState.instance.profiles.value;
                    if (profiles.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(
                          '暂无保存的连接，\n点击上方 + 新增 SSH 会话',
                          style: TextStyle(color: _textSecondary, fontSize: 12, height: 1.6),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final p in profiles)
                          _ProfileRow(
                            profile: p,
                            onTap: () => onConnectProfile(p),
                            onEdit: () => onEditProfile(p),
                            onDelete: () => onDeleteProfile(p),
                          ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '会话',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.add, size: 20, color: _textSecondary),
            color: const Color(0xFF26262E),
            tooltip: '新增会话',
            onSelected: (value) {
              if (value == 'local') onNewLocal();
              if (value == 'ssh') onNewSsh();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'local',
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.terminal, size: 18, color: _textSecondary),
                    SizedBox(width: 10),
                    Text('新建本地会话', style: TextStyle(color: _textPrimary, fontSize: 13)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'ssh',
                height: 40,
                child: Row(
                  children: [
                    Icon(Icons.dns_outlined, size: 18, color: _textSecondary),
                    SizedBox(width: 10),
                    Text('新建 SSH 会话…', style: TextStyle(color: _textPrimary, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Text(
        label,
        style: const TextStyle(
          color: _textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// One active-session row: status indicator, title (endpoint for SSH),
/// close button on hover.
class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.session,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final TerminalSession session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 4),
          color: widget.active
              ? const Color(0xFF2E2E3A)
              : _hovering
                  ? const Color(0xFF26262E)
                  : Colors.transparent,
          child: Row(
            children: [
              // Status indicator reacts to connection/exit signals.
              Watch((_) {
                if (s.connecting.value) {
                  return const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      valueColor: AlwaysStoppedAnimation<Color>(_SessionPalette.accent),
                    ),
                  );
                }
                if (s.exited.value) {
                  return const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: _SessionPalette.error,
                  );
                }
                return Icon(
                  s.kind == TerminalSessionKind.ssh
                      ? Icons.dns_outlined
                      : Icons.terminal,
                  size: 16,
                  color: widget.active
                      ? _SessionPalette.accent
                      : _SessionPalette.secondary,
                );
              }),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.active
                            ? _SessionPalette.primary
                            : _SessionPalette.secondary,
                        fontSize: 13,
                        fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (s.kind == TerminalSessionKind.ssh && s.profile != null)
                      Text(
                        s.profile!.endpoint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _SessionPalette.faint,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (_hovering)
                SizedBox(
                  width: 26,
                  height: 26,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 14,
                    tooltip: '关闭会话',
                    icon: const Icon(Icons.close, color: _SessionPalette.faint),
                    onPressed: widget.onClose,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One saved-profile row: tap to open a new connection; edit/delete trailing.
class _ProfileRow extends StatefulWidget {
  const _ProfileRow({
    required this.profile,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final SshProfile profile;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends State<_ProfileRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.only(left: 12, right: 4),
          color: _hovering ? const Color(0xFF26262E) : Colors.transparent,
          child: Row(
            children: [
              const Icon(
                Icons.bookmark_outline,
                size: 16,
                color: _SessionPalette.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _SessionPalette.primary,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      widget.profile.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _SessionPalette.faint,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hovering) ...[
                _iconButton(Icons.edit_outlined, '编辑', widget.onEdit),
                _iconButton(Icons.delete_outline, '删除', widget.onDelete),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 14,
        tooltip: tooltip,
        icon: Icon(icon, color: _SessionPalette.faint),
        onPressed: onPressed,
      ),
    );
  }
}

/// Palette shared by the sidebar rows (kept separate so the top-level widget
/// colors stay readable).
class _SessionPalette {
  static const primary = Color(0xFFE6E6EC);
  static const secondary = Color(0xFF9B9BA6);
  static const faint = Color(0xFF6E6E7A);
  static const accent = Color(0xFF7AA2F7);
  static const error = Color(0xFFF7768E);
}
