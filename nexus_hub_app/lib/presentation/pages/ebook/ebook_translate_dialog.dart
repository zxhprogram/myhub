import 'package:dio/dio.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/ai_provider_config.dart';
import '../../../data/repositories/ai_chat_repository.dart';
import '../../../data/services/ebook/ebook_translate_service.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../states/ai_chat_state.dart';

/// 翻译弹窗 — 展示选中文字并把 AI 的解释/翻译流式渲染出来。
///
/// Provider 与 API Key 与 AI Chat 子应用共用（[AiChatState]）；此处提供
/// 切换 provider/model 的下拉框，未配置时内嵌一个精简配置表单。
class EbookTranslateDialog extends StatefulWidget {
  const EbookTranslateDialog({
    super.key,
    required this.text,
    this.autoTranslate = false,
  });

  final String text;

  /// When true, translation starts as soon as the provider is resolved —
  /// used by the readers' auto-translate-on-selection flow.
  final bool autoTranslate;

  /// Opens the dialog over the reader page.
  static void show(
    BuildContext context, {
    required String text,
    bool autoTranslate = false,
  }) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) =>
            EbookTranslateDialog(text: text, autoTranslate: autoTranslate),
      ),
    );
  }

  @override
  State<EbookTranslateDialog> createState() => _EbookTranslateDialogState();
}

class _EbookTranslateDialogState extends State<EbookTranslateDialog> {
  static const _prefProviderKey = 'nexus_ebook_translate_provider_v1';
  static const _prefModelKey = 'nexus_ebook_translate_model_v1';

  final _aiState = AiChatState.instance;
  final _service = EbookTranslateService();
  final _outputScroll = ScrollController();

  CancelToken? _cancelToken;
  String _output = '';
  bool _streaming = false;
  String? _error;

  String? _providerId;
  String? _model;

  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _resolveDefaultProvider();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _outputScroll.dispose();
    super.dispose();
  }

  /// Restores the last-used provider/model (persisted per reader), falling
  /// back to the active or first ready provider; optionally starts the
  /// translation right away for the auto-translate-on-selection flow.
  Future<void> _resolveDefaultProvider() async {
    await _aiState.init();
    if (!mounted) return;
    final providers = _aiState.providers.value;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedId = prefs.getString(_prefProviderKey);
    var provider = savedId == null
        ? null
        : providers.where((p) => p.id == savedId).firstOrNull;
    provider ??= _aiState.activeProvider;
    if (!(provider?.isReady ?? false)) {
      provider = providers.where((p) => p.isReady).firstOrNull;
    }
    setState(() {
      _providerId = provider?.id;
      _model = prefs.getString(_prefModelKey) ?? provider?.selectedModel;
      _configured = provider != null;
    });
    if (widget.autoTranslate) {
      await _translate();
    }
  }

  /// Persists the translation provider/model choice so the next dialog
  /// opens with the same configuration.
  Future<void> _persistSelection(String? providerId, String? model) async {
    final prefs = await SharedPreferences.getInstance();
    if (providerId == null || providerId.isEmpty) {
      await prefs.remove(_prefProviderKey);
    } else {
      await prefs.setString(_prefProviderKey, providerId);
    }
    if (model == null || model.isEmpty) {
      await prefs.remove(_prefModelKey);
    } else {
      await prefs.setString(_prefModelKey, model);
    }
  }

  AiProviderConfig? get _provider {
    final providers = _aiState.providers.value;
    return providers.where((p) => p.id == _providerId).firstOrNull ??
        providers.where((p) => p.isReady).firstOrNull;
  }

  /// Resolves the model for [_provider], recovering when the stored model
  /// no longer exists (e.g. the provider was edited in the settings dialog).
  String? get _effectiveModel {
    final provider = _provider;
    if (provider == null) return null;
    if (provider.models.contains(_model)) return _model;
    return provider.selectedModel ?? provider.models.firstOrNull;
  }

  Future<void> _translate() async {
    if (_streaming) return;
    final provider = _provider;
    final model = _effectiveModel;
    if (provider == null || (model ?? '').isEmpty) {
      setState(() => _error = '请先点击齿轮图标配置 AI 服务和模型。');
      return;
    }

    debugPrint(
      '[EbookTranslate] translate tapped: provider=${provider.name} '
      'model=$model',
    );
    setState(() {
      _output = '';
      _error = null;
      _streaming = true;
    });
    final token = _cancelToken = CancelToken();
    try {
      await for (final chunk in _service.stream(
        provider: provider,
        model: model!,
        text: widget.text,
      )) {
        if (token.isCancelled) break;
        setState(() => _output += chunk);
        _scrollOutputToBottom();
      }
      if (!token.isCancelled && _output.isEmpty) {
        setState(() => _error = 'AI 未返回任何内容，请检查所选模型是否可用。');
      }
    } on AiChatCancelledException {
      // 用户主动停止，不算错误。
    } on AiChatException catch (e) {
      debugPrint('[EbookTranslate] failed: ${e.message}');
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      debugPrint('[EbookTranslate] failed: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _streaming = false);
    }
  }

  void _scrollOutputToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_outputScroll.hasClients) return;
      _outputScroll.jumpTo(_outputScroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = _aiState.providers.watch(context);

    return AlertDialog(
      title: Text('AI 翻译', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 680,
        height: 540,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 选中的原文预览。
            OutlinedContainer(
              padding: const EdgeInsets.all(NexusSpacing.sm),
              child: Text(
                widget.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.bodyMd.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            if (_configured && providers.any((p) => p.isReady))
              _buildConfiguredBody(context)
            else
              Expanded(child: _ProviderForm(onSaved: _onProviderSaved)),
          ],
        ),
      ),
      actions: [
        Button.ghost(
          onPressed: () => closeOverlay(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  void _onProviderSaved(AiProviderConfig provider) {
    setState(() {
      _providerId = provider.id;
      _model = provider.selectedModel;
      _configured = true;
    });
    _persistSelection(provider.id, provider.selectedModel);
  }

  /// provider/model 选择 + 流式输出区。
  Widget _buildConfiguredBody(BuildContext context) {
    final theme = Theme.of(context);
    final provider = _provider;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildProviderSelect(context),
              const SizedBox(width: NexusSpacing.sm),
              if (provider != null) _buildModelSelect(context, provider),
              IconButton.ghost(
                icon: const Icon(LucideIcons.settings, size: 16),
                onPressed: () => EbookTranslateConfigDialog.show(context),
              ),
              const Spacer(),
              if (_streaming)
                Button.outline(
                  leading: const Icon(LucideIcons.square, size: 14),
                  onPressed: () => _cancelToken?.cancel(),
                  child: const Text('停止'),
                )
              else
                Button.primary(
                  leading: const Icon(LucideIcons.languages, size: 16),
                  onPressed: () => _translate(),
                  child: const Text('翻译'),
                ),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          Expanded(
            child: OutlinedContainer(
              padding: const EdgeInsets.all(NexusSpacing.md),
              child: _error != null
                  ? SingleChildScrollView(
                      child: Text(
                        _error!,
                        style: NexusTypography.bodyMd.copyWith(
                          color: theme.colorScheme.destructive,
                        ),
                      ),
                    )
                  : _output.isEmpty
                  ? Center(
                      child: Text(
                        _streaming ? '正在请求 AI…' : '点击“翻译”查看结果',
                        style: NexusTypography.bodyMd.copyWith(
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _outputScroll,
                      child: GptMarkdown(_output),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSelect(BuildContext context) {
    final providers = _aiState.providers.value;
    return Select<String>(
      value: _providerId,
      constraints: const BoxConstraints(maxWidth: 180),
      popup: SelectPopup(
        items: SelectItemList(
          children: [
            for (final provider in providers)
              SelectItemButton(
                value: provider.id,
                child: Text(provider.name).small(),
              ),
          ],
        ),
      ).call,
      itemBuilder: (context, value) {
        final provider = providers.where((p) => p.id == value).firstOrNull;
        return Text(provider?.name ?? '未选择').small();
      },
      onChanged: (id) {
        final provider = providers.where((p) => p.id == id).firstOrNull;
        setState(() {
          _providerId = id;
          _model = provider?.selectedModel;
        });
        _persistSelection(id, provider?.selectedModel);
      },
    );
  }

  Widget _buildModelSelect(BuildContext context, AiProviderConfig provider) {
    final models = provider.models;
    return Select<String>(
      value: _effectiveModel,
      constraints: const BoxConstraints(maxWidth: 220),
      popup: SelectPopup.builder(
        enableSearch: true,
        searchPlaceholder: const Text('搜索模型…'),
        builder: (context, searchQuery) => SelectItemList(
          children: [
            for (final model in models)
              if (searchQuery == null ||
                  model.toLowerCase().contains(searchQuery.toLowerCase()))
                SelectItemButton(value: model, child: Text(model).small()),
          ],
        ),
      ).call,
      itemBuilder: (context, value) =>
          Text(value, overflow: TextOverflow.ellipsis).small(),
      onChanged: (model) {
        setState(() => _model = model);
        _persistSelection(_providerId, model);
      },
    );
  }
}

/// AI 翻译设置弹窗 — 查看已配置的 provider、新增或删除。
///
/// 这是阅读器工具栏设置按钮的入口；provider 与 AI Chat 子应用共用。
class EbookTranslateConfigDialog extends StatefulWidget {
  const EbookTranslateConfigDialog({super.key});

  /// Opens the settings dialog over the current context.
  static void show(BuildContext context) {
    showOverlay(
      context,
      DialogConfiguration(
        barrierColor: const Color.fromRGBO(0, 0, 0, 0.54),
        builder: (context) => const EbookTranslateConfigDialog(),
      ),
    );
  }

  @override
  State<EbookTranslateConfigDialog> createState() =>
      _EbookTranslateConfigDialogState();
}

class _EbookTranslateConfigDialogState
    extends State<EbookTranslateConfigDialog> {
  final _aiState = AiChatState.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providers = _aiState.providers.watch(context);

    return AlertDialog(
      title: Text('AI 翻译设置', style: NexusTypography.headlineSm),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (providers.isEmpty)
              Text(
                '尚未配置 AI 服务，请在下方填写（与 AI Chat 共用）：',
                style: NexusTypography.bodyMd.copyWith(
                  color: theme.colorScheme.mutedForeground,
                ),
              )
            else ...[
              Text('已配置的服务').small().semiBold(),
              const SizedBox(height: NexusSpacing.xs),
              for (final provider in providers) ...[
                _buildProviderTile(context, provider),
                const SizedBox(height: NexusSpacing.xs),
              ],
              const SizedBox(height: NexusSpacing.sm),
              Divider(height: 1, color: theme.colorScheme.border),
              const SizedBox(height: NexusSpacing.sm),
              Text('新增服务').small().semiBold(),
              const SizedBox(height: NexusSpacing.xs),
            ],
            Expanded(child: _ProviderForm(onSaved: (_) {})),
          ],
        ),
      ),
      actions: [
        Button.ghost(
          onPressed: () => closeOverlay(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildProviderTile(BuildContext context, AiProviderConfig provider) {
    final theme = Theme.of(context);
    return OutlinedContainer(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider.name).small().semiBold(),
                const SizedBox(height: 2),
                Text(
                  '${provider.baseUrl}  ·  ${provider.selectedModel ?? '未选模型'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelSm.copyWith(
                    color: theme.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          IconButton.ghost(
            icon: const Icon(LucideIcons.trash2, size: 14),
            onPressed: () => _aiState.deleteProvider(provider.id),
          ),
        ],
      ),
    );
  }
}

/// 精简 provider 配置表单（与 AI Chat 共用存储），保存后立即可翻译。
class _ProviderForm extends StatefulWidget {
  const _ProviderForm({required this.onSaved});

  final ValueChanged<AiProviderConfig> onSaved;

  @override
  State<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<_ProviderForm> {
  final _repository = AiChatRepository();
  final _name = TextEditingController();
  final _baseUrl = TextEditingController();
  final _apiKey = TextEditingController();
  final _model = TextEditingController();

  bool _fetching = false;
  String? _error;
  String? _baseUrlError;
  String? _modelError;

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
    _model.dispose();
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
      final temp = AiProviderConfig(
        id: 'draft',
        name: _name.text.trim(),
        baseUrl: _baseUrl.text.trim(),
        apiKey: _apiKey.text.trim(),
      );
      final fetched = await _repository.fetchModels(temp);
      if (!mounted) return;
      if (fetched.isEmpty) {
        setState(() => _error = '该服务未返回模型列表，请手动填写模型 ID。');
      } else if (_model.text.trim().isEmpty) {
        setState(() => _model.text = fetched.first);
      }
    } on AiChatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    final baseUrl = _baseUrl.text.trim();
    final model = _model.text.trim();
    setState(() {
      _baseUrlError = baseUrl.isEmpty ? '必填' : null;
      _modelError = model.isEmpty ? '必填：手动填写或点击“获取模型”' : null;
    });
    if (baseUrl.isEmpty || model.isEmpty) return;

    final config = AiProviderConfig(
      id: AiChatState.generateId(),
      name: _name.text.trim().isEmpty ? '翻译服务' : _name.text.trim(),
      baseUrl: baseUrl,
      apiKey: _apiKey.text.trim(),
      models: [model],
      selectedModel: model,
    );
    await AiChatState.instance.addProvider(config);
    widget.onSaved(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '还没有可用的 AI 服务。填写 OpenAI 兼容的 API 地址和密钥（与 AI Chat 共用）：',
            style: NexusTypography.bodyMd.copyWith(
              color: theme.colorScheme.mutedForeground,
            ),
          ),
          const SizedBox(height: NexusSpacing.sm),
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
          const SizedBox(height: NexusSpacing.sm),
          TextField(
            controller: _name,
            placeholder: const Text('名称（如 My DeepSeek）'),
          ),
          const SizedBox(height: NexusSpacing.sm),
          TextField(
            controller: _baseUrl,
            placeholder: const Text('API 地址，如 https://api.openai.com/v1'),
          ),
          if (_baseUrlError != null)
            Text(
              _baseUrlError!,
              style: NexusTypography.labelSm.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          const SizedBox(height: NexusSpacing.sm),
          TextField(
            controller: _apiKey,
            placeholder: const Text('API Key（本地服务可留空）'),
            obscureText: true,
          ),
          const SizedBox(height: NexusSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _model,
                  placeholder: const Text('模型 ID，如 gpt-4o-mini'),
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              Button.outline(
                leading: _fetching
                    ? const CircularProgressIndicator(size: 14)
                    : const Icon(LucideIcons.cloudDownload, size: 16),
                onPressed: _fetching ? null : _fetchModels,
                child: const Text('获取模型'),
              ),
            ],
          ),
          if (_modelError != null)
            Text(
              _modelError!,
              style: NexusTypography.labelSm.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: NexusSpacing.sm),
            Text(
              _error!,
              style: NexusTypography.bodyMd.copyWith(
                color: theme.colorScheme.destructive,
              ),
            ),
          ],
          const SizedBox(height: NexusSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: Button.primary(
              leading: const Icon(LucideIcons.check, size: 16),
              onPressed: _save,
              child: const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
