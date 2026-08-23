import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/clipboard_item_model.dart';
import '../../data/models/global_index_model.dart';
import '../../data/models/task_model.dart';
import '../../data/models/trending_repo_model.dart';
import '../../data/services/global_index_service.dart';
import '../../data/services/network_monitor_service.dart';
import '../../data/services/trending_service.dart';
import '../../theme/density.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/global_index_carousel.dart';
import '../components/nexus_badge.dart';
import '../components/nexus_card.dart';
import '../components/nexus_toast.dart';
import '../layout/page_scaffold.dart';
import '../states/bookmarks_state.dart';
import '../states/clipboard_state.dart';
import '../states/pomodoro_state.dart';
import '../states/tasks_state.dart';
import 'stocks/fx678_news_pane.dart';

/// Aggregated overview over the hub's live data sources: open tasks, focus
/// sessions, clipboard history, bookmarks, network throughput, global market
/// indices, GitHub trending and finance headlines.
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final TasksState _tasksState = TasksState();
  final BookmarksState _bookmarksState = BookmarksState();
  ClipboardState get _clipboardState => ClipboardState.instance;

  final GlobalIndexService _indexService = GlobalIndexService();
  final TrendingService _trendingService = TrendingService();

  List<TrendingRepo> _trending = const [];
  bool _trendingLoading = true;
  String? _trendingError;

  List<GlobalIndex> _indices = const [];
  bool _indicesLoading = true;
  String? _indicesError;

  @override
  void initState() {
    super.initState();
    _tasksState.load();
    if (_clipboardState.items.value.isEmpty) {
      _clipboardState.load();
    }
    _bookmarksState.load();
    _loadTrending();
    _loadIndices();
  }

  Future<void> _loadTrending() async {
    setState(() {
      _trendingLoading = true;
      _trendingError = null;
    });
    try {
      final repos = await _trendingService.fetchTrending();
      if (mounted) setState(() => _trending = repos);
    } catch (e) {
      if (mounted) setState(() => _trendingError = e.toString());
    } finally {
      if (mounted) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _loadIndices() async {
    setState(() {
      _indicesLoading = true;
      _indicesError = null;
    });
    try {
      final indices = await _indexService.fetchIndices();
      if (mounted) setState(() => _indices = indices);
    } catch (e) {
      if (mounted) setState(() => _indicesError = e.toString());
    } finally {
      if (mounted) setState(() => _indicesLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      header: Row(
        children: [
          Text('仪表盘', style: NexusTypography.headlineSm),
          const SizedBox(width: NexusSpacing.sm),
          Text(
            DateFormat('M/d (EEE)').format(DateTime.now()),
            style: NexusTypography.labelMd.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isWide = width >= 1100;
            final isMedium = width >= 720;
            final gap = SizedBox(height: NexusDensityController.sectionGap);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatStrip(width),
                gap,
                _buildModules(isWide, isMedium),
              ],
            );
          },
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Stat strip
  // ------------------------------------------------------------------

  Widget _buildStatStrip(double width) {
    final cellWidth = (width - 2 * NexusDensityController.cardPadding - 40)
        .clamp(140.0, 190.0);
    return NexusCard(
      child: Wrap(
        spacing: NexusSpacing.md,
        runSpacing: NexusSpacing.md,
        children: [
          _TasksStatCell(state: _tasksState),
          const _FocusStatCell(),
          const _ClipboardStatCell(),
          _BookmarksStatCell(state: _bookmarksState),
          SizedBox(width: cellWidth, child: const _NetworkStatCell()),
        ].map((cell) => SizedBox(width: cellWidth, child: cell)).toList(),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Modules
  // ------------------------------------------------------------------

  Widget _buildModules(bool isWide, bool isMedium) {
    final gap = SizedBox(height: NexusDensityController.sectionGap);

    final modules = <Widget>[
      _ModuleCard(
        title: '今日任务',
        icon: LucideIcons.circleCheck,
        child: _TaskOverviewList(state: _tasksState),
      ),
      _ModuleCard(
        title: '最近剪贴板',
        icon: RadixIcons.clipboard,
        child: const _ClipboardOverviewList(),
      ),
      _ModuleCard(
        title: 'GitHub Trending',
        icon: LucideIcons.trendingUp,
        child: _TrendingOverviewList(
          repos: _trending,
          isLoading: _trendingLoading,
          error: _trendingError,
          onRetry: _loadTrending,
        ),
      ),
      _ModuleCard(
        title: '全球指数',
        icon: LucideIcons.chartLine,
        child: _IndicesSection(
          indices: _indices,
          isLoading: _indicesLoading,
          error: _indicesError,
          onRetry: _loadIndices,
        ),
      ),
      _ModuleCard(
        title: '财经快讯',
        icon: LucideIcons.newspaper,
        child: const SizedBox(height: 300, child: Fx678NewsPane()),
      ),
    ];

    Widget rowOf(List<Widget> children) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: NexusSpacing.md),
              Expanded(child: children[i]),
            ],
          ],
        );

    if (isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rowOf(modules.sublist(0, 3)),
          gap,
          rowOf(modules.sublist(3)),
        ],
      );
    }
    if (isMedium) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rowOf(modules.sublist(0, 2)),
          gap,
          rowOf(modules.sublist(2, 4)),
          gap,
          rowOf(modules.sublist(4)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < modules.length; i++) ...[
          if (i > 0) gap,
          modules[i],
        ],
      ],
    );
  }
}

// --------------------------------------------------------------------
// Stat cells
// --------------------------------------------------------------------

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: NexusTypography.headlineSm.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TasksStatCell extends StatelessWidget {
  const _TasksStatCell({required this.state});

  final TasksState state;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      final tasks = state.tasks.value;
      final done = tasks.where((t) => t.status == 'done').length;
      return _StatCell(
        value: '${tasks.length - done}',
        label: '待办 · $done 已完成',
      );
    });
  }
}

class _FocusStatCell extends StatelessWidget {
  const _FocusStatCell();

  @override
  Widget build(BuildContext context) {
    final pomodoro = PomodoroState.instance;
    return Watch((context) {
      final running = pomodoro.isRunning.value;
      return _StatCell(
        value: '${pomodoro.completedFocus.value}',
        label: running ? '今日专注 · 进行中' : '今日专注次数',
      );
    });
  }
}

class _ClipboardStatCell extends StatelessWidget {
  const _ClipboardStatCell();

  @override
  Widget build(BuildContext context) {
    final state = ClipboardState.instance;
    return Watch((context) {
      final items = state.items.value;
      final latest = items.isEmpty ? '' : _timeAgo(items.first.createdAt);
      return _StatCell(
        value: '${items.length}',
        label: latest.isEmpty ? '剪贴板条目' : '剪贴板 · $latest',
      );
    });
  }
}

class _BookmarksStatCell extends StatelessWidget {
  const _BookmarksStatCell({required this.state});

  final BookmarksState state;

  @override
  Widget build(BuildContext context) {
    return Watch((context) {
      return _StatCell(
        value: '${state.bookmarks.value.length}',
        label: '书签收藏',
      );
    });
  }
}

/// Live network throughput; owns its 1s polling timer so only this cell
/// rebuilds every tick. Renders nothing without the native monitor.
class _NetworkStatCell extends StatefulWidget {
  const _NetworkStatCell();

  @override
  State<_NetworkStatCell> createState() => _NetworkStatCellState();
}

class _NetworkStatCellState extends State<_NetworkStatCell> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!NetworkMonitorService.instance.isRunning) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _formatRate(double bytesPerSecond) {
    if (bytesPerSecond < 1024) return '${bytesPerSecond.round()}B';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).round()}KB';
    }
    return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final service = NetworkMonitorService.instance;
    if (!service.isRunning) {
      return const _StatCell(value: '-', label: '网络监控不可用');
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrowDown,
                size: 12, color: colorScheme.mutedForeground),
            const SizedBox(width: 3),
            Text(
              '${_formatRate(service.recvSpeed.toDouble())}/s',
              style: NexusTypography.headlineSm.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.arrowUp,
                size: 11, color: colorScheme.mutedForeground),
            const SizedBox(width: 3),
            Text(
              '${_formatRate(service.sentSpeed.toDouble())}/s 上行',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------
// Module card shell
// --------------------------------------------------------------------

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return NexusCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: colorScheme.secondary),
              const SizedBox(width: 6),
              Text(
                title,
                style: NexusTypography.labelMd.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: NexusSpacing.sm),
          child,
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------
// Task module
// --------------------------------------------------------------------

class _TaskOverviewList extends StatelessWidget {
  const _TaskOverviewList({required this.state});

  final TasksState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((context) {
      if (state.isLoading.value && state.tasks.value.isEmpty) {
        return const _ModuleHint('加载中…');
      }
      if (state.error.value != null && state.tasks.value.isEmpty) {
        return const _ModuleHint('任务加载失败');
      }
      final tasks = state.tasks.value;
      final open = tasks.where((t) => t.status != 'done').toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final shown = open.take(6).toList();
      if (shown.isEmpty) {
        return const _ModuleHint('没有未完成的任务 🎉');
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < shown.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _TaskRow(task: shown[i], onToggle: () {
              final task = shown[i];
              state.moveTask(task, task.status == 'done' ? 'todo' : 'done');
            }),
          ],
          const SizedBox(height: NexusSpacing.xs),
          Text(
            '${tasks.where((t) => t.status == 'done').length}/${tasks.length} 已完成',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground,
            ),
          ),
        ],
      );
    });
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onToggle});

  final TaskModel task;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final priorityColor = switch (task.priority.toLowerCase()) {
      'high' => colorScheme.destructive,
      'medium' => colorScheme.secondary,
      _ => colorScheme.border,
    };

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 120),
              child: Icon(
                LucideIcons.circle,
                size: 15,
                color: colorScheme.mutedForeground.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Text(
                task.title,
                style: NexusTypography.bodyMd.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: priorityColor,
                borderRadius: NexusRadii.fullRadius,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            NexusBadge(label: task.tag),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------
// Clipboard module
// --------------------------------------------------------------------

class _ClipboardOverviewList extends StatelessWidget {
  const _ClipboardOverviewList();

  @override
  Widget build(BuildContext context) {
    final state = ClipboardState.instance;
    return Watch((context) {
      if (state.isLoading.value && state.items.value.isEmpty) {
        return const _ModuleHint('加载中…');
      }
      if (state.error.value != null && state.items.value.isEmpty) {
        return const _ModuleHint('剪贴板加载失败（需要后端服务）');
      }
      final items = state.items.value.take(6).toList();
      if (items.isEmpty) return const _ModuleHint('暂无剪贴板记录');

      final colorScheme = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _ClipboardRow(item: items[i]),
          ],
          const SizedBox(height: 4),
          Text(
            '点击条目复制',
            style: NexusTypography.labelSm.copyWith(
              color: colorScheme.mutedForeground.withValues(alpha: 0.7),
            ),
          ),
        ],
      );
    });
  }
}

class _ClipboardRow extends StatelessWidget {
  const _ClipboardRow({required this.item});

  final ClipboardItemModel item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = item.isImage
        ? LucideIcons.image
        : item.hasFile
            ? LucideIcons.file
            : RadixIcons.copy;
    final display = item.isImage
        ? '[图片]'
        : item.hasFile
            ? '[文件] ${item.content}'
            : item.content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: item.content));
        if (context.mounted) nexusToast(context, '已复制到剪贴板');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 14, color: colorScheme.mutedForeground),
            const SizedBox(width: NexusSpacing.sm),
            Expanded(
              child: Text(
                display,
                style: NexusTypography.bodyMd.copyWith(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(
              _timeAgo(item.createdAt),
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.mutedForeground,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------
// Trending module
// --------------------------------------------------------------------

class _TrendingOverviewList extends StatelessWidget {
  const _TrendingOverviewList({
    required this.repos,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final List<TrendingRepo> repos;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading && repos.isEmpty) return const _ModuleHint('加载中…');
    if (repos.isEmpty) {
      return _ModuleHint(error != null ? '加载失败，点击重试' : '暂无数据', onTap: onRetry);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final shown = repos.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(
                    '${i + 1}',
                    style: NexusTypography.labelMd.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.mutedForeground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${shown[i].author}/${shown[i].name}',
                    style: NexusTypography.bodyMd.copyWith(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (shown[i].language != null) ...[
                  const SizedBox(width: NexusSpacing.sm),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _parseHexColor(shown[i].languageColor) ??
                          colorScheme.border,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    shown[i].language!,
                    style: NexusTypography.labelSm.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                  ),
                ],
                const SizedBox(width: NexusSpacing.sm),
                Icon(LucideIcons.star,
                    size: 12, color: colorScheme.mutedForeground),
                const SizedBox(width: 3),
                Text(
                  '+${shown[i].currentPeriodStars}',
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.foreground,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Color? _parseHexColor(String hex) {
    final normalized = hex.replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }
}

// --------------------------------------------------------------------
// Indices module
// --------------------------------------------------------------------

class _IndicesSection extends StatelessWidget {
  const _IndicesSection({
    required this.indices,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  final List<GlobalIndex> indices;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading && indices.isEmpty) return const _ModuleHint('加载中…');
    if (indices.isEmpty) {
      return _ModuleHint(error != null ? '指数加载失败，点击重试' : '暂无数据', onTap: onRetry);
    }
    return SizedBox(
      height: 130,
      child: GlobalIndexCarousel(indices: indices, onRefresh: onRetry),
    );
  }
}

// --------------------------------------------------------------------
// Shared bits
// --------------------------------------------------------------------

class _ModuleHint extends StatelessWidget {
  const _ModuleHint(this.message, {this.onTap});

  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Padding(
      padding: const EdgeInsets.symmetric(vertical: NexusSpacing.md),
      child: Text(
        message,
        style: NexusTypography.labelMd.copyWith(
          color: colorScheme.mutedForeground,
        ),
      ),
    );
    if (onTap == null) return text;
    return GestureDetector(onTap: onTap, child: text);
  }
}

String _timeAgo(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.inSeconds < 60) return '刚刚';
  if (difference.inMinutes < 60) return '${difference.inMinutes}分钟前';
  if (difference.inHours < 24) return '${difference.inHours}小时前';
  return DateFormat('M/d').format(dateTime);
}
