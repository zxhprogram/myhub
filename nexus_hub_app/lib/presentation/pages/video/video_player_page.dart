import 'package:flutter/material.dart';

import '../../../data/models/video_models.dart';
import '../../../data/services/video_site_service.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_cached_image.dart';
import '../../components/nexus_empty_state.dart';
import '../../components/nexus_input.dart';
import '../../layout/page_scaffold.dart';
import 'video_detail_page.dart';

/// Video streaming sub-app: browses the movies / series / variety lists
/// scraped from netflixgc.com, with title search.
///
/// Tapping a poster opens [VideoDetailPage] inside the desktop window's
/// local navigator.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

/// Browse state of one category tab: the last loaded page and its result.
class _CategoryTabData {
  int page = 1;
  VideoSeriesPage? result;
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  final VideoSiteService _service = VideoSiteService();
  final TextEditingController _searchController = TextEditingController();

  final Map<VideoCategory, _CategoryTabData> _tabs = {
    for (final category in VideoCategory.values) category: _CategoryTabData(),
  };
  VideoCategory _category = VideoCategory.series;
  bool _loading = false;
  String? _error;

  /// Monotonic request counter; completions of superseded requests only
  /// update the cache, never the UI.
  int _requestSeq = 0;

  /// Non-empty while search results (instead of the paged list) are shown.
  String _searchKeyword = '';
  List<VideoSeries> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _loadCategory(VideoCategory.series);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategory(VideoCategory category, {int? page}) async {
    final tab = _tabs[category]!;
    final targetPage = page ?? tab.page;
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.fetchSeries(
        category: category,
        page: targetPage,
      );
      tab
        ..page = result.page
        ..result = result;
      if (!mounted || seq != _requestSeq) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = '无法加载${category.label}列表：$e';
        _loading = false;
      });
    }
  }

  void _switchCategory(VideoCategory category) {
    if (category == _category && _searchKeyword.isEmpty) return;
    setState(() {
      _category = category;
      _searchKeyword = '';
      _searchResults = const [];
      _searchController.clear();
      _error = null;
    });
    // Cached pages survive tab switches; only fetch what is missing.
    if (_tabs[category]!.result == null) {
      _loadCategory(category);
    }
  }

  Future<void> _runSearch(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
      _searchKeyword = trimmed;
    });
    try {
      final results = await _service.search(trimmed);
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _searchResults = results;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = '搜索失败：$e';
        _loading = false;
      });
    }
  }

  void _exitSearch() {
    setState(() {
      _searchKeyword = '';
      _searchResults = const [];
      _searchController.clear();
    });
  }

  void _openDetail(VideoSeries series) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoDetailPage(series: series),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      header: _buildHeader(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CategoryTabs(
            selected: _searchKeyword.isEmpty ? _category : null,
            onSelect: _switchCategory,
          ),
          const SizedBox(height: NexusSpacing.md),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Video', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                _searchKeyword.isEmpty
                    ? 'Browse ${_category.label} on NetflixGC'
                    : '搜索“$_searchKeyword”的结果',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: NexusSpacing.md),
        SizedBox(
          width: 260,
          child: NexusInput(
            controller: _searchController,
            hintText: '搜索剧名…',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: _searchKeyword.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: '清除搜索',
                    onPressed: _exitSearch,
                  ),
            onSubmitted: _runSearch,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.5));
    }
    if (_error != null) {
      return NexusEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '加载失败',
        subtitle: _error!,
      );
    }

    if (_searchKeyword.isNotEmpty) {
      if (_searchResults.isEmpty) {
        return NexusEmptyState(
          icon: Icons.search_off,
          title: '没有找到相关影片',
          subtitle: '换个关键词试试，或点击上方分类返回列表。',
        );
      }
      return _SeriesGrid(items: _searchResults, onTap: _openDetail);
    }

    final result = _tabs[_category]!.result;
    if (result == null || result.items.isEmpty) {
      return NexusEmptyState(
        icon: Icons.movie_outlined,
        title: '暂无${_category.label}',
        subtitle: '数据源暂时没有返回内容，请切换分类或稍后重试。',
      );
    }
    return Column(
      children: [
        Expanded(child: _SeriesGrid(items: result.items, onTap: _openDetail)),
        const SizedBox(height: NexusSpacing.sm),
        _PageBar(
          page: result.page,
          pageCount: result.pageCount,
          total: result.total,
          onPrev: result.page > 1
              ? () => _loadCategory(_category, page: result.page - 1)
              : null,
          onNext: result.page < result.pageCount
              ? () => _loadCategory(_category, page: result.page + 1)
              : null,
        ),
      ],
    );
  }
}

/// Movie / series / variety selector shown above the browse grid.
///
/// Passes `null` as [selected] while search results are displayed; picking
/// any tab leaves search mode.
class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelect});

  final VideoCategory? selected;
  final ValueChanged<VideoCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: NexusSpacing.sm,
      children: [
        for (final category in VideoCategory.values)
          _CategoryTab(
            label: category.label,
            selected: category == selected,
            onTap: () => onSelect(category),
          ),
      ],
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
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
    return InkWell(
      borderRadius: NexusRadii.fullRadius,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondary
              : colorScheme.surfaceContainerHigh,
          borderRadius: NexusRadii.fullRadius,
        ),
        child: Text(
          label,
          style: NexusTypography.labelMd.copyWith(
            color: selected ? colorScheme.onSecondary : colorScheme.onSurface,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Poster grid shared by the browse list and search results.
class _SeriesGrid extends StatelessWidget {
  const _SeriesGrid({required this.items, required this.onTap});

  final List<VideoSeries> items;
  final ValueChanged<VideoSeries> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: NexusSpacing.md,
        crossAxisSpacing: NexusSpacing.md,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final series = items[index];
        return _SeriesCard(series: series, onTap: () => onTap(series));
      },
    );
  }
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.onTap});

  final VideoSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: NexusRadii.mdRadius,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _CoverImage(series: series)),
          const SizedBox(height: NexusSpacing.xs + 2),
          Text(
            series.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NexusTypography.labelMd.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (series.remarks.isNotEmpty)
            Text(
              series.remarks,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

/// Poster image with the broadcast state (remarks) as a corner badge.
class _CoverImage extends StatelessWidget {
  const _CoverImage({required this.series});

  final VideoSeries series;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: NexusRadii.mdRadius,
          child: NexusCachedImage(
            url: series.coverUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, _) => ColoredBox(
              color: colorScheme.surfaceContainerHigh,
              child: Icon(
                Icons.movie_outlined,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (series.remarks.isNotEmpty)
          Positioned(
            left: 0,
            bottom: 0,
            right: 0,
            child: ClipRect(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                color: Colors.black.withValues(alpha: 0.55),
                child: Text(
                  series.remarks,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelSm.copyWith(
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Prev/next pagination bar below the browse grid.
class _PageBar extends StatelessWidget {
  const _PageBar({
    required this.page,
    required this.pageCount,
    required this.total,
    this.onPrev,
    this.onNext,
  });

  final int page;
  final int pageCount;
  final int total;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: '上一页',
          onPressed: onPrev,
        ),
        Expanded(
          child: Center(
            child: Text(
              '第 $page / $pageCount 页 · 共 $total 部',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: '下一页',
          onPressed: onNext,
        ),
      ],
    );
  }
}
