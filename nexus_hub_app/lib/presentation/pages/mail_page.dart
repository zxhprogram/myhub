import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:signals_flutter/signals_flutter.dart';
// ignore: implementation_imports
import 'package:easy_mail/src/models/mail_message.dart';

import '../../data/models/mail_account_model.dart';
import '../../data/models/mail_item_model.dart';
import '../../data/repositories/mail_repository.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/mail_body_view.dart';
import '../components/nexus_avatar.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_chip.dart';
import '../components/nexus_input.dart';
import '../states/mail_state.dart';

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
    return Container(
      color: NexusColors.background,
      child: Watch((context) {
        if (!_state.hasValidAccount.value || _state.isEditingAccount.value) {
          return _MailAccountSetup(
            state: _state,
            isEditing: _state.hasValidAccount.value,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1100;
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
    return Row(
      children: [
        SizedBox(width: 240, child: _FolderSidebar(state: _state)),
        const VerticalDivider(width: 1),
        SizedBox(width: 400, child: _MessageList(state: _state)),
        const VerticalDivider(width: 1),
        Expanded(child: _ReadingPane(state: _state)),
      ],
    );
  }

  Widget _buildNarrowLayout() {
    return Watch((context) {
      final selected = _state.selectedEmail.value;
      if (selected == null) {
        return Row(
          children: [
            SizedBox(width: 200, child: _FolderSidebar(state: _state)),
            const VerticalDivider(width: 1),
            Expanded(child: _MessageList(state: _state)),
          ],
        );
      }
      return _ReadingPane(state: _state, showBackButton: true);
    });
  }
}

class _MailToolbar extends StatelessWidget {
  const _MailToolbar({required this.state, required this.isWide});

  final MailState state;
  final bool isWide;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.lg),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: NexusColors.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: isWide ? 360 : 200,
            child: NexusInput(
              hintText: 'Search messages...',
              prefixIcon: const Icon(Icons.search, size: 20),
              onChanged: (value) => state.search(value),
            ),
          ),
          if (isWide) ...[
            const SizedBox(width: NexusSpacing.lg),
            Text(
              'Inbox',
              style: NexusTypography.labelMd.copyWith(
                color: NexusColors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const Spacer(),
          _ToolbarIconButton(
            icon: Icons.refresh,
            isLoading: state.isLoading.value,
            onTap: () => state.refresh(),
          ),
          _ToolbarIconButton(icon: Icons.notifications_outlined, onTap: () {}),
          _ToolbarIconButton(
            icon: Icons.settings_outlined,
            onTap: () => state.startAccountEdit(),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Container(width: 1, height: 24, color: NexusColors.outlineVariant),
          const SizedBox(width: NexusSpacing.sm),
          NexusButton(
            label: 'Compose',
            icon: Icons.add,
            onPressed: () => _showComposeDialog(context),
          ),
        ],
      ),
    );
  }

  void _showComposeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexusColors.surfaceContainerLowest,
        title: Text('Compose', style: NexusTypography.headlineSm),
        content: Text(
          'Compose functionality will be implemented in a follow-up.',
          style: NexusTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Close',
              style: NexusTypography.labelMd.copyWith(
                color: NexusColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarIconButton extends StatelessWidget {
  const _ToolbarIconButton({
    required this.icon,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: NexusRadii.mdRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.mdRadius,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: isLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: NexusColors.secondary,
                  ),
                )
              : Icon(icon, size: 20, color: NexusColors.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _FolderSidebar extends StatelessWidget {
  const _FolderSidebar({required this.state});

  final MailState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.surfaceContainerLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(NexusSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFolderGroup(),
                  const SizedBox(height: NexusSpacing.lg),
                  _buildLabelsGroup(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderGroup() {
    return Watch((context) {
      final selected = state.selectedFolder.value;
      final counts = state.unreadCounts.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: state.folders.value.map((folder) {
          final count = counts[folder.id] ?? 0;
          final isSelected = folder.id == selected;
          return _SidebarItem(
            icon: folder.icon,
            label: folder.title,
            count: count,
            isSelected: isSelected,
            onTap: () => state.loadFolder(folder.id),
          );
        }).toList(),
      );
    });
  }

  Widget _buildLabelsGroup() {
    return Watch((context) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: NexusSpacing.sm,
              bottom: NexusSpacing.sm,
            ),
            child: Text(
              'LABELS',
              style: NexusTypography.labelSm.copyWith(
                color: NexusColors.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...state.labels.value.map((label) {
            return _SidebarItem(
              icon: Icons.label,
              label: label,
              iconColor: _labelColor(label),
              isSelected: false,
              onTap: () {},
            );
          }),
        ],
      );
    });
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isSelected ? NexusColors.secondaryContainer : Colors.transparent,
        borderRadius: NexusRadii.mdRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: NexusRadii.mdRadius,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color:
                      iconColor ??
                      (isSelected
                          ? NexusColors.onSecondaryContainer
                          : NexusColors.onSurfaceVariant),
                ),
                const SizedBox(width: NexusSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: NexusTypography.bodyMd.copyWith(
                      color: isSelected
                          ? NexusColors.onSecondaryContainer
                          : NexusColors.onSurfaceVariant,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: NexusSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? NexusColors.secondaryFixed
                          : NexusColors.secondaryContainer,
                      borderRadius: NexusRadii.fullRadius,
                    ),
                    child: Text(
                      count.toString(),
                      style: NexusTypography.labelSm.copyWith(
                        color: isSelected
                            ? NexusColors.onSecondaryFixed
                            : NexusColors.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.state});

  final MailState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: Watch((context) {
              if (state.isLoading.value && state.emails.value.isEmpty) {
                return _buildShimmer();
              }
              if (state.error.value != null && state.emails.value.isEmpty) {
                return _ErrorState(
                  message: state.error.value!,
                  onRetry: state.retry,
                );
              }
              if (state.emails.value.isEmpty) {
                return _EmptyState(message: 'No messages in this folder.');
              }
              return RefreshIndicator(
                color: NexusColors.secondary,
                backgroundColor: NexusColors.surfaceContainerLowest,
                onRefresh: state.refresh,
                child: ListView.builder(
                  itemCount: state.emails.value.length,
                  itemBuilder: (context, index) {
                    final item = state.emails.value[index];
                    return _MessageListItem(
                      item: item,
                      isSelected: state.selectedEmail.value?.uid == item.uid,
                      onTap: () => state.selectEmail(item),
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

  Widget _buildHeader() {
    return Watch((context) {
      return Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: NexusColors.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              state.selectedFolder.value,
              style: NexusTypography.headlineSm.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            _ToolbarIconButton(icon: Icons.filter_list, onTap: () {}),
          ],
        ),
      );
    });
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: NexusColors.surfaceContainerLow,
      highlightColor: NexusColors.surfaceContainerHigh,
      child: ListView.builder(
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            height: 88,
            margin: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
              vertical: NexusSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: NexusColors.surfaceContainerLowest,
              borderRadius: NexusRadii.mdRadius,
            ),
          );
        },
      ),
    );
  }
}

class _MessageListItem extends StatelessWidget {
  const _MessageListItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final MailItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected
        ? NexusColors.onSecondaryContainer
        : item.isRead
        ? NexusColors.onSurfaceVariant
        : NexusColors.onSurface;
    final subjectWeight = item.isRead ? FontWeight.w500 : FontWeight.w700;

    return Material(
      color: isSelected
          ? NexusColors.secondaryContainer
          : NexusColors.surfaceContainerLowest,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.md,
            vertical: NexusSpacing.sm,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: NexusColors.outlineVariant),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!item.isRead)
                Container(
                  width: 4,
                  height: 32,
                  margin: const EdgeInsets.only(right: NexusSpacing.sm),
                  decoration: BoxDecoration(
                    color: NexusColors.secondary,
                    borderRadius: NexusRadii.fullRadius,
                  ),
                )
              else
                const SizedBox(width: 4 + NexusSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.senderName.isEmpty
                                ? item.senderAddress
                                : item.senderName,
                            style: NexusTypography.labelMd.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: NexusSpacing.sm),
                        Text(
                          _formatDate(item.date),
                          style: NexusTypography.labelSm.copyWith(
                            color: isSelected
                                ? NexusColors.onSecondaryContainer
                                : NexusColors.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subject,
                      style: NexusTypography.bodyMd.copyWith(
                        color: foreground,
                        fontWeight: subjectWeight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.snippet,
                      style: NexusTypography.bodyMd.copyWith(
                        color: isSelected
                            ? NexusColors.onSecondaryContainer
                            : NexusColors.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadingPane extends StatelessWidget {
  const _ReadingPane({required this.state, this.showBackButton = false});

  final MailState state;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NexusColors.surfaceContainerLowest,
      child: Column(
        children: [
          _buildToolbar(context),
          Expanded(
            child: Watch((context) {
              final item = state.selectedEmail.value;
              if (item == null) {
                return _EmptyState(message: 'Select a message to read');
              }
              final message = state.selectedEmailMessage.value;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(NexusSpacing.lg),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSubjectHeader(item),
                      const SizedBox(height: NexusSpacing.lg),
                      _buildSenderCard(item),
                      const SizedBox(height: NexusSpacing.lg),
                      _buildBody(message),
                      if (message != null &&
                          message.attachments.isNotEmpty) ...[
                        const SizedBox(height: NexusSpacing.lg),
                        _buildAttachments(message),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: NexusColors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (showBackButton)
            _ToolbarIconButton(
              icon: Icons.arrow_back,
              onTap: () => state.selectEmail(null),
            ),
          _ToolbarIconButton(icon: Icons.reply, onTap: () {}),
          _ToolbarIconButton(icon: Icons.forward, onTap: () {}),
          Container(width: 1, height: 24, color: NexusColors.outlineVariant),
          _ToolbarIconButton(icon: Icons.archive_outlined, onTap: () {}),
          _ToolbarIconButton(icon: Icons.delete_outlined, onTap: () {}),
          const Spacer(),
          _ToolbarIconButton(icon: Icons.star_border, onTap: () {}),
          _ToolbarIconButton(icon: Icons.more_vert, onTap: () {}),
        ],
      ),
    );
  }

  Widget _buildSubjectHeader(MailItem item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            item.subject,
            style: NexusTypography.headlineXl.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: NexusSpacing.md),
        ...item.labels.map((label) {
          return Padding(
            padding: const EdgeInsets.only(left: NexusSpacing.xs),
            child: NexusChip(label: label, color: _labelColor(label)),
          );
        }),
      ],
    );
  }

  Widget _buildSenderCard(MailItem item) {
    return Container(
      padding: const EdgeInsets.all(NexusSpacing.md),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLow,
        borderRadius: NexusRadii.lgRadius,
        border: Border.all(color: NexusColors.outlineVariant),
      ),
      child: Row(
        children: [
          NexusAvatar(
            label: item.senderName.isEmpty
                ? item.senderAddress
                : item.senderName,
            size: 48,
          ),
          const SizedBox(width: NexusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.senderName.isEmpty
                          ? item.senderAddress
                          : item.senderName,
                      style: NexusTypography.bodyLg.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.sm),
                    Text(
                      item.senderName.isEmpty ? '' : '<${item.senderAddress}>',
                      style: NexusTypography.bodyMd.copyWith(
                        color: NexusColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'To: nexus.user@hub.io • ${_formatDate(item.date, full: true)}',
                  style: NexusTypography.bodyMd.copyWith(
                    color: NexusColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(MailMessage? message) {
    if (message == null) {
      return const SizedBox.shrink();
    }
    return MailBodyView(message: message);
  }

  Widget _buildAttachments(MailMessage message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachments (${message.attachments.length})',
          style: NexusTypography.labelSm.copyWith(
            color: NexusColors.outline,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: NexusSpacing.md),
        Wrap(
          spacing: NexusSpacing.md,
          runSpacing: NexusSpacing.md,
          children: message.attachments.map((attachment) {
            return Container(
              width: 240,
              padding: const EdgeInsets.all(NexusSpacing.md),
              decoration: BoxDecoration(
                color: NexusColors.surfaceContainerLowest,
                borderRadius: NexusRadii.mdRadius,
                border: Border.all(color: NexusColors.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    color: NexusColors.secondary,
                    size: 28,
                  ),
                  const SizedBox(width: NexusSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.fileName,
                          style: NexusTypography.labelMd.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${(attachment.size / 1024).ceil()} KB',
                          style: NexusTypography.labelSm.copyWith(
                            color: NexusColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.download_outlined,
                    size: 20,
                    color: NexusColors.onSurfaceVariant,
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mail_outline,
            size: 48,
            color: NexusColors.onSurfaceVariant,
          ),
          const SizedBox(height: NexusSpacing.md),
          Text(
            message,
            style: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: NexusColors.error),
            const SizedBox(height: NexusSpacing.md),
            Text(
              message,
              style: NexusTypography.bodyMd.copyWith(color: NexusColors.error),
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
  'yeah.net': _ServerPreset(
    incomingHost: 'imap.yeah.net',
    incomingPort: 993,
    incomingSsl: true,
    smtpHost: 'smtp.yeah.net',
    smtpPort: 465,
    smtpSsl: true,
  ),
};

class _MailAccountSetup extends StatefulWidget {
  const _MailAccountSetup({required this.state, this.isEditing = false});

  final MailState state;
  final bool isEditing;

  @override
  State<_MailAccountSetup> createState() => _MailAccountSetupState();
}

class _MailAccountSetupState extends State<_MailAccountSetup> {
  final _formKey = GlobalKey<FormState>();
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
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: NexusCard(
            padding: const EdgeInsets.all(NexusSpacing.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        widget.isEditing
                            ? Icons.settings_outlined
                            : Icons.mail_outlined,
                        size: 32,
                        color: NexusColors.secondary,
                      ),
                      const SizedBox(width: NexusSpacing.md),
                      Text(
                        widget.isEditing
                            ? 'Mail Account Settings'
                            : 'Mail Account Setup',
                        style: NexusTypography.headlineLg.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: NexusSpacing.sm),
                  Text(
                    widget.isEditing
                        ? 'Update your account details below.'
                        : 'Enter your email account details to get started.',
                    style: NexusTypography.bodyMd.copyWith(
                      color: NexusColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: NexusSpacing.lg),
                  _buildSectionTitle('Account'),
                  const SizedBox(height: NexusSpacing.md),
                  NexusInput(
                    controller: _emailController,
                    labelText: 'Email address',
                    hintText: 'you@example.com',
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    onChanged: _onEmailChanged,
                  ),
                  const SizedBox(height: NexusSpacing.md),
                  NexusInput(
                    controller: _usernameController,
                    labelText: 'Username',
                    hintText: 'Usually your email address',
                    validator: _validateRequired,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: NexusSpacing.md),
                  NexusInput(
                    controller: _passwordController,
                    labelText: 'Password',
                    hintText: 'Your email password',
                    obscureText: true,
                    validator: _validateRequired,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: NexusSpacing.lg),
                  _buildSectionTitle('Incoming server (IMAP/POP3)'),
                  const SizedBox(height: NexusSpacing.md),
                  NexusInput(
                    controller: _incomingHostController,
                    labelText: 'Server host',
                    hintText: 'imap.example.com',
                    validator: _validateRequired,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: NexusSpacing.md),
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
                  _buildSectionTitle('Outgoing server (SMTP)'),
                  const SizedBox(height: NexusSpacing.md),
                  NexusInput(
                    controller: _smtpHostController,
                    labelText: 'Server host',
                    hintText: 'smtp.example.com',
                    validator: _validateRequired,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: NexusSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: NexusInput(
                          controller: _smtpPortController,
                          labelText: 'Port',
                          hintText: '587',
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
                    final error = widget.state.configError.value;
                    if (error == null) return const SizedBox.shrink();
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(NexusSpacing.md),
                      decoration: BoxDecoration(
                        color: NexusColors.errorContainer,
                        borderRadius: NexusRadii.mdRadius,
                      ),
                      child: Text(
                        error,
                        style: NexusTypography.bodyMd.copyWith(
                          color: NexusColors.onErrorContainer,
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: NexusSpacing.lg),
                  if (widget.isEditing)
                    Row(
                      children: [
                        Expanded(
                          child: NexusButton(
                            label: 'Save Changes',
                            icon: Icons.check,
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
                        icon: Icons.check,
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
                        icon: Icons.logout,
                        onPressed: _signOut,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexusColors.surfaceContainerLowest,
        title: Text('Sign out?', style: NexusTypography.headlineSm),
        content: Text(
          'This will remove the saved account and return to the setup screen.',
          style: NexusTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: NexusTypography.labelMd.copyWith(
                color: NexusColors.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Sign Out',
              style: NexusTypography.labelMd.copyWith(color: NexusColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.state.signOut();
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: NexusTypography.labelSm.copyWith(
        color: NexusColors.outline,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSwitchTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.md),
      decoration: BoxDecoration(
        color: NexusColors.surfaceContainerLow,
        borderRadius: NexusRadii.mdRadius,
        border: Border.all(color: NexusColors.outlineVariant),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: NexusTypography.bodyMd),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: NexusColors.secondary,
            activeTrackColor: NexusColors.secondary.withValues(alpha: 0.5),
          ),
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

    if (_incomingHostController.text.trim().isEmpty) {
      _incomingHostController.text = preset.incomingHost;
    }
    if (_incomingPortController.text.trim().isEmpty) {
      _incomingPortController.text = preset.incomingPort.toString();
      _useIncomingSsl = preset.incomingSsl;
    }
    if (_smtpHostController.text.trim().isEmpty) {
      _smtpHostController.text = preset.smtpHost;
    }
    if (_smtpPortController.text.trim().isEmpty) {
      _smtpPortController.text = preset.smtpPort.toString();
      _useSmtpSsl = preset.smtpSsl;
    }
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
    if (!_formKey.currentState!.validate()) return;
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

Color _labelColor(String label) {
  return switch (label.toLowerCase()) {
    'work' => NexusColors.secondary,
    'personal' => const Color(0xFF9333EA),
    _ => NexusColors.outline,
  };
}

String _formatDate(DateTime? date, {bool full = false}) {
  if (date == null) return '';
  final now = DateTime.now();
  final local = date.toLocal();
  if (full) {
    return DateFormat('MMM d, y (h:mm a)').format(local);
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
