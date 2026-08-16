import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/java_decompiler_service.dart';
import '../components/nexus_empty_state.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Java 反编译器 — 打开 .class 文件并显示反编译后的 Java 源码。
///
/// 解析与反编译由 [JavaDecompilerService]（基于 ../../java-decompiler 包）
/// 在后台 isolate 中完成，结果以带行号的可选择文本展示。
class JavaDecompilerPage extends StatefulWidget {
  const JavaDecompilerPage({super.key});

  @override
  State<JavaDecompilerPage> createState() => _JavaDecompilerPageState();
}

class _JavaDecompilerPageState extends State<JavaDecompilerPage> {
  final JavaDecompilerService _service = JavaDecompilerService();

  static const _typeGroup = XTypeGroup(
    label: 'Java Class 文件',
    extensions: ['class'],
  );

  JavaDecompilerResult? _result;
  bool _loading = false;
  String? _error;

  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openFile() async {
    final file = await openFile(acceptedTypeGroups: [_typeGroup]);
    if (file == null) return;
    await _decompile(file.path);
  }

  Future<void> _decompile(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.decompileFile(path);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法反编译该文件，请确认它是有效的 Java class 文件。\n\n$e';
      });
    }
  }

  Future<void> _copySource() async {
    final source = _result?.source;
    if (source == null) return;
    await Clipboard.setData(ClipboardData(text: source));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('已复制反编译源码到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          _buildToolbar(context),
          const Divider(height: 1),
          Expanded(child: _buildBody(context)),
          if (_result != null) ...[
            const Divider(height: 1),
            _buildStatusBar(context),
          ],
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: NexusSpacing.sm,
      ),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _openFile,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open, size: 18),
            label: const Text('打开 Class 文件'),
          ),
          const SizedBox(width: NexusSpacing.md),
          if (_result != null) ...[
            Icon(Icons.description_outlined,
                size: 16, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Text(
                _fileLabel,
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: '复制源码',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: _copySource,
            ),
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => setState(() {
                _result = null;
                _error = null;
              }),
            ),
          ] else ...[
            Expanded(child: Container()),
          ],
        ],
      ),
    );
  }

  String get _fileLabel {
    final result = _result;
    if (result == null) return '';
    return '${result.className}  ·  ${File(result.filePath).uri.pathSegments.last}';
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: NexusSpacing.md),
            Text(
              '反编译失败',
              style: NexusTypography.headlineSm.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: NexusSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                _error!,
                style: NexusTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            FilledButton.icon(
              onPressed: _openFile,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('重新选择文件'),
            ),
          ],
        ),
      );
    }
    final result = _result;
    if (result == null) {
      return NexusEmptyState(
        icon: Icons.coffee,
        title: 'Java 反编译器',
        subtitle: '打开一个 .class 文件，查看反编译后的 Java 源码',
        action: FilledButton.icon(
          onPressed: _openFile,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text('打开 Class 文件'),
        ),
      );
    }
    return _CodeView(
      source: result.source,
      scrollController: _scrollController,
    );
  }

  Widget _buildStatusBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final result = _result!;
    final lines = '\n'.allMatches(result.source).length + 1;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: 6,
      ),
      color: colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              result.filePath,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          Text(
            'class v${result.majorVersion}.${result.minorVersion}'
            ' (Java ${result.javaVersion})',
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          Text(
            '$lines 行',
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// 深色代码视图：行号栏 + 等宽可选择源码，纵横双向滚动。
class _CodeView extends StatelessWidget {
  const _CodeView({required this.source, required this.scrollController});

  final String source;
  final ScrollController scrollController;

  static const _codeStyle = TextStyle(
    fontFamily: 'Consolas',
    fontSize: 13,
    height: 1.5,
    color: Color(0xFFD4D4D4),
  );

  @override
  Widget build(BuildContext context) {
    final lines = source.split('\n');
    final gutterWidth = (lines.length.toString().length * 9.0) + 24;
    return Container(
      color: const Color(0xFF1A1A1E),
      child: Scrollbar(
        controller: scrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: scrollController,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: gutterWidth,
                  decoration: const BoxDecoration(
                    border: Border(
                      right: BorderSide(color: Color(0x33FFFFFF)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 1; i <= lines.length; i++)
                        Text(
                          '$i',
                          style: _codeStyle.copyWith(
                            color: const Color(0x66FFFFFF),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 0),
                  child: SelectableText(
                    source,
                    style: _codeStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
