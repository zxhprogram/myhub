import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/ai_chat_message.dart';
import '../../data/models/ai_chat_session.dart';
import '../../data/models/ai_provider_config.dart';
import '../../data/repositories/ai_chat_repository.dart';

/// Signals-based state for the AI Chat app.
///
/// Provider configs and the session list persist across restarts via
/// [SharedPreferences] (same approach as [TerminalState]). While a completion
/// streams in, the partial text lives in [streamingText] so only the active
/// bubble rebuilds on every delta; it is folded into the owning session once
/// the stream finishes. New sessions start with the placeholder title
/// [defaultSessionTitle] and are named by the model after their first reply,
/// falling back to a truncated version of the opening question.
class AiChatState {
  AiChatState._() : _repository = AiChatRepository();

  /// The singleton instance used across the app.
  static final AiChatState instance = AiChatState._();

  static const _providersKey = 'nexus_ai_providers_v1';
  static const _activeKey = 'nexus_ai_active_provider_v1';
  static const _sessionsKey = 'nexus_ai_sessions_v1';

  /// Legacy single-transcript key; imported once, then dropped.
  static const _legacyMessagesKey = 'nexus_ai_messages_v1';

  /// Title shown until the model names the session after its first reply.
  static const defaultSessionTitle = 'New chat';

  /// How many recent messages are sent along with each request.
  static const _maxHistoryLength = 30;

  /// Messages kept per session in persisted storage (older ones are dropped).
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
  final sessions = signal<List<AiChatSession>>(const []);
  final activeSessionId = signal<String?>(null);

  /// Messages of the active session; recomputed whenever the session list or
  /// the selection changes.
  late final messages = computed(
    () => activeSession?.messages ?? const <AiChatMessage>[],
  );

  final streamingText = signal<String?>(null);
  final streamingReasoning = signal<String?>(null);

  /// Session that owns the in-flight completion; may differ from the active
  /// session when the user switched conversations mid-stream.
  final streamingSessionId = signal<String?>(null);
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
      _loadSessions(prefs);
    } catch (_) {
      // Corrupted storage — start fresh rather than crash.
    }
    if (sessions.value.isEmpty) {
      await createSession();
    } else {
      final id = activeSessionId.value;
      if (id == null || !sessions.value.any((s) => s.id == id)) {
        activeSessionId.value = sessions.value.first.id;
      }
    }
  }

  void _loadSessions(SharedPreferences prefs) {
    final raw = prefs.getString(_sessionsKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final list = decoded['sessions'];
        if (list is List && list.isNotEmpty) {
          sessions.value = list
              .map((e) => AiChatSession.fromJson(e as Map<String, dynamic>))
              .toList(growable: false);
        }
        final active = decoded['activeSessionId'];
        if (active is String && active.isNotEmpty) {
          activeSessionId.value = active;
        }
      }
    } else {
      _importLegacyTranscript(prefs);
    }
  }

  /// Wraps the pre-session transcript storage into a single session.
  void _importLegacyTranscript(SharedPreferences prefs) {
    final raw = prefs.getString(_legacyMessagesKey);
    if (raw == null || raw.isEmpty) return;
    final list = jsonDecode(raw) as List<dynamic>;
    final messages = list
        .map((e) => AiChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();
    if (messages.isEmpty) return;
    final session = AiChatSession(
      id: generateId(),
      title: _fallbackTitleFromMessages(messages),
      createdAt: messages.first.createdAt,
      updatedAt: messages.last.createdAt,
      messages: messages,
    );
    sessions.value = [session];
    prefs.remove(_legacyMessagesKey);
  }

  AiProviderConfig? get activeProvider {
    final id = activeProviderId.value;
    if (id == null) return null;
    return providers.value.where((p) => p.id == id).firstOrNull;
  }

  AiChatSession? get activeSession {
    final id = activeSessionId.value;
    if (id == null) return null;
    return sessions.value.where((s) => s.id == id).firstOrNull;
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

  /// Creates an empty session, activates it, and persists the list.
  Future<void> createSession() async {
    final now = DateTime.now();
    final session = AiChatSession(
      id: generateId(),
      title: defaultSessionTitle,
      createdAt: now,
      updatedAt: now,
    );
    sessions.value = [session, ...sessions.value];
    activeSessionId.value = session.id;
    error.value = null;
    await _persistSessions();
  }

  /// Activates the session with [id].
  void selectSession(String id) {
    if (activeSessionId.value == id) return;
    if (sessions.value.any((s) => s.id == id)) {
      activeSessionId.value = id;
      error.value = null;
      _persistSessions();
    }
  }

  /// Deletes the session with [id]; the active one falls back to the nearest
  /// remaining session (or a fresh one when the list empties).
  Future<void> deleteSession(String id) async {
    if (isStreaming.value && streamingSessionId.value == id) {
      stopStreaming();
    }
    final index = sessions.value.indexWhere((s) => s.id == id);
    if (index < 0) return;
    sessions.value =
        sessions.value.where((s) => s.id != id).toList(growable: false);
    if (activeSessionId.value == id) {
      if (sessions.value.isEmpty) {
        await createSession();
        return;
      }
      activeSessionId.value =
          sessions.value[index.clamp(0, sessions.value.length - 1)].id;
    }
    await _persistSessions();
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
    var session = activeSession;
    if (session == null) {
      await createSession();
      session = activeSession;
      if (session == null) return;
    }
    final userMessage = AiChatMessage(
      id: generateId(),
      role: AiChatRole.user,
      content: content,
      createdAt: DateTime.now(),
    );
    final history = [...session.messages, userMessage];
    _replaceSession(
      session.copyWith(messages: history, updatedAt: userMessage.createdAt),
    );
    await _persistSessions();

    await _runCompletion(provider, model, history, session.id);
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

    final session = activeSession;
    if (session == null) return;
    var history = [...session.messages];
    if (history.isNotEmpty && history.last.role == AiChatRole.assistant) {
      history = history.sublist(0, history.length - 1);
    }
    if (history.isEmpty || history.last.role != AiChatRole.user) return;

    _replaceSession(
      session.copyWith(messages: history, updatedAt: DateTime.now()),
    );
    await _persistSessions();
    await _runCompletion(provider, model, history, session.id);
  }

  /// Stops the in-flight completion, keeping whatever text arrived so far.
  void stopStreaming() {
    _stopRequested = true;
    _cancelToken?.cancel();
  }

  /// Empties the active session's transcript and resets its title so the
  /// next exchange auto-names it again.
  Future<void> clearConversation() async {
    final session = activeSession;
    if (session == null) return;
    _replaceSession(
      session.copyWith(
        messages: const [],
        title: defaultSessionTitle,
        updatedAt: DateTime.now(),
      ),
    );
    streamingText.value = null;
    streamingReasoning.value = null;
    error.value = null;
    await _persistSessions();
  }

  Future<void> _runCompletion(
    AiProviderConfig provider,
    String model,
    List<AiChatMessage> history,
    String sessionId,
  ) async {
    isStreaming.value = true;
    streamingSessionId.value = sessionId;
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
      streamingSessionId.value = null;
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
      await _appendToSession(sessionId, completed);
      _maybeAutoName(sessionId, provider, model, history, completed);
    }
    _stopRequested = false;
  }

  /// Appends [message] to the session owning the completion — which may no
  /// longer be the active one (or may be deleted) if the user switched or
  /// removed it mid-stream.
  Future<void> _appendToSession(
    String sessionId,
    AiChatMessage message,
  ) async {
    final session = sessions.value.where((s) => s.id == sessionId).firstOrNull;
    if (session == null) return;
    _replaceSession(
      session.copyWith(
        messages: [...session.messages, message],
        updatedAt: DateTime.now(),
      ),
    );
    await _persistSessions();
  }

  /// Names a still-untitled session after its first assistant reply, asking
  /// the model for a short title and falling back to the opening question.
  /// Fire-and-forget: a slow or failing title request never blocks the chat.
  Future<void> _maybeAutoName(
    String sessionId,
    AiProviderConfig provider,
    String model,
    List<AiChatMessage> history,
    AiChatMessage reply,
  ) async {
    final session = sessions.value.where((s) => s.id == sessionId).firstOrNull;
    if (session == null || session.title != defaultSessionTitle) return;
    final question = history.reversed
        .where((m) => m.role == AiChatRole.user)
        .firstOrNull
        ?.content ?? '';
    var title = _fallbackTitle(question);
    if (!reply.isError && question.isNotEmpty) {
      try {
        final generated = await _repository.generateTitle(
          provider: provider,
          model: model,
          userMessage: question,
          assistantMessage: reply.content,
        );
        final normalized = _normalizeTitle(generated);
        if (normalized != null) title = normalized;
      } catch (_) {
        // Keep the fallback title when the provider can't summarize.
      }
    }
    // The session may have been renamed-again, cleared, or deleted while the
    // title request was in flight.
    final current =
        sessions.value.where((s) => s.id == sessionId).firstOrNull;
    if (current == null || current.title != defaultSessionTitle) return;
    _replaceSession(current.copyWith(title: title));
    await _persistSessions();
  }

  /// Replaces the session with the same id and keeps the list sorted by
  /// recency.
  void _replaceSession(AiChatSession session) {
    final updated = [
      for (final s in sessions.value) if (s.id == session.id) session else s,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    sessions.value = updated;
  }

  /// Truncates the first line of [text] into a serviceable session title.
  static String _fallbackTitle(String text) {
    var line = text.trim();
    final newline = line.indexOf('\n');
    if (newline >= 0) line = line.substring(0, newline);
    line = line.trim();
    if (line.isEmpty) return defaultSessionTitle;
    return line.length > 32 ? '${line.substring(0, 32)}…' : line;
  }

  static String _fallbackTitleFromMessages(List<AiChatMessage> messages) {
    final first = messages.where((m) => m.role == AiChatRole.user).firstOrNull;
    return first == null ? 'Chat' : _fallbackTitle(first.content);
  }

  /// Cleans up a model-generated title; null when it is unusable.
  static String? _normalizeTitle(String raw) {
    var title = raw.trim().replaceAll('\n', ' ').trim();
    if (title.length >= 2 && title.startsWith('"') && title.endsWith('"')) {
      title = title.substring(1, title.length - 1).trim();
    }
    if (title.isEmpty) return null;
    return title.length > 60 ? '${title.substring(0, 60)}…' : title;
  }

  Future<void> _persistProviders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _providersKey,
      jsonEncode(providers.value.map((p) => p.toJson()).toList()),
    );
    await prefs.setString(_activeKey, activeProviderId.value ?? '');
  }

  Future<void> _persistSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = [
      for (final session in sessions.value)
        session.messages.length > _maxPersistedMessages
            ? session.copyWith(
                messages: session.messages.sublist(
                  session.messages.length - _maxPersistedMessages,
                ),
              )
            : session,
    ];
    await prefs.setString(
      _sessionsKey,
      jsonEncode({
        'sessions': trimmed.map((s) => s.toJson()).toList(),
        'activeSessionId': activeSessionId.value ?? '',
      }),
    );
  }

  /// Stable-enough id: timestamp prefix + monotonic counter.
  static String generateId() {
    _idCounter++;
    return '${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }
}
