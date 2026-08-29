import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/ai_chat_message.dart';
import '../models/ai_provider_config.dart';

/// One streamed increment of a chat completion.
///
/// Reasoning models (e.g. on OpenRouter) stream their chain of thought in
/// [reasoning] before (or instead of) the visible answer in [content].
class AiChatDelta {
  const AiChatDelta({this.reasoning, this.content});

  final String? reasoning;
  final String? content;

  bool get isEmpty =>
      (reasoning == null || reasoning!.isEmpty) &&
      (content == null || content!.isEmpty);
}

/// Error carrying a human-readable reason for chat/model API failures.
class AiChatException implements Exception {
  const AiChatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a request was cancelled via its [CancelToken]; not an error.
class AiChatCancelledException implements Exception {
  const AiChatCancelledException();
}

/// Talks to OpenAI-compatible chat APIs (`/chat/completions` + `/models`)
/// with SSE streaming support.
///
/// Uses its own [Dio] instance: chat endpoints live on foreign hosts, need
/// provider-specific auth headers, and must not inherit short receive
/// timeouts which would kill long streamed completions.
class AiChatRepository {
  AiChatRepository({Dio? dio})
      : _dio =
            dio ??
            Dio(
              BaseOptions(
                // Applies to the connection phase only; the streamed
                // completion sets its own gap timeout per request.
                connectTimeout: const Duration(seconds: 15),
              ),
            );

  final Dio _dio;

  /// Streams a chat completion, yielding each delta as it arrives.
  ///
  /// [history] is sent as-is (already capped by the caller). Cancelling
  /// [cancelToken] stops the request; the resulting exception is rethrown
  /// for the caller to classify.
  Stream<AiChatDelta> streamChat({
    required AiProviderConfig provider,
    required String model,
    required List<AiChatMessage> history,
    CancelToken? cancelToken,
  }) async* {
    final base = _normalizeBaseUrl(provider.baseUrl);
    final messages = <Map<String, String>>[
      if (provider.systemPrompt.trim().isNotEmpty)
        {'role': 'system', 'content': provider.systemPrompt.trim()},
      for (final message in history)
        {'role': message.role.name, 'content': message.content},
    ];

    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        '$base/chat/completions',
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          headers: _headers(provider),
          // Generous gap timeout: slow reasoning models can sit silent for a
          // long time between chunks.
          receiveTimeout: const Duration(minutes: 5),
        ),
        data: {
          'model': model,
          'messages': messages,
          'stream': true,
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const AiChatCancelledException();
      }
      if (e.type == DioExceptionType.badResponse) {
        throw AiChatException(
          'Provider returned HTTP ${e.response?.statusCode}: '
          '${await _readErrorBody(e.response?.data)}',
        );
      }
      throw _toChatException(e);
    }

    final body = response.data;
    if (body == null) {
      throw const AiChatException('Empty response from the provider.');
    }

    // utf8.decoder + LineSplitter keep SSE events and multi-byte characters
    // intact across chunk boundaries.
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines) {
        if (line.isEmpty || line.startsWith(':')) continue;
        // Strip the `data:` field name plus any whitespace after it — a
        // plain substring(4) would leave the colon behind and break JSON
        // parsing.
        if (!line.startsWith('data:')) continue;
        final payload = line.replaceFirst(RegExp(r'^data:\s*'), '').trim();
        if (payload == '[DONE]') return;
        final delta = _extractDelta(payload);
        if (!delta.isEmpty) yield delta;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw const AiChatCancelledException();
      }
      throw _toChatException(e);
    } on FormatException catch (e) {
      throw AiChatException('Malformed stream event: ${e.message}');
    }
  }

  /// Asks the model for a short title summarizing the opening exchange of a
  /// conversation (non-streaming). Used to auto-name sessions after their
  /// first reply; callers fall back to a local heuristic on failure.
  Future<String> generateTitle({
    required AiProviderConfig provider,
    required String model,
    required String userMessage,
    required String assistantMessage,
  }) async {
    final base = _normalizeBaseUrl(provider.baseUrl);
    String excerpt(String text) =>
        text.length > 500 ? '${text.substring(0, 500)}…' : text;
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '$base/chat/completions',
        options: Options(
          headers: _headers(provider),
          receiveTimeout: const Duration(seconds: 30),
        ),
        data: {
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': 'You name chat conversations. Reply with a concise '
                  'title of at most 6 words, in the language of the '
                  'conversation. Output the title only — no quotes, no '
                  'numbering, no trailing punctuation.',
            },
            {
              'role': 'user',
              'content': 'User: ${excerpt(userMessage)}\n\n'
                  'Assistant: ${excerpt(assistantMessage)}',
            },
          ],
          'stream': false,
          'max_tokens': 64,
        },
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        throw AiChatException(
          'Provider returned HTTP ${e.response?.statusCode}: '
          '${await _readErrorBody(e.response?.data)}',
        );
      }
      throw _toChatException(e);
    }
    final choices = response.data?['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiChatException(
        'Unexpected /chat/completions response: missing choices.',
      );
    }
    final choice = choices.first;
    final message = choice is Map<String, dynamic> ? choice['message'] : null;
    final content = message is Map<String, dynamic> ? message['content'] : null;
    if (content is! String || content.trim().isEmpty) {
      throw const AiChatException(
        'Unexpected /chat/completions response: missing message content.',
      );
    }
    return content;
  }

  /// Fetches the model ids advertised by the provider's `/models` endpoint.
  Future<List<String>> fetchModels(AiProviderConfig provider) async {
    final base = _normalizeBaseUrl(provider.baseUrl);
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$base/models',
        options: Options(headers: _headers(provider)),
      );
      final data = response.data?['data'];
      if (data is! List) {
        throw const AiChatException(
          'Unexpected /models response: expected a "data" list.',
        );
      }
      return data
          .map(
            (e) => e is Map<String, dynamic> ? e['id'] as String? : null,
          )
          .whereType<String>()
          .toList(growable: false);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        throw AiChatException(
          'Provider returned HTTP ${e.response?.statusCode}: '
          '${await _readErrorBody(e.response?.data)}',
        );
      }
      throw _toChatException(e);
    } on TypeError {
      throw const AiChatException('Unexpected /models response format.');
    }
  }

  Map<String, String> _headers(AiProviderConfig provider) => {
        if (provider.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${provider.apiKey.trim()}',
      };

  /// Extracts `choices[0].delta` from an SSE event payload; content and
  /// reasoning are both absent for role-only events and usage summaries.
  AiChatDelta _extractDelta(String payload) {
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(payload) as Map<String, dynamic>;
    } on FormatException {
      throw FormatException('invalid JSON in SSE event', payload);
    }
    final choices = event['choices'];
    if (choices is! List || choices.isEmpty) {
      return const AiChatDelta();
    }
    final choice = choices.first;
    if (choice is! Map<String, dynamic>) return const AiChatDelta();
    final delta = choice['delta'];
    if (delta is! Map<String, dynamic>) return const AiChatDelta();
    return AiChatDelta(
      reasoning: delta['reasoning'] as String?,
      content: delta['content'] as String?,
    );
  }

  String _normalizeBaseUrl(String url) =>
      url.trim().replaceAll(RegExp(r'/+$'), '');

  /// Reads the error body out of a failed response. With streaming requests
  /// the payload is an unread [ResponseBody], so drain it to reach the
  /// provider's JSON error message.
  static Future<String> _readErrorBody(Object? data) async {
    var detail = '';
    if (data is ResponseBody) {
      try {
        detail = await data.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
      } catch (_) {
        detail = '';
      }
    } else if (data is Map<String, dynamic>) {
      final error = data['error'];
      if (error is Map<String, dynamic> && error['message'] is String) {
        detail = error['message'] as String;
      } else if (data['message'] is String) {
        detail = data['message'] as String;
      }
    } else if (data is String) {
      detail = data;
    }
    detail = detail.trim();
    if (detail.length > 300) detail = '${detail.substring(0, 300)}…';
    return detail.isEmpty ? 'no details' : detail;
  }

  AiChatException _toChatException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const AiChatException('Request timed out. '
            'Check the base URL or try a model that responds faster.');
      case DioExceptionType.connectionError:
        return const AiChatException(
          'Could not connect to the provider. Check the base URL and network.',
        );
      case DioExceptionType.badResponse:
        return const AiChatException('Provider returned an error response.');
      case DioExceptionType.cancel:
        // Callers intercept cancels before reaching here; keep a sane
        // fallback just in case.
        return const AiChatException('Request cancelled.');
      default:
        return AiChatException('Request failed: ${e.message}');
    }
  }
}
