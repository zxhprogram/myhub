import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_avatar.dart';
import '../components/nexus_button.dart';
import '../components/nexus_card.dart';
import '../components/nexus_input.dart';
import '../layout/page_scaffold.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({super.key});

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  final _controller = TextEditingController();
  final _messages = <_Message>[
    _Message(
      role: _Role.assistant,
      text: 'Hello! I am Nexus AI. How can I help you today?',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message(role: _Role.user, text: text));
      _messages.add(
        _Message(
          role: _Role.assistant,
          text: 'I received: "$text". This is a placeholder response.',
        ),
      );
    });
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Chat', style: NexusTypography.headlineXl),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            'Ask anything, summarize text, or generate code',
            style: NexusTypography.bodyMd.copyWith(
              color: NexusColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          NexusCard(
            padding: const EdgeInsets.all(0),
            child: SizedBox(
              height: 480,
              child: ListView.builder(
                padding: const EdgeInsets.all(NexusSpacing.md),
                reverse: true,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[_messages.length - 1 - index];
                  return _ChatBubble(message: message);
                },
              ),
            ),
          ),
          const SizedBox(height: NexusSpacing.md),
          Row(
            children: [
              Expanded(
                child: NexusInput(
                  controller: _controller,
                  hintText: 'Type your message...',
                  suffixIcon: IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(label: 'Send', icon: Icons.send, onPressed: _send),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Wrap(
            spacing: NexusSpacing.sm,
            runSpacing: NexusSpacing.sm,
            children:
                [
                      'Summarize selected text',
                      'Generate Dart function',
                      'Explain a design pattern',
                      'Translate to Chinese',
                    ]
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

enum _Role { user, assistant }

class _Message {
  const _Message({required this.role, required this.text});

  final _Role role;
  final String text;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _Message message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == _Role.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: NexusSpacing.sm),
        padding: const EdgeInsets.all(NexusSpacing.md),
        constraints: const BoxConstraints(maxWidth: 640),
        decoration: BoxDecoration(
          color: isUser ? NexusColors.primary : NexusColors.surfaceContainer,
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
              child: Text(
                message.text,
                style: NexusTypography.bodyMd.copyWith(
                  color: isUser ? NexusColors.onPrimary : NexusColors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
