import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:signals_flutter/signals_flutter.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

import '../../data/models/mail_account_model.dart';
import '../../data/models/mail_item_model.dart';
import '../../data/repositories/mail_repository.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/mail_body_view.dart';
import '../components/nexus_avatar.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_chip.dart';
import '../components/nexus_input.dart';
import '../components/nexus_toast.dart';
import '../states/mail_state.dart';
import 'mail_compose_dialog.dart';

class MailPage extends StatefulWidget {
  const MailPage({super.key, this.repository});

  final MailRepository? repository;

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  late final MailState _state;

  @override
  void initState() {
    super.initState();
    _state = MailState(repository: widget.repository);
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.background,
      child: Watch((context) {
        if (!_state.hasValidAccount.value || _state.isEditingAccount.value) {
          return _MailAccountSetup(
            state: _state,
            isEditing: _state.hasValidAccount.value,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 960;
            return Column(
              children: [
                _MailToolbar(state: _state, isWide: isWide),
                Expanded(
                  child: isWide ? _buildWideLayout() : _buildNarrowLayout(),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  Widget _buildWideLayout() {
    return Watch((context) {
      final showSidebar = _state.isSidebarVisible.value;
      return Row(
        children: [
          if (showSidebar) ...[
            SizedBox(width: 220, child: _FolderSidebar(state: _state)),
            const VerticalDivider(width: 1),
          ],
          SizedBox(width: 360, child: _MessageList(state: _state)),
          const VerticalDivider(width: 1),
          Expanded(child: _ReadingPane(state: _state)),
        ],
      );
    });
  }

  Widget _buildNarrowLayout() {
    return Watch((context) {
      final selected = _state.selectedEmail.value;
      final showSidebar = _state.isSidebarVisible.value;
      if (selected == null) {
        return Row(
          children: [
            if (showSidebar) ...[
              SizedBox(width: 200, child: _FolderSidebar(state: _state)),
              const VerticalDivider(width: 1),
            ],
            Expanded(child: _MessageList(state: _state)),
          ],
        );
      }
      return _ReadingPane(state: _state, showBackButton: true);
    });
  }
}

/// macOS Mail Top Unified Navigation & Action Toolbar
class _MailToolbar extends StatelessWidget {
  const _MailToolbar({required this.state, required this.isWide});

  final MailState state;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Watch((context) {
        final selected = state.selectedEmail.value;
        final hasSelection = selected != null;
        final isSidebarOpen = state.isSidebarVisible.value;
        final isFlagged =
            selected != null && state.flaggedUids.value.contains(selected.uid);

        return Row(
          children: [
            // Sidebar toggle button
            _MacToolbarButton(
              icon: LucideIcons.panelLeft,
              tooltip: isSidebarOpen ? 'Hide Mailboxes' : 'Show Mailboxes',
              isActive: isSidebarOpen,
              onTap: state.toggleSidebar,
            ),
            const SizedBox(width: 4),

            // macOS Compose Button (Blue accent capsule)
            _MacComposeButton(onPressed: () => _showComposeDialog(context)),
            const SizedBox(width: 4),

            // Get Mail / Refresh button
            _MacToolbarButton(
              icon: LucideIcons.refreshCw,
              tooltip: 'Get Mail',
              isLoading: state.isLoading.value,
              onTap: () => state.refresh(),
            ),

            const SizedBox(width: 6),
            Container(width: 1, height: 20, color: colorScheme.border),
            const SizedBox(width: 6),

            // Action buttons enabled when an email is selected
            _MacToolbarButton(
              icon: LucideIcons.trash2,
              tooltip: 'Move to Trash',
              enabled: hasSelection,
              onTap: () {
                if (selected != null) {
                  nexusToast(context, 'Message moved to Trash');
                  state.selectEmail(null);
                }
              },
            ),
            _MacToolbarButton(
              icon: LucideIcons.archive,
              tooltip: 'Archive',
              enabled: hasSelection,
              onTap: () {
                if (selected != null) {
                  nexusToast(context, 'Message archived');
                  state.selectEmail(null);
                }
              },
            ),
            _MacToolbarButton(
              icon: LucideIcons.reply,
              tooltip: 'Reply',
              enabled: hasSelection,
              onTap: () => _showReplyDialog(context),
            ),
            _MacToolbarButton(
              icon: LucideIcons.replyAll,
              tooltip: 'Reply All',
              enabled: hasSelection,
              onTap: () => _showReplyDialog(context),
            ),
            _MacToolbarButton(
              icon: LucideIcons.forward,
              tooltip: 'Forward',
              enabled: hasSelection,
              onTap: () => _showForwardDialog(context),
            ),
            _MacToolbarButton(
              icon: selected?.isRead == true
                  ? LucideIcons.mail
                  : LucideIcons.mailOpen,
              tooltip: selected?.isRead == true
                  ? 'Mark as Unread'
                  : 'Mark as Read',
              enabled: hasSelection,
              onTap: () {
                if (selected != null) {
                  if (selected.isRead) {
                    state.markAsUnread(selected);
                  } else {
                    state.markAsRead(selected);
                  }
                }
              },
            ),
            _MacToolbarButton(
              icon: LucideIcons.flag,
              tooltip: isFlagged ? 'Remove Flag' : 'Flag Message',
              enabled: hasSelection,
              iconColor: isFlagged ? const Color(0xFFFF9F0A) : null,
              onTap: () {
                if (selected != null) {
                  state.toggleFlag(selected);
                }
              },
            ),

            const Spacer(),

            // Center/Right: Mailbox title breadcrumb
            if (isWide) ...[
              Text(
                state.selectedFolder.value,
                style: NexusTypography.labelMd.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.foreground,
                ),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 16, color: colorScheme.border),
              const SizedBox(width: 8),
            ],

            // macOS Capsule Search Input
            SizedBox(
              width: isWide ? 220 : 160,
              height: 30,
              child: _MacSearchField(
                initialValue: state.searchQuery.value,
                onChanged: (val) => state.search(val),
              ),
            ),
            const SizedBox(width: 6),

            // Settings gear button
            _MacToolbarButton(
              icon: RadixIcons.gear,
              tooltip: 'Mail Settings',
              onTap: () => state.startAccountEdit(),
            ),
          ],
        );
      }),
    );
  }

  void _showComposeDialog(BuildContext context) {
    showOverlay(
      context,
      const DialogConfiguration(barrierColor: Color.fromRGBO(0, 0, 0, 0.54)),
      builder: (context) => MailComposeDialog(state: state),
    );
  }

  void _showReplyDialog(BuildContext context) {
    final item = state.selectedEmail.value;
    final message = state.selectedEmailMessage.value;
    if (item == null) return;
    final subject = item.subject.startsWith('Re:')
        ? item.subject
        : 'Re: ${item.subject}';
    final quoteBody = _buildQuoteBody(item, message);
    showOverlay(
      context,
      const DialogConfiguration(barrierColor: Color.fromRGBO(0, 0, 0, 0.54)),
      builder: (context) => MailComposeDialog(
        state: state,
        initialTo: [item.senderAddress],
        initialSubject: subject,
        initialBodyDeltaJson: quoteBody,
      ),
    );
  }

  void _showForwardDialog(BuildContext context) {
    final item = state.selectedEmail.value;
    final message = state.selectedEmailMessage.value;
    if (item == null) return;
    final subject = item.subject.startsWith('Fwd:')
        ? item.subject
        : 'Fwd: ${item.subject}';
    final quoteBody = _buildQuoteBody(item, message);
    showOverlay(
      context,
      const DialogConfiguration(barrierColor: Color.fromRGBO(0, 0, 0, 0.54)),
      builder: (context) => MailComposeDialog(
        state: state,
        initialSubject: subject,
        initialBodyDeltaJson: quoteBody,
      ),
    );
  }

  String _buildQuoteBody(MailItem item, MailMessage? message) {
    final sender = item.senderName.isEmpty
        ? item.senderAddress
        : item.senderName;
    final dateStr = item.date != null
        ? DateFormat('EEE, MMM d, y h:mm a').format(item.date!.toLocal())
        : '';
    final originalText = message?.plainTextBody.isNotEmpty == true
        ? message!.plainTextBody
        : _stripHtml(message?.htmlBody ?? '');
    final quoted = originalText.split('\n').map((line) => '> $line').join('\n');
    return '\n\nOn $dateStr, $sender wrote:\n$quoted';
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }
}

/// macOS Compose Action Pill Button
class _MacComposeButton extends StatelessWidget {
  const _MacComposeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF007AFF),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF007AFF).withValues(alpha: 0.25),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              LucideIcons.squarePen,
              size: 14,
              color: Color(0xFFFFFFFF),
            ),
            const SizedBox(width: 5),
            Text(
              'Compose',
              style: NexusTypography.labelSm.copyWith(
                color: const Color(0xFFFFFFFF),
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// macOS Style Toolbar Icon Button
class _MacToolbarButton extends StatefulWidget {
  const _MacToolbarButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.isActive = false,
    this.isLoading = false,
    this.enabled = true,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool isActive;
  final bool isLoading;
  final bool enabled;
  final Color? iconColor;

  @override
  State<_MacToolbarButton> createState() => _MacToolbarButtonState();
}

class _MacToolbarButtonState extends State<_MacToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveColor = !widget.enabled
        ? colorScheme.mutedForeground.withValues(alpha: 0.35)
        : widget.iconColor ??
              (widget.isActive
                  ? const Color(0xFF007AFF)
                  : _hovered
                  ? colorScheme.foreground
                  : colorScheme.mutedForeground);

    final bg = widget.isActive
        ? colorScheme.muted.withValues(alpha: 0.6)
        : _hovered && widget.enabled
        ? colorScheme.muted.withValues(alpha: 0.45)
        : Colors.transparent;

    Widget child = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: Container(
          width: 32,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF007AFF),
                  ),
                )
              : Icon(widget.icon, size: 16, color: effectiveColor),
        ),
      ),
    );

    if (widget.tooltip != null) {
      child = Tooltip(
        tooltip: (context) => Text(widget.tooltip!),
        child: child,
      );
    }
    return child;
  }
}

/// macOS Search Capsule Input
class _MacSearchField extends StatefulWidget {
  const _MacSearchField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_MacSearchField> createState() => _MacSearchFieldState();
}

class _MacSearchFieldState extends State<_MacSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NexusInput(
      controller: _controller,
      hintText: 'Search Mail...',
      prefixIcon: const Icon(RadixIcons.magnifyingGlass, size: 14),
      onChanged: widget.onChanged,
    );
  }
}

/// macOS Mailboxes Sidebar (Source List)
class _FolderSidebar extends StatelessWidget {
  const _FolderSidebar({required this.state});

  final MailState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.muted.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader(context, 'MAILBOXES'),
                  _buildMailboxes(context),
                  const SizedBox(height: 12),
                  _buildSectionHeader(context, 'SMART FILTERS'),
                  _buildSmartFilters(context),
                  const SizedBox(height: 12),
                  _buildSectionHeader(context, 'TAGS & LABELS'),
                  _buildLabels(context),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          _buildAccountStatusCard(context),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
      child: Text(
        title,
        style: NexusTypography.labelSm.copyWith(
          fontSize: 10.5,
          letterSpacing: 0.5,
          fontWeight: FontWeight.w700,
          color: colorScheme.mutedForeground.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildMailboxes(BuildContext context) {
    return Watch((context) {
      final selected = state.selectedFolder.value;
      final counts = state.unreadCounts.value;
      final activeFilter = state.activeFilter.value;
      final activeLabel = state.activeLabel.value;

      return Column(
        children: state.folders.value.map((folder) {
          final count = counts[folder.id] ?? 0;
          final isSelected =
              folder.id == selected &&
              activeFilter == 'all' &&
              activeLabel == null;
          final color = _getFolderColor(folder.id);

          return _SidebarItemRow(
            icon: folder.icon,
            label: folder.title,
            count: count,
            iconColor: color,
            isSelected: isSelected,
            onTap: () {
              state.setFilter('all');
              state.loadFolder(folder.id);
            },
          );
        }).toList(),
      );
    });
  }

  Widget _buildSmartFilters(BuildContext context) {
    return Watch((context) {
      final filter = state.activeFilter.value;
      final activeLabel = state.activeLabel.value;
      final unreadCount = state.emails.value.where((e) => !e.isRead).length;
      final flaggedCount = state.flaggedUids.value.length;

      return Column(
        children: [
          _SidebarItemRow(
            icon: LucideIcons.circleDot,
            label: 'Unread Only',
            count: unreadCount,
            iconColor: const Color(0xFF007AFF),
            isSelected: filter == 'unread' && activeLabel == null,
            onTap: () => state.setFilter(filter == 'unread' ? 'all' : 'unread'),
          ),
          _SidebarItemRow(
            icon: LucideIcons.flag,
            label: 'Flagged',
            count: flaggedCount,
            iconColor: const Color(0xFFFF9F0A),
            isSelected: filter == 'flagged' && activeLabel == null,
            onTap: () =>
                state.setFilter(filter == 'flagged' ? 'all' : 'flagged'),
          ),
        ],
      );
    });
  }

  Widget _buildLabels(BuildContext context) {
    return Watch((context) {
      final activeLabel = state.activeLabel.value;
      return Column(
        children: state.labels.value.map((label) {
          final color = _getLabelColor(label);
          final isSelected = activeLabel == label;
          return _SidebarItemRow(
            icon: LucideIcons.tag,
            label: label,
            iconColor: color,
            isSelected: isSelected,
            onTap: () => state.setLabel(isSelected ? null : label),
          );
        }).toList(),
      );
    });
  }

  Widget _buildAccountStatusCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((context) {
      final account = state.account.value;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: colorScheme.card,
        child: Row(
          children: [
            Stack(
              children: [
                NexusAvatar(
                  label: account.emailAddress.isNotEmpty
                      ? account.emailAddress
                      : 'User',
                  size: 26,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFF34C759),
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.card, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account.emailAddress.isNotEmpty
                        ? account.emailAddress
                        : 'Connected',
                    style: NexusTypography.labelSm.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Online • IMAP SSL',
                    style: NexusTypography.bodyMd.copyWith(
                      fontSize: 10,
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => state.startAccountEdit(),
              child: Icon(
                RadixIcons.gear,
                size: 14,
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    });
  }

  Color _getFolderColor(String folderId) {
    return switch (folderId.toUpperCase()) {
      'INBOX' => const Color(0xFF007AFF),
      'SENT' => const Color(0xFF34C759),
      'DRAFTS' => const Color(0xFFFF9500),
      'TRASH' => const Color(0xFF8E8E93),
      'SPAM' => const Color(0xFFFF3B30),
      _ => const Color(0xFFAF52DE),
    };
  }

  Color _getLabelColor(String label) {
    return switch (label.toLowerCase()) {
      'work' => const Color(0xFF007AFF),
      'personal' => const Color(0xFF9333EA),
      'finance' => const Color(0xFF10B981),
      'social' => const Color(0xFFF59E0B),
      _ => const Color(0xFF64748B),
    };
  }
}

/// macOS Sidebar Row Item
class _SidebarItemRow extends StatefulWidget {
  const _SidebarItemRow({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.count = 0,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int count;
  final Color? iconColor;

  @override
  State<_SidebarItemRow> createState() => _SidebarItemRowState();
}

class _SidebarItemRowState extends State<_SidebarItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = widget.isSelected;

    final bg = isSelected
        ? const Color(0xFF007AFF)
        : _hovered
        ? colorScheme.muted.withValues(alpha: 0.4)
        : Colors.transparent;

    final textColor = isSelected
        ? const Color(0xFFFFFFFF)
        : colorScheme.foreground;

    final iconColor = isSelected
        ? const Color(0xFFFFFFFF)
        : (widget.iconColor ?? colorScheme.mutedForeground);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: NexusTypography.bodyMd.copyWith(
                    color: textColor,
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFFFFFF).withValues(alpha: 0.25)
                        : colorScheme.muted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.count.toString(),
                    style: NexusTypography.labelSm.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? const Color(0xFFFFFFFF)
                          : colorScheme.mutedForeground,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS Message List (Middle Column) - High Information Density
class _MessageList extends StatelessWidget {
  const _MessageList({required this.state});

  final MailState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(
            child: Watch((context) {
              final colorScheme = Theme.of(context).colorScheme;
              if (state.isLoading.value && state.emails.value.isEmpty) {
                return _buildShimmer(colorScheme);
              }
              if (state.error.value != null && state.emails.value.isEmpty) {
                return _ErrorState(
                  message: state.error.value!,
                  onRetry: state.retry,
                );
              }
              final list = state.visibleEmails;
              if (list.isEmpty) {
                return _EmptyState(
                  message: state.activeFilter.value == 'unread'
                      ? 'No unread messages.'
                      : state.activeFilter.value == 'flagged'
                      ? 'No flagged messages.'
                      : 'No messages in this folder.',
                );
              }
              return RefreshTrigger(
                onRefresh: () async {
                  await state.refresh();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 4,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    return _MacMessageCard(
                      item: item,
                      isSelected: state.selectedEmail.value?.uid == item.uid,
                      isFlagged: state.flaggedUids.value.contains(item.uid),
                      onTap: () => state.selectEmail(item),
                      onToggleFlag: () => state.toggleFlag(item),
                      onToggleRead: () {
                        if (item.isRead) {
                          state.markAsUnread(item);
                        } else {
                          state.markAsRead(item);
                        }
                      },
                    );
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((context) {
      final list = state.visibleEmails;
      final activeFilter = state.activeFilter.value;
      final unreadCount = state.emails.value.where((e) => !e.isRead).length;

      return Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colorScheme.card,
          border: Border(bottom: BorderSide(color: colorScheme.border)),
        ),
        child: Row(
          children: [
            // Folder title & count
            Text(
              state.selectedFolder.value,
              style: NexusTypography.labelMd.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.muted,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${list.length}${unreadCount > 0 ? " ($unreadCount unread)" : ""}',
                style: NexusTypography.labelSm.copyWith(
                  fontSize: 10.5,
                  color: colorScheme.mutedForeground,
                ),
              ),
            ),

            const Spacer(),

            // Segmented filter control: All / Unread / Flagged
            Container(
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: colorScheme.muted.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  _FilterSegmentPill(
                    label: 'All',
                    isSelected: activeFilter == 'all',
                    onTap: () => state.setFilter('all'),
                  ),
                  _FilterSegmentPill(
                    label: 'Unread',
                    isSelected: activeFilter == 'unread',
                    onTap: () => state.setFilter('unread'),
                  ),
                  _FilterSegmentPill(
                    label: 'Flagged',
                    isSelected: activeFilter == 'flagged',
                    onTap: () => state.setFilter('flagged'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildShimmer(ColorScheme colorScheme) {
    return Shimmer.fromColors(
      baseColor: colorScheme.muted,
      highlightColor: colorScheme.accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(4),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Container(
            height: 58,
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: colorScheme.card,
              borderRadius: BorderRadius.circular(5),
            ),
          );
        },
      ),
    );
  }
}

class _FilterSegmentPill extends StatelessWidget {
  const _FilterSegmentPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.card : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? colorScheme.foreground
                : colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}

/// macOS Mail List Row — Compact High-Density Style (Matches native Mail.app)
class _MacMessageCard extends StatefulWidget {
  const _MacMessageCard({
    required this.item,
    required this.isSelected,
    required this.isFlagged,
    required this.onTap,
    required this.onToggleFlag,
    required this.onToggleRead,
  });

  final MailItem item;
  final bool isSelected;
  final bool isFlagged;
  final VoidCallback onTap;
  final VoidCallback onToggleFlag;
  final VoidCallback onToggleRead;

  @override
  State<_MacMessageCard> createState() => _MacMessageCardState();
}

class _MacMessageCardState extends State<_MacMessageCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = widget.isSelected;
    final item = widget.item;
    final isUnread = !item.isRead;

    final bg = isSelected
        ? const Color(0xFF007AFF)
        : _hovered
        ? colorScheme.muted.withValues(alpha: 0.35)
        : Colors.transparent;

    final primaryText = isSelected
        ? const Color(0xFFFFFFFF)
        : colorScheme.foreground;

    final secondaryText = isSelected
        ? const Color(0xFFFFFFFF).withValues(alpha: 0.8)
        : colorScheme.mutedForeground;

    final senderColor = isSelected
        ? const Color(0xFFFFFFFF)
        : isUnread
        ? colorScheme.foreground
        : colorScheme.foreground.withValues(alpha: 0.72);

    // Indent used to align subject/snippet with sender text after unread dot
    const dotColumnWidth = 12.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTap: () => widget.onToggleRead(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: Border(
              bottom: BorderSide(
                color: isSelected
                    ? Colors.transparent
                    : colorScheme.border.withValues(alpha: 0.35),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Line 1: Unread Dot + Sender + Flag + Date
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: dotColumnWidth,
                    child: isUnread
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFFFFFF)
                                    : const Color(0xFF007AFF),
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    child: Text(
                      item.senderName.isEmpty
                          ? item.senderAddress
                          : item.senderName,
                      style: NexusTypography.labelMd.copyWith(
                        color: senderColor,
                        fontWeight: isUnread
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (widget.isFlagged)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        LucideIcons.flag,
                        size: 11,
                        color: isSelected
                            ? const Color(0xFFFFD60A)
                            : const Color(0xFFFF9F0A),
                      ),
                    ),
                  Text(
                    _formatDate(item.date),
                    style: NexusTypography.labelSm.copyWith(
                      color: secondaryText,
                      fontSize: 10.5,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),

              // Line 2: Subject + Label chips (inline, high density)
              Padding(
                padding: const EdgeInsets.only(left: dotColumnWidth),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.subject.isEmpty ? '(No Subject)' : item.subject,
                        style: NexusTypography.bodyMd.copyWith(
                          color: primaryText.withValues(
                            alpha: isUnread || isSelected ? 1 : 0.8,
                          ),
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.w400,
                          fontSize: 12,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.labels.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      ...item.labels.take(2).map((label) {
                        return Container(
                          margin: const EdgeInsets.only(left: 3),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 0.5,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(
                                    0xFFFFFFFF,
                                  ).withValues(alpha: 0.25)
                                : _labelColor(
                                    colorScheme,
                                    label,
                                  ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? const Color(0xFFFFFFFF)
                                  : _labelColor(colorScheme, label),
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),

              // Line 3: One-line snippet preview
              Padding(
                padding: const EdgeInsets.only(left: dotColumnWidth),
                child: Text(
                  item.snippet.isNotEmpty
                      ? item.snippet
                      : 'No preview available',
                  style: NexusTypography.bodyMd.copyWith(
                    color: secondaryText,
                    fontSize: 11,
                    height: 1.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// macOS Reading Pane (Right Column)
class _ReadingPane extends StatelessWidget {
  const _ReadingPane({required this.state, this.showBackButton = false});

  final MailState state;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.background,
      child: Watch((context) {
        final item = state.selectedEmail.value;
        if (item == null) {
          return _MacReadingEmptyState();
        }
        final error = state.messageError.value;
        if (error != null) {
          return _ErrorState(
            message: error,
            onRetry: () => state.selectEmail(item),
          );
        }
        final message = state.selectedEmailMessage.value;
        if (message == null) {
          return const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          );
        }

        final isFlagged = state.flaggedUids.value.contains(item.uid);

        return Column(
          children: [
            // Reading Toolbar
            _buildReadingToolbar(context, item, isFlagged),

            // Reading Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  NexusSpacing.md,
                  NexusSpacing.sm,
                  NexusSpacing.md,
                  NexusSpacing.md,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSubjectHeader(item, colorScheme),
                      const SizedBox(height: 8),
                      _buildSenderCard(context, item, colorScheme),
                      const SizedBox(height: 12),
                      if (message.attachments.isNotEmpty) ...[
                        _buildAttachmentsGallery(message, colorScheme),
                        const SizedBox(height: 12),
                      ],
                      _buildBody(message),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildReadingToolbar(
    BuildContext context,
    MailItem item,
    bool isFlagged,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.card,
        border: Border(bottom: BorderSide(color: colorScheme.border)),
      ),
      child: Row(
        children: [
          if (showBackButton)
            _MacToolbarButton(
              icon: RadixIcons.arrowLeft,
              tooltip: 'Back to List',
              onTap: () => state.selectEmail(null),
            ),
          _MacToolbarButton(
            icon: LucideIcons.reply,
            tooltip: 'Reply',
            onTap: () => _showReplyDialog(context),
          ),
          _MacToolbarButton(
            icon: LucideIcons.replyAll,
            tooltip: 'Reply All',
            onTap: () => _showReplyDialog(context),
          ),
          _MacToolbarButton(
            icon: LucideIcons.forward,
            tooltip: 'Forward',
            onTap: () => _showForwardDialog(context),
          ),
          Container(width: 1, height: 18, color: colorScheme.border),
          _MacToolbarButton(
            icon: LucideIcons.trash2,
            tooltip: 'Move to Trash',
            onTap: () {
              nexusToast(context, 'Message moved to Trash');
              state.selectEmail(null);
            },
          ),
          _MacToolbarButton(
            icon: LucideIcons.archive,
            tooltip: 'Archive',
            onTap: () {
              nexusToast(context, 'Message archived');
              state.selectEmail(null);
            },
          ),
          _MacToolbarButton(
            icon: LucideIcons.flag,
            tooltip: isFlagged ? 'Remove Flag' : 'Flag Message',
            iconColor: isFlagged ? const Color(0xFFFF9F0A) : null,
            onTap: () => state.toggleFlag(item),
          ),
          const Spacer(),
          _MacToolbarButton(
            icon: LucideIcons.mail,
            tooltip: 'Mark as Unread',
            onTap: () {
              state.markAsUnread(item);
              nexusToast(context, 'Marked as unread');
            },
          ),
        ],
      ),
    );
  }

  void _showReplyDialog(BuildContext context) {
    final item = state.selectedEmail.value;
    final message = state.selectedEmailMessage.value;
    if (item == null) return;
    final subject = item.subject.startsWith('Re:')
        ? item.subject
        : 'Re: ${item.subject}';
    final quoteBody = _buildQuoteBody(item, message);
    showOverlay(
      context,
      const DialogConfiguration(barrierColor: Color.fromRGBO(0, 0, 0, 0.54)),
      builder: (context) => MailComposeDialog(
        state: state,
        initialTo: [item.senderAddress],
        initialSubject: subject,
        initialBodyDeltaJson: quoteBody,
      ),
    );
  }

  void _showForwardDialog(BuildContext context) {
    final item = state.selectedEmail.value;
    final message = state.selectedEmailMessage.value;
    if (item == null) return;
    final subject = item.subject.startsWith('Fwd:')
        ? item.subject
        : 'Fwd: ${item.subject}';
    final quoteBody = _buildQuoteBody(item, message);
    showOverlay(
      context,
      const DialogConfiguration(barrierColor: Color.fromRGBO(0, 0, 0, 0.54)),
      builder: (context) => MailComposeDialog(
        state: state,
        initialSubject: subject,
        initialBodyDeltaJson: quoteBody,
      ),
    );
  }

  String _buildQuoteBody(MailItem item, MailMessage? message) {
    final sender = item.senderName.isEmpty
        ? item.senderAddress
        : item.senderName;
    final dateStr = item.date != null
        ? DateFormat('EEE, MMM d, y h:mm a').format(item.date!.toLocal())
        : '';
    final originalText = message?.plainTextBody.isNotEmpty == true
        ? message!.plainTextBody
        : _stripHtml(message?.htmlBody ?? '');
    final quoted = originalText.split('\n').map((line) => '> $line').join('\n');
    return '\n\nOn $dateStr, $sender wrote:\n$quoted';
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  Widget _buildSubjectHeader(MailItem item, ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            item.subject.isEmpty ? '(No Subject)' : item.subject,
            style: NexusTypography.headlineLg.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontSize: 19,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: NexusSpacing.md),
        ...item.labels.map((label) {
          return Padding(
            padding: const EdgeInsets.only(left: NexusSpacing.xs),
            child: NexusChip(
              label: label,
              color: _labelColor(colorScheme, label),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSenderCard(
    BuildContext context,
    MailItem item,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border(
          top: BorderSide(
            color: colorScheme.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
          bottom: BorderSide(
            color: colorScheme.border.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          NexusAvatar(
            label: item.senderName.isEmpty
                ? item.senderAddress
                : item.senderName,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Row 1: Sender name + address + Signed badge
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.senderName.isEmpty
                            ? item.senderAddress
                            : item.senderName,
                        style: NexusTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.senderName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '<${item.senderAddress}>',
                          style: NexusTypography.bodyMd.copyWith(
                            color: colorScheme.mutedForeground,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF34C759).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            LucideIcons.shieldCheck,
                            size: 10,
                            color: Color(0xFF34C759),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Signed',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF34C759),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // Row 2: To + full date on one compact line
                Text(
                  'To: ${state.account.value.emailAddress}  •  ${_formatDate(item.date, full: true)}',
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.mutedForeground,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsGallery(
    MailMessage message,
    ColorScheme colorScheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              LucideIcons.paperclip,
              size: 14,
              color: colorScheme.mutedForeground,
            ),
            const SizedBox(width: 6),
            Text(
              'Attachments (${message.attachments.length})',
              style: NexusTypography.labelSm.copyWith(
                fontWeight: FontWeight.w700,
                color: colorScheme.foreground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: message.attachments.map((attachment) {
            return Container(
              width: 220,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colorScheme.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.fileText,
                      color: Color(0xFF007AFF),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName,
                          style: NexusTypography.labelSm.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${(attachment.size / 1024).ceil()} KB',
                          style: NexusTypography.bodyMd.copyWith(
                            fontSize: 10.5,
                            color: colorScheme.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    LucideIcons.download,
                    size: 15,
                    color: colorScheme.mutedForeground,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildBody(MailMessage message) {
    return MailBodyView(message: message);
  }
}

/// macOS Mail Minimalistic Empty Reading State
class _MacReadingEmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.muted.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              LucideIcons.mail,
              size: 30,
              color: colorScheme.mutedForeground.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No Message Selected',
            style: NexusTypography.headlineSm.copyWith(
              fontWeight: FontWeight.w600,
              color: colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Select an email from the list to view its contents',
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground.withValues(alpha: 0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            LucideIcons.inbox,
            size: 36,
            color: colorScheme.mutedForeground.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.circleAlert,
              size: 40,
              color: colorScheme.destructive,
            ),
            const SizedBox(height: NexusSpacing.md),
            Text(
              message,
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.destructive,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: NexusSpacing.md),
            NexusButton(label: 'Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}

class _ServerPreset {
  const _ServerPreset({
    required this.incomingHost,
    required this.incomingPort,
    required this.incomingSsl,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpSsl,
  });

  final String incomingHost;
  final int incomingPort;
  final bool incomingSsl;
  final String smtpHost;
  final int smtpPort;
  final bool smtpSsl;
}

const _serverPresets = <String, _ServerPreset>{
  'qq.com': _ServerPreset(
    incomingHost: 'imap.qq.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.qq.com',
    smtpPort: 465,
    smtpSsl: true,
  ),
  'gmail.com': _ServerPreset(
    incomingHost: 'imap.gmail.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.gmail.com',
    smtpPort: 587,
    smtpSsl: true,
  ),
  'outlook.com': _ServerPreset(
    incomingHost: 'outlook.office365.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.office365.com',
    smtpPort: 587,
    smtpSsl: true,
  ),
  'hotmail.com': _ServerPreset(
    incomingHost: 'outlook.office365.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.office365.com',
    smtpPort: 587,
    smtpSsl: true,
  ),
  'live.com': _ServerPreset(
    incomingHost: 'outlook.office365.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.office365.com',
    smtpPort: 587,
    smtpSsl: true,
  ),
  '163.com': _ServerPreset(
    incomingHost: 'imap.163.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.163.com',
    smtpPort: 465,
    smtpSsl: true,
  ),
  '126.com': _ServerPreset(
    incomingHost: 'imap.126.com',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.126.com',
    smtpPort: 465,
    smtpSsl: true,
  ),
  'yeah.net': _ServerPreset(
    incomingHost: 'imap.yeah.net',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.yeah.net',
    smtpPort: 465,
    smtpSsl: true,
  ),
};

/// macOS System Preferences Style Mail Account Setup
class _MailAccountSetup extends StatefulWidget {
  const _MailAccountSetup({required this.state, this.isEditing = false});

  final MailState state;
  final bool isEditing;

  @override
  State<_MailAccountSetup> createState() => _MailAccountSetupState();
}

class _MailAccountSetupState extends State<_MailAccountSetup> {
  late final _emailController = TextEditingController();
  late final _usernameController = TextEditingController();
  late final _passwordController = TextEditingController();
  late final _incomingHostController = TextEditingController();
  late final _incomingPortController = TextEditingController(text: '993');
  late final _smtpHostController = TextEditingController();
  late final _smtpPortController = TextEditingController(text: '587');
  bool _useIncomingSsl = true;
  bool _useSmtpSsl = true;
  bool _isSaving = false;

  ColorScheme get colorScheme => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    final saved = widget.state.account.value;
    _emailController.text = saved.emailAddress;
    _usernameController.text = saved.username;
    _passwordController.text = widget.isEditing ? saved.password : '';
    _incomingHostController.text = saved.host;
    _incomingPortController.text = saved.port.toString();
    _useIncomingSsl = saved.useSsl;
    _smtpHostController.text = saved.smtpHost;
    _smtpPortController.text = saved.smtpPort.toString();
    _useSmtpSsl = saved.smtpUseSsl;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _incomingHostController.dispose();
    _incomingPortController.dispose();
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: NexusCard(
            padding: const EdgeInsets.all(NexusSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF007AFF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.isEditing ? RadixIcons.gear : LucideIcons.mail,
                        size: 24,
                        color: const Color(0xFF007AFF),
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.md),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isEditing
                              ? 'Mail Account Settings'
                              : 'Mail Account Setup',
                          style: NexusTypography.headlineLg.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          widget.isEditing
                              ? 'Update your email server credentials and settings.'
                              : 'Connect your email inbox using IMAP / SMTP.',
                          style: NexusTypography.bodyMd.copyWith(
                            color: colorScheme.mutedForeground,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.lg),

                // Quick Presets
                Text('QUICK PRESETS', style: _sectionHeaderStyle),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _presetButton('QQ Mail', 'qq.com'),
                    _presetButton('NetEase 163', '163.com'),
                    _presetButton('Gmail', 'gmail.com'),
                    _presetButton('Outlook', 'outlook.com'),
                    _presetButton('126 Mail', '126.com'),
                    _presetButton('Yeah.net', 'yeah.net'),
                  ],
                ),
                const SizedBox(height: NexusSpacing.lg),

                Text('ACCOUNT DETAILS', style: _sectionHeaderStyle),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _emailController,
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: _validateEmail,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: _onEmailChanged,
                ),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _usernameController,
                  labelText: 'Username',
                  hintText: 'Usually your full email address',
                  validator: _validateRequired,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _passwordController,
                  labelText: 'Password / Authorization Code',
                  hintText: 'App authorization password',
                  obscureText: true,
                  validator: _validateRequired,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: NexusSpacing.lg),

                Text('INCOMING SERVER (IMAP)', style: _sectionHeaderStyle),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _incomingHostController,
                  labelText: 'Server host',
                  hintText: 'imap.example.com',
                  validator: _validateRequired,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: NexusSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: NexusInput(
                        controller: _incomingPortController,
                        labelText: 'Port',
                        hintText: '993',
                        keyboardType: TextInputType.number,
                        validator: _validatePort,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.md),
                    Expanded(
                      flex: 3,
                      child: _buildSwitchTile(
                        label: 'Use SSL/TLS',
                        value: _useIncomingSsl,
                        onChanged: (value) =>
                            setState(() => _useIncomingSsl = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.lg),

                Text('OUTGOING SERVER (SMTP)', style: _sectionHeaderStyle),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _smtpHostController,
                  labelText: 'Server host',
                  hintText: 'smtp.example.com',
                  validator: _validateRequired,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: NexusSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: NexusInput(
                        controller: _smtpPortController,
                        labelText: 'Port',
                        hintText: '465 / 587',
                        keyboardType: TextInputType.number,
                        validator: _validatePort,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.md),
                    Expanded(
                      flex: 3,
                      child: _buildSwitchTile(
                        label: 'Use SSL/TLS',
                        value: _useSmtpSsl,
                        onChanged: (value) =>
                            setState(() => _useSmtpSsl = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.lg),

                Watch((context) {
                  final colorScheme = Theme.of(context).colorScheme;
                  final error = widget.state.configError.value;
                  if (error == null) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: NexusSpacing.md),
                    padding: const EdgeInsets.all(NexusSpacing.md),
                    decoration: BoxDecoration(
                      color: colorScheme.destructive,
                      borderRadius: NexusRadii.mdRadius,
                    ),
                    child: Text(
                      error,
                      style: NexusTypography.bodyMd.copyWith(
                        color: const Color(0xFFFFFFFF),
                      ),
                    ),
                  );
                }),

                if (widget.isEditing)
                  Row(
                    children: [
                      Expanded(
                        child: NexusButton(
                          label: 'Save Changes',
                          icon: RadixIcons.check,
                          isLoading: _isSaving,
                          onPressed: _submit,
                        ),
                      ),
                      const SizedBox(width: NexusSpacing.md),
                      Expanded(
                        child: NexusButton(
                          label: 'Cancel',
                          variant: NexusButtonVariant.outlined,
                          onPressed: widget.state.cancelAccountEdit,
                        ),
                      ),
                    ],
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: NexusButton(
                      label: 'Connect Account',
                      icon: RadixIcons.check,
                      isLoading: _isSaving,
                      onPressed: _submit,
                    ),
                  ),
                if (widget.isEditing) ...[
                  const SizedBox(height: NexusSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: NexusButton(
                      label: 'Sign Out',
                      variant: NexusButtonVariant.text,
                      icon: LucideIcons.logOut,
                      onPressed: _signOut,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _sectionHeaderStyle => NexusTypography.labelSm.copyWith(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.5,
    color: colorScheme.mutedForeground,
  );

  Widget _presetButton(String label, String domain) {
    return GestureDetector(
      onTap: () {
        final currentEmail = _emailController.text;
        final at = currentEmail.indexOf('@');
        final prefix = at != -1 ? currentEmail.substring(0, at) : 'user';
        _emailController.text = '$prefix@$domain';
        _applyServerPreset('$prefix@$domain');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.border.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          style: NexusTypography.labelSm.copyWith(
            fontSize: 11,
            color: colorScheme.foreground,
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showOverlay<bool>(
      context,
      const DialogConfiguration(barrierColor: Color.fromRGBO(0, 0, 0, 0.54)),
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text('Sign out?', style: NexusTypography.headlineSm),
          content: Text(
            'This will remove the saved account and return to the setup screen.',
            style: NexusTypography.bodyMd,
          ),
          actions: [
            Button.text(
              onPressed: () => closeOverlay<bool>(context, false),
              child: Text(
                'Cancel',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ),
            Button.destructive(
              onPressed: () => closeOverlay<bool>(context, true),
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    ).future;
    if (confirmed == true) {
      await widget.state.signOut();
    }
  }

  Widget _buildSwitchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: NexusTypography.bodyMd.copyWith(fontSize: 12.5)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  void _onEmailChanged(String value) {
    final trimmed = value.trim();
    if (_usernameController.text.trim().isEmpty) {
      _usernameController.text = trimmed;
    }
    _applyServerPreset(trimmed);
  }

  void _applyServerPreset(String email) {
    final at = email.lastIndexOf('@');
    if (at == -1 || at == email.length - 1) return;
    final domain = email.substring(at + 1).toLowerCase();
    final preset = _serverPresets[domain];
    if (preset == null) return;

    _incomingHostController.text = preset.incomingHost;
    _incomingPortController.text = preset.incomingPort.toString();
    _useIncomingSsl = preset.incomingSsl;
    _smtpHostController.text = preset.smtpHost;
    _smtpPortController.text = preset.smtpPort.toString();
    _useSmtpSsl = preset.smtpSsl;

    if (mounted) setState(() {});
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email address is required.';
    if (!trimmed.contains('@') || !trimmed.contains('.')) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value ?? '');
    if (port == null || port <= 0 || port > 65535) {
      return 'Port 1-65535';
    }
    return null;
  }

  Future<void> _submit() async {
    final validationError = [
      _validateEmail(_emailController.text),
      _validateRequired(_usernameController.text),
      _validateRequired(_passwordController.text),
      _validateRequired(_incomingHostController.text),
      _validatePort(_incomingPortController.text),
      _validateRequired(_smtpHostController.text),
      _validatePort(_smtpPortController.text),
    ].firstWhere((e) => e != null, orElse: () => null);
    if (validationError != null) return;
    setState(() => _isSaving = true);
    try {
      final account = MailAccount(
        emailAddress: _emailController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        host: _incomingHostController.text.trim(),
        port: int.parse(_incomingPortController.text.trim()),
        useSsl: _useIncomingSsl,
        smtpHost: _smtpHostController.text.trim(),
        smtpPort: int.parse(_smtpPortController.text.trim()),
        smtpUseSsl: _useSmtpSsl,
      );
      await widget.state.saveAccount(account);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

Color _labelColor(ColorScheme colorScheme, String label) {
  return switch (label.toLowerCase()) {
    'work' => const Color(0xFF007AFF),
    'personal' => const Color(0xFF9333EA),
    'finance' => const Color(0xFF10B981),
    'social' => const Color(0xFFF59E0B),
    _ => const Color(0xFF64748B),
  };
}

String _formatDate(DateTime? date, {bool full = false}) {
  if (date == null) return '';
  final now = DateTime.now();
  final local = date.toLocal();
  if (full) {
    return DateFormat('EEE, MMM d, y • h:mm a').format(local);
  }
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return DateFormat('h:mm a').format(local);
  }
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day - 1) {
    return 'Yesterday';
  }
  return DateFormat('MMM d').format(local);
}
