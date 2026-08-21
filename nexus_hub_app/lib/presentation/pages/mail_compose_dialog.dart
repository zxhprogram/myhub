import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/mail_account_model.dart';
import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../utils/quill_delta_to_html.dart';
import '../components/nexus_button.dart';
import '../components/nexus_input.dart';
import '../components/nexus_rich_text_editor.dart';
import '../states/mail_state.dart';

/// A full-screen-capable compose dialog for writing and sending email.
///
/// Pass [initialTo], [initialSubject], and [initialBodyHtml] to pre-fill the
/// fields for reply or forward scenarios.
class MailComposeDialog extends StatefulWidget {
  const MailComposeDialog({
    super.key,
    required this.state,
    this.initialTo,
    this.initialCc,
    this.initialSubject,
    this.initialBodyDeltaJson,
  });

  final MailState state;
  final List<String>? initialTo;
  final List<String>? initialCc;
  final String? initialSubject;
  final String? initialBodyDeltaJson;

  @override
  State<MailComposeDialog> createState() => _MailComposeDialogState();
}

class _MailComposeDialogState extends State<MailComposeDialog> {
  late final TextEditingController _toController;
  late final TextEditingController _ccController;
  late final TextEditingController _subjectController;
  late String _bodyDeltaJson;
  bool _showCc = false;

  @override
  void initState() {
    super.initState();
    _toController = TextEditingController(
      text: widget.initialTo?.join(', ') ?? '',
    );
    _ccController = TextEditingController(
      text: widget.initialCc?.join(', ') ?? '',
    );
    _subjectController = TextEditingController(
      text: widget.initialSubject ?? '',
    );
    _bodyDeltaJson = widget.initialBodyDeltaJson ?? '';
    _showCc = widget.initialCc?.isNotEmpty ?? false;
  }

  MailAccount get _account => widget.state.account.value;

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      padding: EdgeInsets.zero,
      fillColor: colorScheme.card,
      borderRadius: NexusRadii.lgRadius,
      borderWidth: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(NexusSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(colorScheme),
              const SizedBox(height: NexusSpacing.md),
              _buildFields(colorScheme),
              const SizedBox(height: NexusSpacing.md),
              Expanded(child: _buildEditor(colorScheme)),
              const SizedBox(height: NexusSpacing.md),
              _buildFooter(colorScheme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(LucideIcons.notebookPen, size: 28, color: colorScheme.secondary),
        const SizedBox(width: NexusSpacing.sm),
        Text(
          'New Message',
          style: NexusTypography.headlineSm.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        IconButton.ghost(
  icon: const Icon(RadixIcons.cross2, size: 20),
  onPressed: () => closeOverlay<void>(context),
),
      ],
    );
  }

  Widget _buildFields(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldRow(
          label: 'From',
          child: Text(
            _account.emailAddress,
            style: NexusTypography.bodyMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ),
        _buildFieldRow(
          label: 'To',
          child: NexusInput(
            controller: _toController,
            hintText: 'recipient@example.com',
            maxLines: 1,
            onChanged: (_) => setState(() {}),
          ),
          trailing: Button.text(
  onPressed: () => setState(() => _showCc = !_showCc),
  leading: Icon(
              _showCc ? RadixIcons.chevronUp : RadixIcons.chevronDown,
              size: 18,
            ),
  child: const Text('Cc'),
),
        ),
        if (_showCc)
          _buildFieldRow(
            label: 'Cc',
            child: NexusInput(
              controller: _ccController,
              hintText: 'cc@example.com',
              maxLines: 1,
            ),
          ),
        _buildFieldRow(
          label: 'Subject',
          child: NexusInput(
            controller: _subjectController,
            hintText: 'Email subject',
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldRow({
    required String label,
    required Widget child,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: NexusTypography.labelMd.copyWith(
                color: Theme.of(context).colorScheme.mutedForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(child: child),
          if (trailing != null) ...[
            const SizedBox(width: NexusSpacing.xs),
            trailing,
          ],
        ],
      ),
    );
  }

  Widget _buildEditor(ColorScheme colorScheme) {
    return NexusRichTextEditor(
      initialDeltaJson: _bodyDeltaJson,
      onChanged: (json) => _bodyDeltaJson = json,
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    return Watch((context) {
      final isSending = widget.state.isSending.value;
      final sendError = widget.state.sendError.value;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sendError != null)
            Container(
              margin: const EdgeInsets.only(bottom: NexusSpacing.sm),
              padding: const EdgeInsets.all(NexusSpacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.destructive,
                borderRadius: NexusRadii.mdRadius,
              ),
              child: Text(
                sendError,
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.destructiveForeground,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              NexusButton(
                label: 'Cancel',
                variant: NexusButtonVariant.outlined,
                onPressed: isSending
                    ? null
                    : () => closeOverlay<void>(context),
              ),
              const SizedBox(width: NexusSpacing.md),
              NexusButton(
                label: 'Send',
                icon: Icons.send,
                isLoading: isSending,
                onPressed: _send,
              ),
            ],
          ),
        ],
      );
    });
  }

  Future<void> _send() async {
    final to = _parseRecipients(_toController.text);
    if (to.isEmpty) {
      widget.state.sendError.value = 'Please enter at least one recipient.';
      return;
    }
    final cc = _parseRecipients(_ccController.text);
    final subject = _subjectController.text.trim();
    if (subject.isEmpty) {
      widget.state.sendError.value = 'Please enter a subject.';
      return;
    }
    final htmlBody = QuillDeltaToHtml.convert(_bodyDeltaJson);
    if (htmlBody.isEmpty) {
      widget.state.sendError.value = 'Email body is empty.';
      return;
    }

    final success = await widget.state.sendMail(
      to: to,
      cc: cc.isEmpty ? null : cc,
      subject: subject,
      htmlBody: htmlBody,
    );
    if (success && mounted) {
      closeOverlay<void>(context);
    }
  }

  List<String> _parseRecipients(String text) {
    return text
        .split(RegExp(r'[,\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.contains('@'))
        .toList();
  }
}
