import 'package:flutter/material.dart';

import '../../../data/models/video_site_config.dart';
import '../../../data/services/video_site_config_storage.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_input.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Opens the data source manager of the video sub-app.
///
/// All mutations (create, edit, delete, activate) are persisted to
/// VideoSiteConfigStorage as they happen; the returned value is the active
/// source at close time, so callers can compare it with the config they
/// are currently using and reload when it changed.
Future<VideoSiteConfig> showVideoSourceManagerDialog(BuildContext context) {
  return showDialog<VideoSiteConfig>(
    context: context,
    builder: (_) => const _VideoSourceManagerDialog(),
  ).then(
    (value) => value ?? VideoSiteConfigStorage.current,
  );
}

class _VideoSourceManagerDialog extends StatefulWidget {
  const _VideoSourceManagerDialog();

  @override
  State<_VideoSourceManagerDialog> createState() =>
      _VideoSourceManagerDialogState();
}

class _VideoSourceManagerDialogState extends State<_VideoSourceManagerDialog> {
  List<VideoSiteConfig> _sources = VideoSiteConfigStorage.sources;
  String _activeId = VideoSiteConfigStorage.current.id;

  void _refresh() {
    setState(() {
      _sources = VideoSiteConfigStorage.sources;
      _activeId = VideoSiteConfigStorage.current.id;
    });
  }

  Future<void> _activate(VideoSiteConfig source) async {
    if (source.id == _activeId) return;
    await VideoSiteConfigStorage.setActive(source.id);
    _refresh();
  }

  Future<void> _create() async {
    final created = await _showEditDialog();
    if (created == null) return;
    await VideoSiteConfigStorage.upsert(created, activate: true);
    _refresh();
  }

  Future<void> _edit(VideoSiteConfig source) async {
    final updated = await _showEditDialog(initial: source);
    if (updated == null) return;
    await VideoSiteConfigStorage.upsert(updated);
    _refresh();
  }

  Future<void> _delete(VideoSiteConfig source) async {
    // The last source cannot be deleted — there would be nothing to
    // browse through (VideoSiteConfigStorage.remove guards as well).
    await VideoSiteConfigStorage.remove(source.id);
    _refresh();
  }

  Future<VideoSiteConfig?> _showEditDialog({VideoSiteConfig? initial}) {
    return showDialog<VideoSiteConfig>(
      context: context,
      builder: (_) => _VideoSourceEditDialog(initial: initial),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Row(
        children: [
          Icon(Icons.dns_outlined, size: 24, color: colorScheme.secondary),
          const SizedBox(width: NexusSpacing.sm),
          Text('视频数据源', style: NexusTypography.headlineSm),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '点选任一数据源即可切换浏览与播放；每个数据源可单独配置协议与域名。',
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final source in _sources)
                      _SourceRow(
                        source: source,
                        active: source.id == _activeId,
                        deletable: _sources.length > 1,
                        onSelect: () => _activate(source),
                        onEdit: () => _edit(source),
                        onDelete: () => _delete(source),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            NexusButton(
              label: '新建数据源',
              variant: NexusButtonVariant.tonal,
              icon: Icons.add,
              onPressed: _create,
            ),
          ],
        ),
      ),
      actions: [
        NexusButton(
          label: '完成',
          onPressed: () =>
              Navigator.of(context).pop(VideoSiteConfigStorage.current),
        ),
      ],
    );
  }
}

/// One saved source in the manager list: activation radio on the left,
/// name and protocol · domain summary, edit and delete on the right.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.active,
    required this.deletable,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final VideoSiteConfig source;
  final bool active;
  final bool deletable;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
      child: InkWell(
        borderRadius: NexusRadii.mdRadius,
        onTap: onSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: NexusSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: active
                ? colorScheme.secondaryContainer.withValues(alpha: 0.45)
                : colorScheme.surfaceContainerLow,
            border: Border.all(
              color: active
                  ? colorScheme.secondary.withValues(alpha: 0.6)
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: NexusRadii.mdRadius,
          ),
          child: Row(
            children: [
              Icon(
                active ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: active
                    ? colorScheme.secondary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: NexusSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NexusTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${source.protocol.label} · ${source.domain}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NexusTypography.labelSm.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: '编辑',
                visualDensity: VisualDensity.compact,
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: deletable ? '删除' : '最后一个数据源不可删除',
                visualDensity: VisualDensity.compact,
                onPressed: deletable ? onDelete : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Create/edit form of one data source.
///
/// Pass [initial] to edit an existing source; omit it to create a new one
/// (domains prefill with the protocol defaults). Returns the completed
/// configuration, or `null` if the user cancelled; persisting it is up to
/// the caller.
class _VideoSourceEditDialog extends StatefulWidget {
  const _VideoSourceEditDialog({this.initial});

  final VideoSiteConfig? initial;

  @override
  State<_VideoSourceEditDialog> createState() => _VideoSourceEditDialogState();
}

class _VideoSourceEditDialogState extends State<_VideoSourceEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late VideoProtocol _protocol =
      widget.initial?.protocol ?? VideoProtocol.netflixgc;
  late final _nameController = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final _domainController = TextEditingController(
    text: widget.initial?.domain ?? VideoSiteConfig.defaultDomain,
  );
  late final _parseDomainController = TextEditingController(
    text: widget.initial?.parseDomain ?? VideoSiteConfig.defaultParseDomain,
  );

  @override
  void dispose() {
    _nameController.dispose();
    _domainController.dispose();
    _parseDomainController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) return '必填项';
    return null;
  }

  String? _validateDomain(String? value) {
    if (!VideoSiteConfig.isValidDomain(value ?? '')) {
      return '仅支持域名（可带端口），例如 www.example.com';
    }
    return null;
  }

  void _reset() {
    setState(() {
      _protocol = VideoProtocol.netflixgc;
      _domainController.text = VideoSiteConfig.defaultDomain;
      _parseDomainController.text = VideoSiteConfig.defaultParseDomain;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      VideoSiteConfig(
        id: widget.initial?.id ?? VideoSiteConfig.generateId(),
        name: _nameController.text.trim(),
        protocol: _protocol,
        domain: VideoSiteConfig.normalizeDomain(_domainController.text),
        parseDomain: VideoSiteConfig.normalizeDomain(
          _parseDomainController.text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.initial != null;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_outlined : Icons.add_circle_outline,
            size: 24,
            color: colorScheme.secondary,
          ),
          const SizedBox(width: NexusSpacing.sm),
          Text(
            isEditing ? '编辑数据源' : '新建数据源',
            style: NexusTypography.headlineSm,
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NexusInput(
                controller: _nameController,
                labelText: '名称',
                hintText: '例如：NetflixGC 主站',
                prefixIcon: const Icon(Icons.label_outline, size: 18),
                validator: _validateName,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                autofocus: !isEditing,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NexusSpacing.md),
              Text(
                '解析协议',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: NexusSpacing.xs),
              DropdownButtonFormField<VideoProtocol>(
                initialValue: _protocol,
                items: [
                  for (final protocol in VideoProtocol.values)
                    DropdownMenuItem(
                      value: protocol,
                      child: Text(
                        protocol.label,
                        style: NexusTypography.bodyMd,
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _protocol = value ?? _protocol),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: NexusRadii.mdRadius,
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: NexusRadii.mdRadius,
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'NetflixGC 协议：按现有规则解析（列表/搜索 JSON 接口、详情页 '
                'HTML、播放页双重加密与云端解析）。站点域名变更时无需改动协议，'
                '只需更新下方域名。',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: NexusSpacing.md),
              NexusInput(
                controller: _domainController,
                labelText: '站点域名',
                hintText: VideoSiteConfig.defaultDomain,
                prefixIcon: const Icon(Icons.language, size: 18),
                validator: _validateDomain,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NexusSpacing.md),
              NexusInput(
                controller: _parseDomainController,
                labelText: '解析接口域名',
                hintText: VideoSiteConfig.defaultParseDomain,
                prefixIcon: const Icon(Icons.play_circle_outline, size: 18),
                validator: _validateDomain,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                '播放源云端解析接口所在的域名，与站点域名通常不同。',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        NexusButton(
          label: '恢复默认域名',
          variant: NexusButtonVariant.text,
          icon: Icons.restore,
          onPressed: _reset,
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NexusButton(
              label: '取消',
              variant: NexusButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: NexusSpacing.sm),
            NexusButton(label: '保存', icon: Icons.check, onPressed: _submit),
          ],
        ),
      ],
    );
  }
}
