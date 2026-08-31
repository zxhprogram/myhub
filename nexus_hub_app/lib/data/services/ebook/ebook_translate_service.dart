import 'package:flutter/foundation.dart';

import '../../models/ai_chat_message.dart';
import '../../models/ai_provider_config.dart';
import '../../repositories/ai_chat_repository.dart';

/// AI-powered translation for the ebook reader.
///
/// Every call is a standalone session: exactly one system prompt plus one
/// user message is sent, with no conversation history. The selected text is
/// explained/translated into Chinese via an OpenAI-compatible provider
/// (reusing [AiChatRepository] and the provider configs shared with the
/// AI Chat sub-app).
class EbookTranslateService {
  EbookTranslateService({AiChatRepository? repository})
    : _repository = repository ?? AiChatRepository();

  final AiChatRepository _repository;

  /// Default instruction for translation requests.
  static const defaultPrompt = '''
你是一位阅读助手兼词典。用户在阅读时从书中选中了一段文字，请先判断其语言，再按以下规则用中文回答：

- 若选中的是英文或其他外语的单词、短语或习语：给出中文释义，按不同含义分条列出；每个含义配一个原文例句，例句后附中文翻译；最后列出常见的同义词/近义词（若有）。
- 若选中的是英文或其他外语的句子或段落：将其翻译成中文，再用一两句话说明关键含义或背景。
- 若选中的是中文：将其翻译成英文，并简要说明关键词汇。

每次请求都是一次独立的翻译会话，只处理本次提供的文字，不要参考之前的对话。输出使用清晰的 Markdown 小标题分段。''';

  /// Streams the translation for [text] as Markdown chunks (each yield is
  /// an increment, not the full transcript).
  ///
  /// Some OpenAI-compatible servers answer `stream:true` requests with a
  /// plain JSON body instead of SSE events; in that case the stream ends
  /// without any content. To stay usable with those servers, the service
  /// falls back to a single non-streaming completion when nothing arrived.
  Stream<String> stream({
    required AiProviderConfig provider,
    required String model,
    required String text,
  }) async* {
    debugPrint(
      '[EbookTranslate] start: provider=${provider.name} '
      'model=$model text=${text.length} chars',
    );
    var received = false;
    try {
      final message = AiChatMessage(
        id: 'ebook-translate',
        role: AiChatRole.user,
        content: '选中的文字：\n\n$text',
        createdAt: DateTime.now(),
      );
      await for (final delta in _repository.streamChat(
        provider: provider.copyWith(systemPrompt: defaultPrompt),
        model: model,
        history: [message],
      )) {
        final content = delta.content;
        if (content != null && content.isNotEmpty) {
          received = true;
          yield content;
        }
      }
    } catch (e) {
      debugPrint('[EbookTranslate] stream failed: $e');
      rethrow;
    }

    if (received) {
      debugPrint('[EbookTranslate] done (streamed)');
      return;
    }

    debugPrint(
      '[EbookTranslate] stream returned no content; '
      'retrying without streaming',
    );
    final answer = await _repository.complete(
      provider: provider,
      model: model,
      systemPrompt: defaultPrompt,
      userMessage: '选中的文字：\n\n$text',
    );
    if (answer.trim().isEmpty) {
      throw const AiChatExceptionIsEmpty();
    }
    debugPrint('[EbookTranslate] done (non-streamed fallback)');
    yield answer;
  }
}

/// Thrown when the provider answered but with an empty message.
class AiChatExceptionIsEmpty implements Exception {
  const AiChatExceptionIsEmpty();

  @override
  String toString() => 'AI 未返回任何内容，请检查所选模型是否可用。';
}
