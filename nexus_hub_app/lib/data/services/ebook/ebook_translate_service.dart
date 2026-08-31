import '../../models/ai_chat_message.dart';
import '../../models/ai_provider_config.dart';
import '../../repositories/ai_chat_repository.dart';

/// AI-powered translation for the ebook reader.
///
/// Sends the reader's selected text to an OpenAI-compatible provider
/// (reusing [AiChatRepository] and the provider configs shared with the
/// AI Chat sub-app) and streams the answer back as plain Markdown.
class EbookTranslateService {
  EbookTranslateService({AiChatRepository? repository})
    : _repository = repository ?? AiChatRepository();

  final AiChatRepository _repository;

  /// Default instruction for translation requests: explain the meaning(s)
  /// with one example sentence each, plus synonyms; translate longer
  /// selections instead of treating them as dictionary entries.
  static const defaultPrompt = '''
你是一位阅读助手兼词典。用户在阅读时从书中选中了一段文字，请用中文回答：

- 若选中的是一个词、短语或习语：解释它的每个含义，每个含义单独一条，并给每个含义配一个例句（例句用原文语言，后面附上中文翻译）。
- 若选中的是句子或段落：先给出通顺的中文翻译，再用一两句话说明其关键含义或背景。
- 最后列出该词/短语常见的同义词和近义词（若有），用简洁的列表呈现。

输出使用清晰的 Markdown 小标题分段。除代码和例句外，全部使用中文。''';

  /// Streams the translation for [text] as accumulated Markdown chunks.
  ///
  /// Each yielded string is a new increment (not the full transcript);
  /// the caller appends it to the displayed output.
  Stream<String> stream({
    required AiProviderConfig provider,
    required String model,
    required String text,
  }) async* {
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
      if (content != null && content.isNotEmpty) yield content;
    }
  }
}
