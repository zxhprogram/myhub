import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/fx678_news_model.dart';
import '../../../data/services/fx678_news_service.dart';
import '../../../theme/colors.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// 7x24 flash-news pane backed by the fx678 live feed (汇通财经快讯).
class Fx678NewsPane extends StatefulWidget {
  const Fx678NewsPane({super.key});

  @override
  State<Fx678NewsPane> createState() => _Fx678NewsPaneState();
}

class _Fx678NewsPaneState extends State<Fx678NewsPane> {
  final _service = Fx678NewsService();

  List<Fx678NewsItem> _items = const [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _onlyImportant = false;

  /// Monotonic request counter; completions of superseded loads never
  /// update the state.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => _guard(_service.fetchNews());

  Future<void> _refresh() => _guard(_service.refreshNews());

  Future<void> _guard(Future<List<Fx678NewsItem>> future) async {
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      final items = await future;
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _openInBrowser(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visible = _onlyImportant
        ? _items.where((i) => i.isImportant).toList()
        : _items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('汇通财经 · 7x24 快讯', style: NexusTypography.headlineSm),
            const SizedBox(width: NexusSpacing.sm),
            if (!_isLoading && !_hasError)
              Text(
                '${visible.length} 条',
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            const Spacer(),
            _filterChip(
              context,
              label: '全部',
              selected: !_onlyImportant,
              onTap: () => setState(() => _onlyImportant = false),
            ),
            const SizedBox(width: NexusSpacing.sm),
            _filterChip(
              context,
              label: '重要',
              selected: _onlyImportant,
              onTap: () => setState(() => _onlyImportant = true),
            ),
            const SizedBox(width: NexusSpacing.md),
            NexusButton(
              label: '刷新',
              icon: Icons.refresh,
              variant: NexusButtonVariant.outlined,
              isLoading: _isLoading,
              onPressed: _refresh,
            ),
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        Expanded(
          child: _buildBody(context, visible),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, List<Fx678NewsItem> items) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    if (_hasError) {
      return NexusEmptyState(
        icon: Icons.cloud_off,
        title: '快讯加载失败',
        subtitle: '请检查网络后重试',
        action: NexusButton(
          label: '重试',
          icon: Icons.refresh,
          variant: NexusButtonVariant.outlined,
          onPressed: _load,
        ),
      );
    }

    if (items.isEmpty) {
      return const NexusEmptyState(
        icon: Icons.flash_on,
        title: '暂无快讯',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: NexusSpacing.lg),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: NexusSpacing.xs),
        itemBuilder: (context, index) {
          final item = items[index];
          final showDayHeader = index == 0 ||
              item.publishTime?.day != items[index - 1].publishTime?.day ||
              item.publishTime?.month != items[index - 1].publishTime?.month;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showDayHeader) ...[
                _DayHeader(dateTime: item.publishTime),
                const SizedBox(height: NexusSpacing.sm),
              ],
              _NewsTile(
                item: item,
                onOpen: () => _openInBrowser(item.url),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colorScheme.primary : Colors.transparent,
      borderRadius: NexusRadii.fullRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: NexusRadii.fullRadius,
        hoverColor: selected
            ? null
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            borderRadius: NexusRadii.fullRadius,
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: selected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Date divider shown whenever the feed crosses to another day.
class _DayHeader extends StatelessWidget {
  const _DayHeader({this.dateTime});

  final DateTime? dateTime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    String label;
    final date = dateTime;
    if (date == null) {
      label = '最新';
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final thatDay = DateTime(date.year, date.month, date.day);
      final diff = today.difference(thatDay).inDays;
      final mmdd =
          '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      label = switch (diff) {
        0 => '今天 $mmdd',
        1 => '昨天 $mmdd',
        2 => '前天 $mmdd',
        _ => mmdd,
      };
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: NexusSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: NexusRadii.fullRadius,
          ),
          child: Text(
            label,
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: NexusSpacing.sm),
        Expanded(
          child: Divider(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }
}

/// A single flash-news entry: time on the left, headline + body on the right.
class _NewsTile extends StatefulWidget {
  const _NewsTile({
    required this.item,
    required this.onOpen,
  });

  final Fx678NewsItem item;
  final VoidCallback onOpen;

  @override
  State<_NewsTile> createState() => _NewsTileState();
}

class _NewsTileState extends State<_NewsTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = widget.item;
    final accent = item.isImportant ? NexusColors.stockDown : colorScheme.primary;
    final longBody = item.content.length > 140;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Padding(
            padding: const EdgeInsets.only(top: NexusSpacing.sm + 2),
            child: Text(
              item.timeText.length >= 5
                  ? item.timeText.substring(0, 5)
                  : item.timeText,
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(NexusSpacing.md),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: NexusRadii.lgRadius,
              border: Border(
                left: BorderSide(color: accent, width: 3),
                top: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                right: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: NexusTypography.labelMd.copyWith(
                          fontWeight: FontWeight.w700,
                          color: item.isImportant
                              ? NexusColors.stockDown
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (item.isImportant) ...[
                      const SizedBox(width: NexusSpacing.sm),
                      _ImportantBadge(),
                    ],
                    const SizedBox(width: NexusSpacing.sm),
                    InkWell(
                      onTap: widget.onOpen,
                      borderRadius: NexusRadii.smRadius,
                      child: Icon(
                        Icons.open_in_new,
                        size: 14,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.content != item.title) ...[
                  const SizedBox(height: NexusSpacing.xs),
                  Text(
                    item.content,
                    maxLines: _expanded ? null : 5,
                    overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: NexusTypography.bodyMd.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.85),
                      height: 1.5,
                    ),
                  ),
                  if (longBody)
                    Padding(
                      padding: const EdgeInsets.only(top: NexusSpacing.xs),
                      child: GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Text(
                          _expanded ? '收起' : '展开全文',
                          style: NexusTypography.labelSm.copyWith(
                            color: colorScheme.secondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ImportantBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: NexusColors.stockDown.withValues(alpha: 0.12),
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Text(
        '重要',
        style: NexusTypography.labelSm.copyWith(
          color: NexusColors.stockDown,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
