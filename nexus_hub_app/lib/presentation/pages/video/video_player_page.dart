import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../data/models/video_models.dart';
import '../../../data/models/video_site_config.dart';
import '../../../data/services/video_site_config_storage.dart';
import '../../../data/services/video_site_exception.dart';
import '../../../data/services/video_site_service.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_cached_image.dart';
import '../../components/nexus_empty_state.dart';
import '../../components/nexus_input.dart';
import '../../layout/page_scaffold.dart';
import 'video_detail_page.dart';
import 'video_source_manager_dialog.dart';

/// Video streaming sub-app: browses the movies / series / documentary /
/// variety / anime lists of the active data source, with title search.
/// The header offers a quick source switcher; the settings button beside
/// it opens the source manager where sources can be created, edited and
/// deleted.
///
/// Sources whose protocol gates the browse list behind a captcha (see
/// [CaptchaRequiredException]) prompt an in-app challenge dialog and
/// retry automatically once it is solved.
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
  /// Data source the current [_service] was built from; kept besides the
  /// service so the source switcher can mark the active entry.
  VideoSiteConfig _config = VideoSiteConfigStorage.current;
  late VideoSiteService _service = VideoSiteService(config: _config);
  final TextEditingController _searchController = TextEditingController();

  final Map<VideoCategory, _CategoryTabData> _tabs = {
    for (final category in VideoCategory.values) category: _CategoryTabData(),
  };
  VideoCategory _category = VideoCategory.series;
  bool _loading = false;
  String? _error;

  /// True while the last error was a skipped captcha challenge, so the
  /// error state can offer a "重新验证" action.
  bool _captchaPending = false;

  /// Monotonic request counter; completions of superseded requests only
  /// update the cache, never the UI.
  int _requestSeq = 0;

  /// Non-empty while search results (instead of the paged list) are shown.
  String _searchKeyword = '';
  List<VideoSeries> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Activates the persisted data source configuration before the first
  /// load; the field-initialized service already matches it unless
  /// storage holds a customized one.
  Future<void> _init() async {
    final config = await VideoSiteConfigStorage.load();
    if (!mounted) return;
    if (config != _config) {
      setState(() => _applyConfig(config));
    }
    _loadCategory(VideoCategory.series);
  }

  /// Points the page at a new data source: rebuilds the service with
  /// [config] and drops every cached browse page and search result.
  ///
  /// Callers are responsible for wrapping this in `setState` and reloading
  /// the visible category.
  void _applyConfig(VideoSiteConfig config) {
    _config = config;
    _service = VideoSiteService(config: config);
    _error = null;
    _captchaPending = false;
    _searchKeyword = '';
    _searchResults = const [];
    _searchController.clear();
    for (final tab in _tabs.values) {
      tab
        ..page = 1
        ..result = null;
    }
  }

  /// Switches browsing and playback to the saved source with [id].
  Future<void> _switchSource(String id) async {
    if (id == _config.id) return;
    final source = VideoSiteConfigStorage.sources
        .where((s) => s.id == id)
        .firstOrNull;
    if (source == null) return;
    await VideoSiteConfigStorage.setActive(id);
    if (!mounted) return;
    setState(() => _applyConfig(VideoSiteConfigStorage.current));
    _loadCategory(_category);
  }

  /// Opens the data source manager. Every change inside is persisted
  /// directly; when the active source changed (switched, edited or the
  /// active one deleted), the browse list reloads from it.
  Future<void> _openSources() async {
    final active = await showVideoSourceManagerDialog(context);
    if (!mounted || active == _config) return;
    setState(() => _applyConfig(active));
    _loadCategory(_category);
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
      _captchaPending = false;
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
    } on CaptchaRequiredException {
      if (!mounted) return;
      final solved = await _handleCaptchaChallenge();
      if (!mounted || seq != _requestSeq) return;
      if (solved) {
        _loadCategory(category, page: targetPage);
        return;
      }
      setState(() {
        _captchaPending = true;
        _error = '该数据源需要完成人机验证后才能浏览列表';
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = '无法加载${category.label}列表：$e';
        _loading = false;
      });
    }
  }

  /// Opens the captcha challenge dialog of the active source (protocols
  /// without one never get here — their pages do not throw
  /// [CaptchaRequiredException]). True when the challenge was solved and
  /// the failed request can be retried.
  Future<bool> _handleCaptchaChallenge() async {
    final movie555 = _service.movie555;
    if (movie555 == null) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _CaptchaDialog(
            fetchImage: movie555.fetchCaptchaImage,
            submit: movie555.submitCaptcha,
          ),
        ) ??
        false;
  }

  void _switchCategory(VideoCategory category) {
    if (category == _category && _searchKeyword.isEmpty) return;
    setState(() {
      _category = category;
      _searchKeyword = '';
      _searchResults = const [];
      _searchController.clear();
      _error = null;
      _captchaPending = false;
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
      _captchaPending = false;
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
                    ? '${_category.label} · ${_config.name} · ${_config.domain}'
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
        _SourceSwitcherButton(
          config: _config,
          onSelected: _switchSource,
          onManage: _openSources,
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
        const SizedBox(width: NexusSpacing.sm),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 20),
          tooltip: '管理数据源',
          onPressed: _openSources,
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
        action: _captchaPending
            ? NexusButton(
                label: '重新验证',
                variant: NexusButtonVariant.tonal,
                icon: Icons.verified_user_outlined,
                onPressed: () => _loadCategory(_category),
              )
            : null,
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

/// Category (movie / series / documentary / variety / anime) selector shown
/// above the browse grid.
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

/// Compact header button listing every saved data source; picking one
/// switches browsing and playback to it, the trailing entry opens the
/// source manager.
class _SourceSwitcherButton extends StatelessWidget {
  const _SourceSwitcherButton({
    required this.config,
    required this.onSelected,
    required this.onManage,
  });

  /// The currently active source, marked in the menu.
  final VideoSiteConfig config;

  /// Called with the id of the picked source.
  final ValueChanged<String> onSelected;

  /// Opens the source manager dialog.
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: '切换数据源',
      constraints: const BoxConstraints(minWidth: 240),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == '_manage') {
          onManage();
        } else {
          onSelected(value);
        }
      },
      itemBuilder: (context) => [
        for (final source in VideoSiteConfigStorage.sources)
          PopupMenuItem<String>(
            value: source.id,
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child:
                      source.id == config.id
                          ? Icon(
                              Icons.check,
                              size: 16,
                              color: colorScheme.secondary,
                            )
                          : null,
                ),
                const SizedBox(width: NexusSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        source.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        source.domain,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NexusTypography.labelSm.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: '_manage',
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                child: Icon(Icons.settings_outlined, size: 16),
              ),
              const SizedBox(width: NexusSpacing.xs),
              const Text('管理数据源…'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.sm + 2,
          vertical: NexusSpacing.xs + 3,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: NexusRadii.mdRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 16,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: NexusSpacing.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                config.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NexusTypography.labelMd,
              ),
            ),
            const SizedBox(width: NexusSpacing.xs),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
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

/// Captcha challenge dialog for sites that gate their browse list behind
/// an image captcha (555电影): loads the code image bound to the site
/// session, submits the typed code and pops with `true` on success.
///
/// [fetchImage] and [submit] come straight from the active source's
/// Movie555SiteService so the image and the check share its cookie jar.
class _CaptchaDialog extends StatefulWidget {
  const _CaptchaDialog({required this.fetchImage, required this.submit});

  final Future<Uint8List> Function() fetchImage;
  final Future<bool> Function(String code) submit;

  @override
  State<_CaptchaDialog> createState() => _CaptchaDialogState();
}

class _CaptchaDialogState extends State<_CaptchaDialog> {
  final _codeController = TextEditingController();
  Uint8List? _image;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshImage();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refreshImage() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await widget.fetchImage();
      if (mounted) {
        setState(() {
          _image = image;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '验证码加载失败：$e';
          _busy = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final solved = await widget.submit(code);
      if (!mounted) return;
      if (solved) {
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _error = '验证码不正确，请重试';
        _busy = false;
      });
      _codeController.clear();
      await _refreshImage();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '提交失败：$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      backgroundColor: colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: NexusRadii.lgRadius),
      title: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 24,
              color: colorScheme.secondary),
          const SizedBox(width: NexusSpacing.sm),
          Text('人机验证', style: NexusTypography.headlineSm),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '该站点要求完成验证后才能浏览列表，输入图片中的字符即可，验证一次在本轮浏览中持续有效。',
              style: NexusTypography.labelSm.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: NexusSpacing.md),
            Center(
              child: _busy && _image == null
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : _image == null
                      ? Text(
                          _error ?? '验证码不可用',
                          style: NexusTypography.labelSm.copyWith(
                            color: colorScheme.error,
                          ),
                        )
                      : GestureDetector(
                          onTap: _refreshImage,
                          child: ClipRRect(
                            borderRadius: NexusRadii.smRadius,
                            child: Image.memory(
                              _image!,
                              height: 48,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
            ),
            if (_image != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _busy ? null : _refreshImage,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('换一张'),
                ),
              ),
            NexusInput(
              controller: _codeController,
              labelText: '验证码',
              hintText: '输入图片中的字符',
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null && _image != null) ...[
              const SizedBox(height: NexusSpacing.sm),
              Text(
                _error!,
                style: NexusTypography.labelSm.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        NexusButton(
          label: '取消',
          variant: NexusButtonVariant.text,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        const SizedBox(width: NexusSpacing.sm),
        NexusButton(
          label: '提交',
          icon: Icons.check,
          onPressed: _busy ? null : _submit,
        ),
      ],
    );
  }
}
