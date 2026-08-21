import 'package:flutter/services.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/ai_chat_message.dart';
import '../../data/models/ai_chat_session.dart';
import '../../data/models/ai_provider_config.dart';
import '../../data/repositories/ai_chat_repository.dart';
import '../../theme/spacing.dart';
import '../states/ai_chat_state.dart';

/// AI Chat page built entirely from shadcn_flutter components.
///
/// The page can be hosted in two environments: desktop windows (already
/// inside a [ShadcnLayer]) and the mobile app-shell route (Material only).
/// [build] therefore installs the shadcn infrastructure itself when it is
/// missing, and always overrides the shadcn color scheme to follow the
/// ambient Material brightness so the page matches the app theme.
class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _state = AiChatState.instance;
  final _controller = TextEditingController();

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
    showToast(
      context: context,
      showDuration: const Duration(seconds: 2),
      builder: (context, overlay) => const _InfoToast(message: 'Copied to clipboard'),
    );
  }

  void _openSettings() {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) => const _ProviderSettingsDialog(),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final completer = showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) => const _ClearConversationDialog(),
      ),
    );
    final confirmed = await completer.future;
    if (confirmed == true) {
      await _state.clearConversation();
    }
  }

  Future<void> _confirmDeleteSession(String id) async {
    final completer = showOverlay<bool>(
      context,
      DialogConfiguration<bool>(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) => const _DeleteSessionDialog(),
      ),
    );
    final confirmed = await completer.future;
    if (confirmed == true) {
      await _state.deleteSession(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The shadcn theme is installed app-wide by ShadcnApp.
    return _AiChatView(
      state: _state,
      controller: _controller,
      onSend: _send,
      onCopyMessage: _copyMessage,
      onOpenSettings: _openSettings,
      onConfirmClear: _confirmClear,
      onNewChat: () => _state.createSession(),
      onDeleteSession: _confirmDeleteSession,
    );
  }
}

class _AiChatView extends StatelessWidget {
  const _AiChatView({
    required this.state,
    required this.controller,
    required this.onSend,
    required this.onCopyMessage,
    required this.onOpenSettings,
    required this.onConfirmClear,
    required this.onNewChat,
    required this.onDeleteSession,
  });

  final AiChatState state;
  final TextEditingController controller;
  final VoidCallback onSend;
  final void Function(String) onCopyMessage;
  final VoidCallback onOpenSettings;
  final VoidCallback onConfirmClear;
  final VoidCallback onNewChat;
  final void Function(String) onDeleteSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      color: colorScheme.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SessionSidebar(
            state: state,
            onNewChat: onNewChat,
            onDeleteSession: onDeleteSession,
          ),
          Container(width: 1, color: colorScheme.border),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(NexusSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const SizedBox(height: NexusSpacing.md),
                  Expanded(child: _buildTranscript()),
                  const SizedBox(height: NexusSpacing.md),
                  _buildError(),
                  _buildComposer(),
                  const SizedBox(height: NexusSpacing.md),
                  _buildQuickPrompts(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Watch((_) {
            final title = state.activeSession?.title ?? 'AI Chat';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title).large().semiBold(),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  'Ask anything, summarize text, or generate code',
                ).small().muted(),
              ],
            );
          }),
        ),
        const SizedBox(width: NexusSpacing.sm),
        Watch((_) {
          final providers = state.providers.value;
          final active = state.activeProvider;
          final hasMessages = state.messages.value.isNotEmpty;
          final isStreaming = state.isStreaming.value;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (providers.isNotEmpty) ...[
                _ProviderSelect(
                  providers: providers,
                  active: active,
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == _kManageProviders) {
                      onOpenSettings();
                    } else {
                      state.setActiveProvider(value);
                    }
                  },
                ),
                const SizedBox(width: NexusSpacing.sm),
                _ModelSelect(
                  active: active,
                  onChanged: (value) {
                    if (value == null) return;
                    if (value == _kManageProviders) {
                      onOpenSettings();
                    } else if (active != null) {
                      state.setSelectedModel(active.id, value);
                    }
                  },
                ),
                const SizedBox(width: NexusSpacing.sm),
              ],
              Tooltip(
                tooltip: (context) => const Text('Provider settings'),
                child: IconButton.ghost(
                  icon: const Icon(LucideIcons.settings2, size: 18),
                  onPressed: onOpenSettings,
                ),
              ),
              Tooltip(
                tooltip: (context) => const Text('Clear conversation'),
                child: IconButton.ghost(
                  icon: const Icon(LucideIcons.trash2, size: 18),
                  onPressed: hasMessages && !isStreaming
                      ? onConfirmClear
                      : null,
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildTranscript() {
    return Watch((_) {
      if (state.providers.value.isEmpty) {
        return _EmptyState(
          icon: LucideIcons.bot,
          title: 'No provider configured',
          subtitle:
              'Add an OpenAI-compatible provider (OpenAI, DeepSeek, '
              'Kimi, Ollama, …) to start chatting.',
          action: Button.primary(
            leading: const Icon(LucideIcons.settings2),
            onPressed: onOpenSettings,
            child: const Text('Configure providers'),
          ),
        );
      }
      final messages = state.messages.value;
      // The streaming bubble belongs to the session that owns the stream,
      // which may differ from the selected one.
      final streamingHere = state.isStreaming.value &&
          state.streamingSessionId.value == state.activeSessionId.value;
      if (messages.isEmpty && !streamingHere) {
        return _EmptyState(
          icon: LucideIcons.messageCircle,
          title: 'Ask anything',
          subtitle: 'Replies stream in live and render as rich '
              'Markdown with code blocks and tables.',
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(NexusSpacing.md),
        reverse: true,
        itemCount: messages.length + (streamingHere ? 1 : 0),
        itemBuilder: (context, index) {
          if (streamingHere && index == 0) {
            return const _StreamingBubble();
          }
          final message =
              messages[messages.length - 1 - index + (streamingHere ? 1 : 0)];
          return _ChatBubble(
            message: message,
            onCopy: onCopyMessage,
          );
        },
      );
    });
  }

  Widget _buildError() {
    return Watch((_) {
      final error = state.error.value;
      if (error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
        child: Alert.destructive(
          leading: const Icon(LucideIcons.circleAlert, size: 18),
          title: Text(error).small(),
          trailing: IconButton.ghost(
            icon: const Icon(LucideIcons.x, size: 14),
            size: ButtonSize.small,
            onPressed: () => state.error.value = null,
          ),
        ),
      );
    });
  }

  Widget _buildComposer() {
    return Watch((_) {
      final isStreaming = state.isStreaming.value;
      final messages = state.messages.value;
      final canRegenerate = !isStreaming &&
          messages.isNotEmpty &&
          messages.last.role == AiChatRole.assistant;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Tooltip(
            tooltip: (context) => const Text('Regenerate reply'),
            child: IconButton.outline(
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              onPressed: canRegenerate ? () => state.regenerate() : null,
            ),
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
                      onSend();
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: controller,
                  placeholder: const Text(
                    'Type your message… (Enter to send, Shift+Enter '
                    'for a new line)',
                  ),
                  maxLines: 5,
                  minLines: 1,
                ),
              ),
            ),
          ),
          const SizedBox(width: NexusSpacing.sm),
          if (isStreaming)
            Button.secondary(
              leading: const Icon(LucideIcons.circleStop),
              onPressed: state.stopStreaming,
              child: const Text('Stop'),
            )
          else
            Button.primary(
              leading: const Icon(LucideIcons.send),
              onPressed: onSend,
              child: const Text('Send'),
            ),
        ],
      );
    });
  }

  Widget _buildQuickPrompts() {
    return Wrap(
      spacing: NexusSpacing.sm,
      runSpacing: NexusSpacing.sm,
      children: [
        for (final prompt in _quickPrompts)
          Chip(
            onPressed: () => controller.text = prompt,
            child: Text(prompt).small(),
          ),
      ],
    );
  }
}

/// Width of the left rail listing the conversation history.
const _kSidebarWidth = 264.0;

/// Left rail with the "New chat" action and the session history.
class _SessionSidebar extends StatelessWidget {
  const _SessionSidebar({
    required this.state,
    required this.onNewChat,
    required this.onDeleteSession,
  });

  final AiChatState state;
  final VoidCallback onNewChat;
  final void Function(String) onDeleteSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: _kSidebarWidth,
      color: theme.colorScheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(NexusSpacing.sm),
            child: Button.primary(
              leading: const Icon(LucideIcons.plus, size: 16),
              onPressed: onNewChat,
              child: const Text('New chat'),
            ),
          ),
          Expanded(
            child: Watch((_) {
              final sessions = state.sessions.value;
              if (sessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(NexusSpacing.md),
                  child: const Text('No conversations yet').small().muted(),
                );
              }
              final activeId = state.activeSessionId.value;
              final streamingId = state.isStreaming.value
                  ? state.streamingSessionId.value
                  : null;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: NexusSpacing.sm,
                ),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return _SessionTile(
                    session: session,
                    selected: session.id == activeId,
                    streaming: session.id == streamingId,
                    onSelect: () => state.selectSession(session.id),
                    onDelete: () => onDeleteSession(session.id),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// One entry of the session history: title, relative time, delete action, and
/// a pulsing indicator while the session is streaming.
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.streaming,
    required this.onSelect,
    required this.onDelete,
  });

  final AiChatSession session;
  final bool selected;
  final bool streaming;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.xs),
      child: SelectedButton(
        value: selected,
        enabled: true,
        onPressed: onSelect,
        alignment: Alignment.centerLeft,
        style: const ButtonStyle.ghost(density: ButtonDensity.dense),
        selectedStyle: const ButtonStyle.secondary(
          density: ButtonDensity.dense,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.messageCircle,
              size: 14,
              color: theme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    overflow: TextOverflow.ellipsis,
                  ).small().semiBold(),
                  Text(
                    _formatSessionTime(session.updatedAt),
                  ).xSmall().muted(),
                ],
              ),
            ),
            if (streaming)
              const _PulsingDot()
            else
              Tooltip(
                tooltip: (context) => const Text('Delete conversation'),
                child: IconButton.ghost(
                  icon: const Icon(LucideIcons.trash2, size: 14),
                  size: ButtonSize.small,
                  onPressed: onDelete,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact relative timestamp shown under the session title.
String _formatSessionTime(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return time.year == now.year ? '$month-$day' : '${time.year}-$month-$day';
}

const _kManageProviders = '__manage_providers__';

const _quickPrompts = [
  'Summarize selected text',
  'Generate Dart function',
  'Explain a design pattern',
  'Translate to Chinese',
];

class _SendIntent extends Intent {
  const _SendIntent();
}

/// Dropdown picking the active provider, with a manage entry at the end.
class _ProviderSelect extends StatelessWidget {
  const _ProviderSelect({
    required this.providers,
    required this.active,
    required this.onChanged,
  });

  final List<AiProviderConfig> providers;
  final AiProviderConfig? active;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Select<String>(
      value: active?.id,
      constraints: const BoxConstraints(maxWidth: 180),
      // SelectPopup implements SelectPopupBuilder via its `call` method.
      popup: SelectPopup(
        items: SelectItemList(
          children: [
            for (final provider in providers)
              SelectItemButton(
                value: provider.id,
                child: Text(provider.name).small(),
              ),
            SelectItemButton(
              value: _kManageProviders,
              child: Text('Manage providers…').small(),
            ),
          ],
        ),
      ).call,
      itemBuilder: (context, value) {
        final provider = providers.where((p) => p.id == value).firstOrNull;
        return Text(provider?.name ?? 'No provider').small();
      },
      onChanged: onChanged,
    );
  }
}

/// Dropdown picking the model of the active provider; searchable because
/// providers often expose long model lists.
class _ModelSelect extends StatelessWidget {
  const _ModelSelect({required this.active, required this.onChanged});

  final AiProviderConfig? active;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final models = active?.models ?? const <String>[];
    return Select<String>(
      value: active?.selectedModel,
      constraints: const BoxConstraints(maxWidth: 200),
      popup: SelectPopup.builder(
        enableSearch: true,
        searchPlaceholder: const Text('Search models…'),
        builder: (context, searchQuery) => SelectItemList(
          children: [
            if (searchQuery == null)
              SelectItemButton(
                value: _kManageProviders,
                child: Text('Manage models in settings…').small(),
              ),
            for (final model in models)
              if (searchQuery == null ||
                  model.toLowerCase().contains(searchQuery.toLowerCase()))
                SelectItemButton(
                  value: model,
                  child: Text(model).small(),
                ),
          ],
        ),
      ).call,
      itemBuilder: (context, value) => Text(
        value,
        overflow: TextOverflow.ellipsis,
      ).small(),
      onChanged: onChanged,
    );
  }
}

/// Centered placeholder used for the empty transcript / no-provider states.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.muted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 24,
                color: theme.colorScheme.mutedForeground,
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            Text(title).base().semiBold(),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
            ).small().muted(),
            if (action != null) ...[
              const SizedBox(height: NexusSpacing.md),
              action!,
            ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: NexusSpacing.sm),
        padding: const EdgeInsets.all(NexusSpacing.md),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: colorScheme.muted,
          borderRadius: theme.borderRadiusLg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: NexusSpacing.sm),
              child: Avatar(
                initials: 'AI',
                size: 28,
                backgroundColor: colorScheme.secondary,
              ),
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
                        style: theme.typography.base.copyWith(
                          color: colorScheme.foreground,
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
                          reasoning.isEmpty ? 'Connecting…' : 'Thinking…',
                        ).small().muted(),
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
                        Text('Generating…').small().muted(),
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Button.ghost(
          alignment: Alignment.centerLeft,
          onPressed: () => setState(() => _expanded = !_expanded),
          leading: Icon(
            _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
            size: 14,
          ),
          child: Text(
            _expanded ? 'Hide thinking' : 'Show thinking',
          ).small().muted(),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.xs),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(NexusSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.muted,
                borderRadius: theme.borderRadiusMd,
              ),
              child: SelectableText(
                widget.reasoning,
                style: theme.typography.small.copyWith(
                  color: theme.colorScheme.mutedForeground,
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isUser = message.role == AiChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: NexusSpacing.sm),
        padding: const EdgeInsets.all(NexusSpacing.md),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: message.isError
              ? colorScheme.destructive
              : isUser
                  ? colorScheme.primary
                  : colorScheme.muted,
          borderRadius: theme.borderRadiusLg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(right: NexusSpacing.sm),
                child: Avatar(
                  initials: 'AI',
                  size: 28,
                  backgroundColor: colorScheme.secondary,
                ),
              ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isUser &&
                      !message.isError &&
                      message.reasoning.isNotEmpty)
                    _ReasoningDisclosure(reasoning: message.reasoning),
                  if (!isUser &&
                      !message.isError &&
                      message.reasoning.isNotEmpty)
                    const SizedBox(height: NexusSpacing.xs),
                  if (isUser || message.isError)
                    SelectableText(
                      message.content,
                      style: theme.typography.base.copyWith(
                        color: const Color(0xFFFFFFFF),
                      ),
                    )
                  else
                    GptMarkdown(
                      message.content,
                      style: theme.typography.base.copyWith(
                        color: colorScheme.foreground,
                      ),
                      onLinkTap: (url, _) => launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  if (!isUser) ...[
                    const SizedBox(height: NexusSpacing.xs),
                    Tooltip(
                      tooltip: (context) => const Text('Copy'),
                      child: IconButton.ghost(
                        icon: Icon(
                          LucideIcons.copy,
                          size: 14,
                          color: colorScheme.mutedForeground,
                        ),
                        size: ButtonSize.small,
                        onPressed: onCopy != null
                            ? () => onCopy!(message.content)
                            : null,
                      ),
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

/// Minimal toast card shown by [showToast] (e.g. copy feedback).
class _InfoToast extends StatelessWidget {
  const _InfoToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedContainer(
      backgroundColor: theme.colorScheme.popover,
      borderRadius: theme.borderRadiusMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.check,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(message).small(),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog for clearing the transcript.
class _ClearConversationDialog extends StatelessWidget {
  const _ClearConversationDialog();

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: 'Clear conversation?',
      children: [
        Text(
          'This removes the whole transcript from this device.',
        ).small().muted(),
      ],
      actions: (context) => [
        Button.ghost(
          onPressed: () => closeOverlay<bool>(context, false),
          child: const Text('Cancel'),
        ),
        Button.destructive(
          leading: const Icon(LucideIcons.trash2),
          onPressed: () => closeOverlay<bool>(context, true),
          child: const Text('Clear'),
        ),
      ],
    );
  }
}

/// Confirmation dialog for deleting a session from the history.
class _DeleteSessionDialog extends StatelessWidget {
  const _DeleteSessionDialog();

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      title: 'Delete conversation?',
      children: [
        Text(
          'This permanently removes the conversation and its transcript '
          'from this device.',
        ).small().muted(),
      ],
      actions: (context) => [
        Button.ghost(
          onPressed: () => closeOverlay<bool>(context, false),
          child: const Text('Cancel'),
        ),
        Button.destructive(
          leading: const Icon(LucideIcons.trash2),
          onPressed: () => closeOverlay<bool>(context, true),
          child: const Text('Delete'),
        ),
      ],
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
    return _DialogShell(
      title: 'AI Providers',
      width: 560,
      actions: (context) => [
        Button.secondary(
          leading: const Icon(LucideIcons.plus),
          onPressed: () => _openEditor(context, null),
          child: const Text('Add provider'),
        ),
        Button.ghost(
          onPressed: () => closeOverlay(context),
          child: const Text('Close'),
        ),
      ],
      children: [
        Watch((_) {
          final providers = state.providers.value;
          final activeId = state.activeProviderId.value;
          if (providers.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: NexusSpacing.lg),
              child: Text(
                'No providers yet. Add an OpenAI-compatible provider to '
                'start chatting.',
              ).small().muted(),
            );
          }
          return Column(
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
          );
        }),
      ],
    );
  }

  static void _openEditor(BuildContext context, AiProviderConfig? initial) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) => _ProviderEditDialog(initial: initial),
      ),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({required this.provider, required this.selected});

  final AiProviderConfig provider;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = AiChatState.instance;
    return OutlinedContainer(
      borderColor:
          selected ? theme.colorScheme.primary : theme.colorScheme.border,
      borderRadius: theme.borderRadiusMd,
      child: Button.card(
        alignment: Alignment.centerLeft,
        onPressed: () => state.setActiveProvider(provider.id),
        child: Row(
          children: [
            Icon(
              selected ? LucideIcons.circleCheck : LucideIcons.circle,
              size: 18,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.mutedForeground,
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(provider.name).small().semiBold(),
                  const SizedBox(height: 2),
                  Text(
                    '${provider.baseUrl}  ·  '
                    '${provider.selectedModel ?? 'no model'}',
                    overflow: TextOverflow.ellipsis,
                  ).xSmall().muted(),
                ],
              ),
            ),
            Tooltip(
              tooltip: (context) => const Text('Edit'),
              child: IconButton.ghost(
                icon: const Icon(LucideIcons.pencil, size: 16),
                size: ButtonSize.small,
                onPressed: () =>
                    _ProviderSettingsDialog._openEditor(context, provider),
              ),
            ),
            Tooltip(
  tooltip: (context) => const Text('Delete'),
  child: IconButton.ghost(
                icon: const Icon(LucideIcons.trash2, size: 16),
                size: ButtonSize.small,
                onPressed: () {
                  if (state.isStreaming.value &&
                      state.activeProviderId.value == provider.id) {
                    state.stopStreaming();
                  }
                  state.deleteProvider(provider.id);
                },
              ),
),
          ],
        ),
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
  String? _nameError;
  String? _baseUrlError;

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
    setState(() {
      _nameError =
          _name.text.trim().isEmpty ? 'Required' : null;
      _baseUrlError =
          _baseUrl.text.trim().isEmpty ? 'Required' : null;
    });
    if (_nameError != null || _baseUrlError != null) return;
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
      closeOverlay(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _DialogShell(
      title: widget.initial == null ? 'Add provider' : 'Edit provider',
      width: 560,
      scrollable: true,
      actions: (context) => [
        Button.ghost(
          onPressed: () => closeOverlay(context),
          child: const Text('Cancel'),
        ),
        Button.primary(
          leading: const Icon(LucideIcons.check),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
      children: [
        Wrap(
          spacing: NexusSpacing.xs,
          runSpacing: NexusSpacing.xs,
          children: [
            for (final (name, url) in _presets)
              Chip(
                onPressed: () => _applyPreset(name, url),
                child: Text(name).small(),
              ),
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        _LabeledField(
          label: 'Name',
          error: _nameError,
          child: TextField(
            controller: _name,
            placeholder: const Text('e.g. My DeepSeek'),
          ),
        ),
        const SizedBox(height: NexusSpacing.sm),
        _LabeledField(
          label: 'Base URL',
          error: _baseUrlError,
          child: TextField(
            controller: _baseUrl,
            placeholder: const Text('https://api.openai.com/v1'),
          ),
        ),
        const SizedBox(height: NexusSpacing.sm),
        _LabeledField(
          label: 'API key (optional)',
          child: TextField(
            controller: _apiKey,
            placeholder: const Text('sk-…'),
            obscureText: true,
          ),
        ),
        const SizedBox(height: NexusSpacing.sm),
        _LabeledField(
          label: 'System prompt (optional)',
          child: TextField(
            controller: _systemPrompt,
            placeholder: const Text('You are a helpful assistant…'),
            maxLines: 3,
            minLines: 2,
          ),
        ),
        const SizedBox(height: NexusSpacing.md),
        Text('Models').small().semiBold(),
        const SizedBox(height: NexusSpacing.xs),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newModel,
                placeholder: const Text('Model id, e.g. gpt-4o-mini'),
                onSubmitted: (_) => _addManualModel(),
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Button.outline(
              leading: const Icon(LucideIcons.plus),
              onPressed: _addManualModel,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.sm),
        if (_models.isEmpty)
          Text(
            'No models yet — add one manually or fetch the list from '
            'the provider.',
          ).small().muted()
        else
          Wrap(
            spacing: NexusSpacing.xs,
            runSpacing: NexusSpacing.xs,
            children: [
              for (final model in _models)
                Chip(
                  onPressed: () =>
                      setState(() => _selectedModel = model),
                  style: model == _selectedModel
                      ? const ButtonStyle.primary()
                      : const ButtonStyle.secondary(),
                  trailing: ChipButton(
                    onPressed: () => _removeModel(model),
                    child: const Icon(LucideIcons.x, size: 12),
                  ),
                  child: Text(model).small(),
                ),
            ],
          ),
        const SizedBox(height: NexusSpacing.sm),
        Button.outline(
          leading: _fetching
              ? const CircularProgressIndicator(size: 14)
              : const Icon(LucideIcons.cloudDownload),
          onPressed: _fetching ? null : _fetchModels,
          child: const Text('Fetch from API'),
        ),
        if (_error != null) ...[
          const SizedBox(height: NexusSpacing.sm),
          Text(
            _error!,
            style: theme.typography.small.copyWith(
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

/// Label + field + inline validation error, mirroring the shadcn form look.
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.child,
    this.error,
  });

  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label).small().semiBold(),
        const SizedBox(height: NexusSpacing.xs),
        child,
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: theme.typography.xSmall.copyWith(
              color: theme.colorScheme.destructive,
            ),
          ),
        ],
      ],
    );
  }
}

/// Shared modal layout for the page's dialogs: title, body, action row.
class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.title,
    required this.children,
    required this.actions,
    this.width,
    this.scrollable = false,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> Function(BuildContext) actions;
  final double? width;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
    if (scrollable) {
      body = SingleChildScrollView(child: body);
    }
    return ModalContainer(
      filled: true,
      padding: EdgeInsets.all(
        theme.density.baseContainerPadding * theme.scaling,
      ),
      borderRadius: theme.borderRadiusLg,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title).large().semiBold(),
            const SizedBox(height: NexusSpacing.md),
            Flexible(child: body),
            const SizedBox(height: NexusSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: actions(context),
            ),
          ],
        ),
      ),
    );
  }
}
