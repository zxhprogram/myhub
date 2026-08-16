import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/ai_chat_message.dart';
import '../../data/models/ai_provider_config.dart';
import '../../data/repositories/ai_chat_repository.dart';

/// Signals-based state for the AI Chat app.
///
/// Provider configs and the transcript persist across restarts via
/// [SharedPreferences] (same approach as [TerminalState]). While a completion
/// streams in, the partial text lives in [streamingText] so only the active
/// bubble rebuilds on every delta; it is folded into [messages] once the
/// stream finishes.
class AiChatState {
  AiChatState._() : _repository = AiChatRepository();

  /// The singleton instance used across the app.
  static final AiChatState instance = AiChatState._();

  static const _providersKey = 'nexus_ai_providers_v1';
  static const _activeKey = 'nexus_ai_active_provider_v1';
  static const _messagesKey = 'nexus_ai_messages_v1';

  /// How many recent messages are sent along with each request.
  static const _maxHistoryLength = 30;

  /// Messages kept in persisted storage (older ones are dropped).
  static const _maxPersistedMessages = 200;

  static int _idCounter = 0;

  final AiChatRepository _repository;
  CancelToken? _cancelToken;

  /// Set by [stopStreaming]; aborting the request surfaces as a low-level
  /// stream error rather than a DioException, so the flag is what tells
  /// [_runCompletion] that the failure was user-initiated.
  bool _stopRequested = false;

  final providers = signal<List<AiProviderConfig>>(const []);
  final activeProviderId = signal<String?>(null);
  final messages = signal<List<AiChatMessage>>(const []);
  final streamingText = signal<String?>(null);
  final streamingReasoning = signal<String?>(null);
  final isStreaming = signal<bool>(false);
  final isFetchingModels = signal<bool>(false);
  final error = signal<String?>(null);

  bool _initialized = false;

  /// Loads persisted data once; safe to call from every entry point.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    try {
      final rawProviders = prefs.getString(_providersKey);
      if (rawProviders != null && rawProviders.isNotEmpty) {
        final list = jsonDecode(rawProviders) as List<dynamic>;
        providers.value = list
            .map(
              (e) => AiProviderConfig.fromJson(e as Map<String, dynamic>),
            )
            .toList(growable: false);
      }
      final activeId = prefs.getString(_activeKey);
      if (activeId != null &&
          providers.value.any((p) => p.id == activeId)) {
        activeProviderId.value = activeId;
      } else if (providers.value.isNotEmpty) {
        activeProviderId.value = providers.value.first.id;
      }
      final rawMessages = prefs.getString(_messagesKey);
      if (rawMessages != null && rawMessages.isNotEmpty) {
        final list = jsonDecode(rawMessages) as List<dynamic>;
        messages.value = list
            .map((e) => AiChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      }
    } catch (_) {
      // Corrupted storage — start fresh rather than crash.
    }
  }

  AiProviderConfig? get activeProvider {
    final id = activeProviderId.value;
    if (id == null) return null;
    return providers.value.where((p) => p.id == id).firstOrNull;
  }

  /// Adds a new provider and activates it when it is the first one.
  Future<void> addProvider(AiProviderConfig provider) async {
    providers.value = [...providers.value, provider];
    if (activeProviderId.value == null) {
      activeProviderId.value = provider.id;
    }
    await _persistProviders();
  }

  /// Replaces the stored provider that shares [provider]'s id.
  Future<void> updateProvider(AiProviderConfig provider) async {
    providers.value = [
      for (final p in providers.value)
        if (p.id == provider.id) provider else p,
    ];
    await _persistProviders();
  }

  /// Removes the provider with [id]; the active provider falls back to the
  /// first remaining one.
  Future<void> deleteProvider(String id) async {
    providers.value =
        providers.value.where((p) => p.id != id).toList(growable: false);
    if (activeProviderId.value == id) {
      activeProviderId.value = providers.value.isNotEmpty
          ? providers.value.first.id
          : null;
    }
    await _persistProviders();
  }

  void setActiveProvider(String id) {
    if (providers.value.any((p) => p.id == id)) {
      activeProviderId.value = id;
      _persistProviders();
    }
  }

  /// Persists [model] as the provider's selected model.
  Future<void> setSelectedModel(String providerId, String model) async {
    final provider = providers.value
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return;
    await updateProvider(provider.copyWith(selectedModel: model));
  }

  /// Fetches the model list from the provider's API and merges it into the
  /// stored config. Returns the merged list.
  Future<List<String>> fetchModels(String providerId) async {
    final provider = providers.value
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return const [];
    isFetchingModels.value = true;
    try {
      final fetched = await _repository.fetchModels(provider);
      final merged = <String>{...provider.models, ...fetched}.toList()
        ..sort();
      var updated = provider.copyWith(models: merged);
      if ((updated.selectedModel ?? '').isEmpty && merged.isNotEmpty) {
        updated = updated.copyWith(selectedModel: merged.first);
      }
      await updateProvider(updated);
      return merged;
    } finally {
      isFetchingModels.value = false;
    }
  }

  /// Sends [text] as a new user message and streams the reply.
  Future<void> sendMessage(String text) async {
    final content = text.trim();
    if (content.isEmpty || isStreaming.value) return;
    final provider = activeProvider;
    final model = provider?.selectedModel ?? '';
    if (provider == null || model.isEmpty) {
      error.value =
          'No provider or model selected. Open the provider settings first.';
      return;
    }

    error.value = null;
    final userMessage = AiChatMessage(
      id: generateId(),
      role: AiChatRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    final history = [...messages.value, userMessage];
    messages.value = history;
    await _persistMessages();

    await _runCompletion(provider, model, history);
  }

  /// Drops the last assistant reply (if any) and regenerates it from the
  /// last user message.
  Future<void> regenerate() async {
    if (isStreaming.value) return;
    final provider = activeProvider;
    final model = provider?.selectedModel ?? '';
    if (provider == null || model.isEmpty) {
      error.value =
          'No provider or model selected. Open the provider settings first.';
      return;
    }

    var history = [...messages.value];
    if (history.isNotEmpty && history.last.role == AiChatRole.assistant) {
      history = history.sublist(0, history.length - 1);
    }
    if (history.isEmpty || history.last.role != AiChatRole.user) return;

    messages.value = history;
    await _persistMessages();
    await _runCompletion(provider, model, history);
  }

  /// Stops the in-flight completion, keeping whatever text arrived so far.
  void stopStreaming() {
    _stopRequested = true;
    _cancelToken?.cancel();
  }

  Future<void> clearConversation() async {
    messages.value = const [];
    streamingText.value = null;
    streamingReasoning.value = null;
    error.value = null;
    await _persistMessages();
  }

  Future<void> _runCompletion(
    AiProviderConfig provider,
    String model,
    List<AiChatMessage> history,
  ) async {
    isStreaming.value = true;
    streamingText.value = '';
    streamingReasoning.value = '';
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    _cancelToken = CancelToken();

    var failureMessage = 'The model returned an empty response.';
    try {
      final sent = history.length > _maxHistoryLength
          ? history.sublist(history.length - _maxHistoryLength)
          : history;
      await for (final delta in _repository.streamChat(
        provider: provider,
        model: model,
        history: sent,
        cancelToken: _cancelToken,
      )) {
        if ((delta.reasoning ?? '').isNotEmpty) {
          reasoningBuffer.write(delta.reasoning);
          streamingReasoning.value = reasoningBuffer.toString();
        }
        if ((delta.content ?? '').isNotEmpty) {
          contentBuffer.write(delta.content);
          streamingText.value = contentBuffer.toString();
        }
      }
    } on AiChatCancelledException {
      // User pressed stop — keep the partial text, no error.
    } on AiChatException catch (e) {
      if (!_stopRequested) failureMessage = e.message;
    } catch (e) {
      if (!_stopRequested) failureMessage = e.toString();
    } finally {
      _cancelToken = null;
      isStreaming.value = false;
      streamingText.value = null;
      streamingReasoning.value = null;
    }

    final text = contentBuffer.toString();
    final stoppedEmpty = _stopRequested && text.isEmpty;
    if (!stoppedEmpty) {
      final completed = AiChatMessage(
        id: generateId(),
        role: AiChatRole.assistant,
        content: text.isNotEmpty ? text : '⚠ $failureMessage',
        createdAt: DateTime.now(),
        reasoning: reasoningBuffer.toString(),
        isError: text.isEmpty,
      );
      if (text.isEmpty) {
        error.value = failureMessage;
      }
      messages.value = [...messages.value, completed];
      await _persistMessages();
    }
    _stopRequested = false;
  }

  Future<void> _persistProviders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _providersKey,
      jsonEncode(providers.value.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(_activeKey, activeProviderId.value ?? '');
  }

  Future<void> _persistMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final recent = messages.value.length > _maxPersistedMessages
        ? messages.value.sublist(messages.value.length - _maxPersistedMessages)
        : messages.value;
    await prefs.setString(
      _messagesKey,
      jsonEncode(recent.map((m) => m.toJson()).toList()),
    );
  }

  /// Stable-enough id: timestamp prefix + monotonic counter.
  static String generateId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }
}
