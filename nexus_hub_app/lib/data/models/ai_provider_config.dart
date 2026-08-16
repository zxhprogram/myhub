import 'package:flutter/foundation.dart';

/// Configuration for an OpenAI-compatible chat provider (OpenAI, DeepSeek,
/// Kimi, Ollama's `/v1` endpoint, LM Studio, ...).
///
/// The API key is stored alongside the other fields in plain text (the same
/// trade-off as [SshProfile]); switch to a secure storage package if stronger
/// protection is ever required.
@immutable
class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.systemPrompt = '',
    this.models = const [],
    this.selectedModel,
  });

  final String id;

  /// Display name shown in the provider picker.
  final String name;

  /// API root without a trailing slash, e.g. `https://api.openai.com/v1`.
  final String baseUrl;

  /// Bearer token; empty for local servers that need none.
  final String apiKey;

  /// Optional system prompt sent as the first message of every request.
  final String systemPrompt;

  /// Models known for this provider, either fetched from the API or added
  /// manually.
  final List<String> models;

  /// Model used for new completions; must be one of [models] (or null before
  /// the user picked one).
  final String? selectedModel;

  /// `name · baseUrl` summary shown in the provider list.
  String get endpoint => '$name · $baseUrl';

  bool get isReady => baseUrl.isNotEmpty && (selectedModel ?? '').isNotEmpty;

  AiProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? systemPrompt,
    List<String>? models,
    String? selectedModel,
  }) {
    return AiProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      models: models ?? this.models,
      selectedModel: selectedModel ?? this.selectedModel,
    );
  }

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    return AiProviderConfig(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      models: (json['models'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(growable: false),
      selectedModel: json['selectedModel'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'systemPrompt': systemPrompt,
        'models': models,
        'selectedModel': selectedModel,
      };
}
