import 'package:flutter/foundation.dart';

/// Roles used in the chat transcript.
enum AiChatRole { user, assistant }

/// One message in the AI chat transcript.
@immutable
class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.reasoning = '',
    this.isError = false,
  });

  final String id;
  final AiChatRole role;

  /// Raw model output in Markdown; rendered richly for assistant messages.
  final String content;
  final DateTime createdAt;

  /// Chain-of-thought text streamed by reasoning models before [content];
  /// empty for regular models.
  final String reasoning;

  /// Marks a message that holds an error report instead of a real reply.
  final bool isError;

  AiChatMessage copyWith({
    String? id,
    AiChatRole? role,
    String? content,
    DateTime? createdAt,
    String? reasoning,
    bool? isError,
  }) {
    return AiChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      reasoning: reasoning ?? this.reasoning,
      isError: isError ?? this.isError,
    );
  }

  factory AiChatMessage.fromJson(Map<String, dynamic> json) {
    return AiChatMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] == 'user' ? AiChatRole.user : AiChatRole.assistant,
      content: json['content'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      reasoning: json['reasoning'] as String? ?? '',
      isError: json['isError'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'reasoning': reasoning,
        'isError': isError,
      };
}
