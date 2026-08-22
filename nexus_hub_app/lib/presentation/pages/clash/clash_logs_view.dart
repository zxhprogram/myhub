import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../../data/models/clash_models.dart';
import '../../states/clash_state.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_toast.dart';

/// Log screen, ported from FlClash's `LogsView`: level filter, text search,
/// auto-scroll-to-end toggle, clear and export to file. The filter is ported
/// from FlClash's `LogsStateExt.list`.
class ClashLogsView extends StatefulWidget {
  const ClashLogsView({super.key});

  @override
  State<ClashLogsView> createState() => _ClashLogsViewState();
}

class _ClashLogsViewState extends State<ClashLogsView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  ClashLogLevel? _levelFilter;
  bool _autoScroll = true;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ClashLog> _filtered(List<ClashLog> logs) {
    final query = _searchController.text.toLowerCase().trim();
    return logs.where((log) {
      if (_levelFilter != null && log.level != _levelFilter) return false;
      if (query.isEmpty) return true;
      return log.payload.toLowerCase().contains(query) ||
          log.level.value.contains(query);
    }).toList();
  }

  /// Exports the filtered log lines to a file (FlClash's `Logs.exportLogs`).
  Future<void> _exportLogs(BuildContext context) async {
    final logs = _filtered(ClashState.instance.logs.value);
    if (logs.isEmpty) {
      nexusToast(context, '没有可导出的日志', isError: true);
      return;
    }
    final stamp = DateTime.now();
    final fileName =
        'clash-logs-${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}-${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}.txt';
    const typeGroup = XTypeGroup(label: '文本文件', extensions: ['txt']);
    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: [typeGroup],
    );
    if (location == null) return;
    final text = [
      for (final log in logs)
        '[${log.level.value}] ${log.time.toIso8601String()} ${log.payload}',
    ].join('\n');
    try {
      await File(location.path).writeAsString(text);
      if (context.mounted) {
        nexusToast(context, '日志已导出');
      }
    } catch (error) {
      if (context.mounted) {
        nexusToast(context, '导出失败：$error', isError: true);
      }
    }
  }

  void _scrollToEnd() {
    if (!_autoScroll || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Watch((_) {
      final logs = _filtered(ClashState.instance.logs.value);
      _scrollToEnd();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('日志', style: NexusTypography.headlineSm),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                '${logs.length} 条',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
              const Spacer(),
              for (final level in [
                null,
                ...ClashLogLevel.values,
              ]) ...[
                _LevelChip(
                  label: level?.value ?? '全部',
                  selected: _levelFilter == level,
                  onTap: () => setState(() => _levelFilter = level),
                ),
                const SizedBox(width: NexusSpacing.xs),
              ],
              const SizedBox(width: NexusSpacing.sm),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _searchController,
                  hintText: '搜索日志…',
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: _autoScroll ? '自动滚动：开' : '自动滚动：关',
                icon: LucideIcons.arrowDown,
                variant: _autoScroll
                    ? NexusButtonVariant.tonal
                    : NexusButtonVariant.outlined,
                onPressed: () => setState(() => _autoScroll = !_autoScroll),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: '导出',
                icon: LucideIcons.fileDown,
                variant: NexusButtonVariant.outlined,
                onPressed: () => _exportLogs(context),
              ),
              const SizedBox(width: NexusSpacing.sm),
              NexusButton(
                label: '清空',
                icon: LucideIcons.trash2,
                variant: NexusButtonVariant.outlined,
                onPressed: () => ClashState.instance.clearLogs(),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.border),
              ),
              child: logs.isEmpty
                  ? Center(
                      child: Text(
                        ClashState.instance.status.value ==
                                ClashStatus.connected
                            ? '等待日志…'
                            : '连接核心后显示实时日志。',
                        style: NexusTypography.bodyMd.copyWith(
                          color: colorScheme.mutedForeground,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        vertical: NexusSpacing.sm,
                      ),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        return _LogLine(log: logs[index]);
                      },
                    ),
            ),
          ),
        ],
      );
    });
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withValues(alpha: 0.5)
                  : colorScheme.border,
            ),
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }
}

/// One log line with the level color coding FlClash uses.
class _LogLine extends StatelessWidget {
  const _LogLine({required this.log});

  final ClashLog log;

  static Color _levelColor(ClashLogLevel level) {
    return switch (level) {
      ClashLogLevel.debug => const Color(0xFF6B7280),
      ClashLogLevel.info => const Color(0xFF0EA5E9),
      ClashLogLevel.warning => const Color(0xFFF59E0B),
      ClashLogLevel.error => const Color(0xFFEF4444),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final levelColor = _levelColor(log.level);
    final clock =
        '${log.time.hour.toString().padLeft(2, '0')}:'
        '${log.time.minute.toString().padLeft(2, '0')}:'
        '${log.time.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.md,
        vertical: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              log.level.value.toUpperCase(),
              style: NexusTypography.labelSm.copyWith(color: levelColor),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              clock,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              log.payload,
              style: NexusTypography.bodyMd.copyWith(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
