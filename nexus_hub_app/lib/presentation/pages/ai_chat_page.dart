import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/ai_chat_message.dart';
import '../../data/models/ai_provider_config.dart';
import '../../data/repositories/ai_chat_repository.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_avatar.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_chip.dart';
import '../components/nexus_empty_state.dart';
import '../components/nexus_input.dart';
import '../layout/page_scaffold.dart';
import '../states/ai_chat_state.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _state = AiChatState.instance;
  final _controller = TextEditingController();

  static const _quickPrompts = [
    'Summarize selected text',
    'Generate Dart function',
    'Explain a design pattern',
    'Translate to Chinese',
  ];

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || _state.isStreaming.value) return;
    _controller.clear();
    _state.sendMessage(text);
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard', style: NexusTypography.bodyMd),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _openSettings() {
    return showDialog(
      context: context,
      builder: (_) => const _ProviderSettingsDialog(),
    );
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear conversation?', style: NexusTypography.headlineSm),
        content: Text(
          'This removes the whole transcript from this device.',
          style: NexusTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        actions: [
          NexusButton(
            label: 'Cancel',
            variant: NexusButtonVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          NexusButton(
            label: 'Clear',
            icon: Icons.delete_sweep_outlined,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _state.clearConversation();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Chat', style: NexusTypography.headlineXl),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  'Ask anything, summarize text, or generate code',
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Watch((_) {
            final providers = _state.providers.value;
            final active = _state.activeProvider;
            final hasMessages = _state.messages.value.isNotEmpty;
            final isStreaming = _state.isStreaming.value;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (providers.isNotEmpty) ...[
                  _MenuButton<String>(
                    icon: Icons.dns_outlined,
                    label: active?.name ?? 'No provider',
                    itemBuilder: (_) => [
                      for (final provider in providers)
                        PopupMenuItem(
                          value: provider.id,
                          child: Row(
                            children: [
                              if (provider.id == active?.id)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: colorScheme.primary,
                                )
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: NexusSpacing.sm),
                              Flexible(
                                child: Text(
                                  provider.name,
                                  style: NexusTypography.bodyMd,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _kManageProviders,
                        child: Row(
                          children: [
                            Icon(Icons.tune, size: 16),
                            SizedBox(width: NexusSpacing.sm),
                            Text('Manage providers…'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == _kManageProviders) {
                        _openSettings();
                      } else {
                        _state.setActiveProvider(value);
                      }
                    },
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                  _MenuButton<String>(
                    icon: Icons.model_training_outlined,
                    label: active?.selectedModel ?? 'No model',
                    itemBuilder: (_) => [
                      for (final model in active?.models ?? const <String>[])
                        PopupMenuItem(
                          value: model,
                          child: Row(
                            children: [
                              if (model == active?.selectedModel)
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: colorScheme.primary,
                                )
                              else
                                const SizedBox(width: 16),
                              const SizedBox(width: NexusSpacing.sm),
                              Flexible(
                                child: Text(
                                  model,
                                  style: NexusTypography.bodyMd,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _kManageProviders,
                        child: Row(
                          children: [
                            Icon(Icons.tune, size: 16),
                            SizedBox(width: NexusSpacing.sm),
                            Text('Manage models in settings…'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == _kManageProviders) {
                        _openSettings();
                      } else if (active != null) {
                        _state.setSelectedModel(active.id, value);
                      }
                    },
                  ),
                  const SizedBox(width: NexusSpacing.sm),
                ],
                IconButton(
                  tooltip: 'Provider settings',
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: _openSettings,
                ),
                IconButton(
                  tooltip: 'Clear conversation',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  onPressed:
                      hasMessages && !isStreaming ? _confirmClear : null,
                ),
              ],
            );
          }),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Watch((_) {
              if (_state.providers.value.isEmpty) {
                return NexusCard(
                  child: NexusEmptyState(
                    icon: Icons.smart_toy_outlined,
                    title: 'No provider configured',
                    subtitle:
                        'Add an OpenAI-compatible provider (OpenAI, DeepSeek, '
                        'Kimi, Ollama, …) to start chatting.',
                    action: NexusButton(
                      label: 'Configure providers',
                      icon: Icons.tune,
                      onPressed: _openSettings,
                    ),
                  ),
                );
              }
              return NexusCard(
                padding: const EdgeInsets.all(0),
                child: Watch((_) {
                  final messages = _state.messages.value;
                  final isStreaming = _state.isStreaming.value;
                  if (messages.isEmpty && !isStreaming) {
                    return NexusEmptyState(
                      icon: Icons.forum_outlined,
                      title: 'Ask anything',
                      subtitle:
                          'Replies stream in live and render as rich '
                          'Markdown with code blocks and tables.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(NexusSpacing.md),
                    reverse: true,
                    itemCount: messages.length + (isStreaming ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (isStreaming && index == 0) {
                        return const _StreamingBubble();
                      }
                      final message =
                          messages[messages.length - 1 - index + (isStreaming ? 1 : 0)];
                      return _ChatBubble(
                        message: message,
                        onCopy: _copyMessage,
                      );
                    },
                  );
                }),
              );
            }),
          ),
          const SizedBox(height: NexusSpacing.md),
          Watch((_) {
            final error = _state.error.value;
            if (error == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
              child: Material(
                color: colorScheme.errorContainer,
                borderRadius: NexusRadii.mdRadius,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.md,
                    vertical: NexusSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 18,
                        color: colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: NexusSpacing.sm),
                      Expanded(
                        child: Text(
                          error,
                          style: NexusTypography.bodyMd.copyWith(
                            color: colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        color: colorScheme.onErrorContainer,
                        onPressed: () => _state.error.value = null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          Watch((_) {
            final isStreaming = _state.isStreaming.value;
            final messages = _state.messages.value;
            final canRegenerate =
                !isStreaming &&
                messages.isNotEmpty &&
                messages.last.role == AiChatRole.assistant;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Regenerate reply',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: canRegenerate ? () => _state.regenerate() : null,
                ),
                const SizedBox(width: NexusSpacing.sm),
                Expanded(
                  child: Shortcuts(
                    shortcuts: const <ShortcutActivator, Intent>{
                      SingleActivator(LogicalKeyboardKey.enter): _SendIntent(),
                      SingleActivator(
                        LogicalKeyboardKey.numpadEnter,
                      ): _SendIntent(),
                    },
                    child: Actions(
                      actions: <Type, Action<Intent>>{
                        _SendIntent: CallbackAction<_SendIntent>(
                          onInvoke: (_) {
                            _send();
                            return null;
                          },
                        ),
                      },
                      child: NexusInput(
                        controller: _controller,
                        hintText:
                            'Type your message… (Enter to send, Shift+Enter '
                            'for a new line)',
                        maxLines: 5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: NexusSpacing.sm),
                if (isStreaming)
                  NexusButton(
                    label: 'Stop',
                    icon: Icons.stop_circle_outlined,
                    variant: NexusButtonVariant.tonal,
                    onPressed: _state.stopStreaming,
                  )
                else
                  NexusButton(
                    label: 'Send',
                    icon: Icons.send,
                    onPressed: _send,
                  ),
              ],
            );
          }),
          const SizedBox(height: NexusSpacing.md),
          Wrap(
            spacing: NexusSpacing.sm,
            runSpacing: NexusSpacing.sm,
            children: _quickPrompts
                .map(
                  (prompt) => ActionChip(
                    label: Text(prompt, style: NexusTypography.labelMd),
                    onPressed: () {
                      _controller.text = prompt;
                    },
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

const _kManageProviders = '__manage_providers__';

class _SendIntent extends Intent {
  const _SendIntent();
}

/// Compact dropdown used for the provider and model pickers in the header.
class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.label,
    required this.itemBuilder,
    this.onSelected,
  });

  final IconData icon;
  final String label;
  final List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<T>(
      tooltip: label,
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 220),
      itemBuilder: itemBuilder,
      onSelected: onSelected,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: NexusRadii.mdRadius,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                label,
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bubble for the in-flight reply; rebuilds itself on every streamed delta
/// so the rest of the transcript stays untouched.
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: NexusSpacing.sm),
        padding: const EdgeInsets.all(NexusSpacing.md),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: NexusRadii.lgRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: NexusSpacing.sm),
              child: NexusAvatar(label: 'AI'),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Watch((_) {
                    final text =
                        AiChatState.instance.streamingText.value ?? '';
                    if (text.isNotEmpty) {
                      return GptMarkdown(
                        text,
                        style: NexusTypography.bodyMd.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      );
                    }
                    final reasoning =
                        AiChatState.instance.streamingReasoning.value ?? '';
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _PulsingDot(),
                        const SizedBox(width: NexusSpacing.sm),
                        Text(
                          reasoning.isEmpty
                              ? 'Connecting…'
                              : 'Thinking…',
                          style: NexusTypography.labelMd.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: NexusSpacing.xs),
                  Watch((_) {
                    if ((AiChatState.instance.streamingText.value ?? '')
                        .isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _PulsingDot(),
                        const SizedBox(width: NexusSpacing.sm),
                        Text(
                          'Generating…',
                          style: NexusTypography.labelMd.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
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
}

/// Collapsible block showing a reasoning model's chain of thought that was
/// streamed before the visible answer.
class _ReasoningDisclosure extends StatefulWidget {
  const _ReasoningDisclosure({required this.reasoning});

  final String reasoning;

  @override
  State<_ReasoningDisclosure> createState() => _ReasoningDisclosureState();
}

class _ReasoningDisclosureState extends State<_ReasoningDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: NexusRadii.smRadius,
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: NexusSpacing.xs),
              Text(
                _expanded ? 'Hide thinking' : 'Show thinking',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.xs),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(NexusSpacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: NexusRadii.mdRadius,
              ),
              child: SelectableText(
                widget.reasoning,
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, this.onCopy});

  final AiChatMessage message;
  final void Function(String)? onCopy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUser = message.role == AiChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: NexusSpacing.sm),
        padding: const EdgeInsets.all(NexusSpacing.md),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: message.isError
              ? colorScheme.errorContainer
              : isUser
              ? colorScheme.primary
              : colorScheme.surfaceContainer,
          borderRadius: NexusRadii.lgRadius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser)
              const Padding(
                padding: EdgeInsets.only(right: NexusSpacing.sm),
                child: NexusAvatar(label: 'AI'),
              ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isUser && !message.isError && message.reasoning.isNotEmpty)
                    _ReasoningDisclosure(reasoning: message.reasoning),
                  if (!isUser && !message.isError && message.reasoning.isNotEmpty)
                    const SizedBox(height: NexusSpacing.xs),
                  if (isUser || message.isError)
                    SelectableText(
                      message.content,
                      style: NexusTypography.bodyMd.copyWith(
                        color: message.isError
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimary,
                      ),
                    )
                  else
                    GptMarkdown(
                      message.content,
                      style: NexusTypography.bodyMd.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      onLinkTap: (url, _) => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  if (!isUser) ...[
                    const SizedBox(height: NexusSpacing.xs),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      tooltip: 'Copy',
                      icon: Icon(
                        Icons.copy_outlined,
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed:
                          onCopy != null ? () => onCopy!(message.content) : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lists all configured providers; lets the user activate, edit, or delete
/// them and open the add/edit form.
class _ProviderSettingsDialog extends StatelessWidget {
  const _ProviderSettingsDialog();

  @override
  Widget build(BuildContext context) {
    final state = AiChatState.instance;
    return AlertDialog(
      title: Text('AI Providers', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 560,
        child: Watch((_) {
          final providers = state.providers.value;
          final activeId = state.activeProviderId.value;
          if (providers.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.lg),
              child: Text(
                'No providers yet. Add an OpenAI-compatible provider to '
                'start chatting.',
                style: NexusTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final provider in providers) ...[
                  if (provider != providers.first)
                    const SizedBox(height: NexusSpacing.sm),
                  _ProviderListTile(
                    provider: provider,
                    selected: provider.id == activeId,
                  ),
                ],
              ],
            ),
          );
        }),
      ),
      actions: [
        NexusButton(
          label: 'Add provider',
          icon: Icons.add,
          variant: NexusButtonVariant.tonal,
          onPressed: () => _openEditor(context, null),
        ),
        NexusButton(
          label: 'Close',
          variant: NexusButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static void _openEditor(BuildContext context, AiProviderConfig? initial) {
    showDialog(
      context: context,
      builder: (_) => _ProviderEditDialog(initial: initial),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({required this.provider, required this.selected});

  final AiProviderConfig provider;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final state = AiChatState.instance;
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      highlight: selected,
      onTap: () => state.setActiveProvider(provider.id),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  provider.name,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${provider.baseUrl}  ·  ${provider.selectedModel ?? 'no model'}',
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () =>
                _ProviderSettingsDialog._openEditor(context, provider),
          ),
          IconButton(
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () {
              if (state.isStreaming.value &&
                  state.activeProviderId.value == provider.id) {
                state.stopStreaming();
              }
              state.deleteProvider(provider.id);
            },
          ),
        ],
      ),
    );
  }
}

/// Add/edit form for a single provider, including model management.
class _ProviderEditDialog extends StatefulWidget {
  const _ProviderEditDialog({this.initial});

  final AiProviderConfig? initial;

  @override
  State<_ProviderEditDialog> createState() => _ProviderEditDialogState();
}

class _ProviderEditDialogState extends State<_ProviderEditDialog> {
  final _formKey = GlobalKey<FormState>();
  final _repository = AiChatRepository();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _baseUrl = TextEditingController(
    text: widget.initial?.baseUrl ?? '',
  );
  late final _apiKey = TextEditingController(
    text: widget.initial?.apiKey ?? '',
  );
  late final _systemPrompt = TextEditingController(
    text: widget.initial?.systemPrompt ?? '',
  );
  final _newModel = TextEditingController();

  late List<String> _models = [...?widget.initial?.models];
  late String? _selectedModel = widget.initial?.selectedModel;

  bool _fetching = false;
  String? _error;

  static const _presets = <(String, String)>[
    ('OpenAI', 'https://api.openai.com/v1'),
    ('DeepSeek', 'https://api.deepseek.com/v1'),
    ('Kimi', 'https://api.moonshot.cn/v1'),
    ('GLM', 'https://open.bigmodel.cn/api/paas/v4'),
    ('Ollama', 'http://localhost:11434/v1'),
    ('LM Studio', 'http://localhost:1234/v1'),
  ];

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _apiKey.dispose();
    _systemPrompt.dispose();
    _newModel.dispose();
    super.dispose();
  }

  void _applyPreset(String name, String url) {
    if (_name.text.trim().isEmpty) _name.text = name;
    _baseUrl.text = url;
  }

  Future<void> _fetchModels() async {
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      // Fetch against the unsaved form values so new providers can pull
      // their model list before being stored.
      final temp = AiProviderConfig(
        id: 'draft',
        name: _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
      );
      final fetched = await _repository.fetchModels(temp);
      setState(() {
        _models = {..._models, ...fetched}.toList()..sort();
        if ((_selectedModel ?? '').isEmpty && _models.isNotEmpty) {
          _selectedModel = _models.first;
        }
      });
    } on AiChatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _fetching = false);
    }
  }

  void _addManualModel() {
    final name = _newModel.text.trim();
    if (name.isEmpty) return;
    setState(() {
      if (!_models.contains(name)) {
        _models = [..._models, name]..sort();
      }
      _selectedModel = name;
      _newModel.clear();
    });
  }

  void _removeModel(String model) {
    setState(() {
      _models = _models.where((m) => m != model).toList();
      if (_selectedModel == model) {
        _selectedModel = _models.isEmpty ? null : _models.first;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = AiProviderConfig(
      id: widget.initial?.id ?? AiChatState.generateId(),
      name: _name.text.trim(),
      baseUrl: _baseUrl.text.trim(),
      apiKey: _apiKey.text.trim(),
      systemPrompt: _systemPrompt.text,
      models: List.unmodifiable(_models),
      selectedModel: _selectedModel,
    );
    final state = AiChatState.instance;
    if (widget.initial == null) {
      await state.addProvider(config);
    } else {
      await state.updateProvider(config);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Add provider' : 'Edit provider',
        style: NexusTypography.headlineSm,
      ),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: NexusSpacing.xs,
                  runSpacing: NexusSpacing.xs,
                  children: [
                    for (final (name, url) in _presets)
                      ActionChip(
                        label: Text(name, style: NexusTypography.labelMd),
                        onPressed: () => _applyPreset(name, url),
                      ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.md),
                NexusInput(
                  controller: _name,
                  labelText: 'Name',
                  hintText: 'e.g. My DeepSeek',
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _baseUrl,
                  labelText: 'Base URL',
                  hintText: 'https://api.openai.com/v1',
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _apiKey,
                  labelText: 'API key (optional)',
                  hintText: 'sk-…',
                  obscureText: true,
                ),
                const SizedBox(height: NexusSpacing.sm),
                NexusInput(
                  controller: _systemPrompt,
                  labelText: 'System prompt (optional)',
                  hintText: 'You are a helpful assistant…',
                  maxLines: 3,
                ),
                const SizedBox(height: NexusSpacing.md),
                Text(
                  'Models',
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: NexusSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: NexusInput(
                        controller: _newModel,
                        hintText: 'Model id, e.g. gpt-4o-mini',
                        onSubmitted: (_) => _addManualModel(),
                      ),
                    ),
                    const SizedBox(width: NexusSpacing.sm),
                    NexusButton(
                      label: 'Add',
                      icon: Icons.add,
                      variant: NexusButtonVariant.tonal,
                      onPressed: _addManualModel,
                    ),
                  ],
                ),
                const SizedBox(height: NexusSpacing.sm),
                if (_models.isEmpty)
                  Text(
                    'No models yet — add one manually or fetch the list from '
                    'the provider.',
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: NexusSpacing.xs,
                    runSpacing: NexusSpacing.xs,
                    children: [
                      for (final model in _models)
                        NexusChip(
                          label: model,
                          selected: model == _selectedModel,
                          onTap: () =>
                              setState(() => _selectedModel = model),
                          onDeleted: () => _removeModel(model),
                        ),
                    ],
                  ),
                const SizedBox(height: NexusSpacing.sm),
                NexusButton(
                  label: 'Fetch from API',
                  icon: Icons.cloud_download_outlined,
                  variant: NexusButtonVariant.outlined,
                  isLoading: _fetching,
                  onPressed: _fetching ? null : _fetchModels,
                ),
                if (_error != null) ...[
                  const SizedBox(height: NexusSpacing.sm),
                  Text(
                    _error!,
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        NexusButton(
          label: 'Cancel',
          variant: NexusButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NexusButton(
          label: 'Save',
          icon: Icons.check,
          onPressed: _save,
        ),
      ],
    );
  }
}
