import 'package:flutter/material.dart';

import '../../../data/models/video_models.dart';
import '../../../data/services/video_site_service.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_empty_state.dart';
import 'video_play_page.dart';

/// Series detail page: poster, metadata, synopsis and the playback sources
/// with their episode grids scraped from the site's detail page.
class VideoDetailPage extends StatefulWidget {
  const VideoDetailPage({super.key, required this.series});

  /// The list entry this page was opened from; used as placeholder data
  /// while the full detail page downloads.
  final VideoSeries series;

  @override
  State<VideoDetailPage> createState() => _VideoDetailPageState();
}

class _VideoDetailPageState extends State<VideoDetailPage> {
  final VideoSiteService _service = VideoSiteService();

  VideoDetail? _detail;
  bool _loading = false;
  String? _error;
  int _selectedSource = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _service.fetchDetail(widget.series.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _selectedSource = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '无法加载详情：$e';
        _loading = false;
      });
    }
  }

  void _openEpisode(int episodeIndex) {
    final detail = _detail;
    if (detail == null) return;
    final source = detail.sources[_selectedSource];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayPage(
          seriesTitle: detail.title,
          sourceName: source.name,
          episodes: source.episodes,
          initialEpisode: episodeIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _detail?.title ?? widget.series.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新加载',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(context),
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
    final detail = _detail;
    if (detail == null) {
      return const NexusEmptyState(
        icon: Icons.movie_outlined,
        title: '没有数据',
      );
    }
    if (!detail.hasEpisodes) {
      return const NexusEmptyState(
        icon: Icons.videocam_off_outlined,
        title: '暂无可播放资源',
        subtitle: '该剧在数据源上没有任何播放源。',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(NexusSpacing.md),
      children: [
        _buildHeaderRow(context, detail),
        const SizedBox(height: NexusSpacing.md),
        _SectionTitle('剧情简介'),
        const SizedBox(height: NexusSpacing.xs),
        Text(
          detail.synopsis.isEmpty ? '暂无简介' : detail.synopsis,
          style: NexusTypography.bodyMd.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: NexusSpacing.lg),
        _SectionTitle('播放源 (${detail.sources.length})'),
        const SizedBox(height: NexusSpacing.sm),
        Wrap(
          spacing: NexusSpacing.sm,
          runSpacing: NexusSpacing.sm,
          children: [
            for (var i = 0; i < detail.sources.length; i++)
              _SourceChip(
                label: detail.sources[i].name,
                count: detail.sources[i].episodes.length,
                selected: i == _selectedSource,
                onTap: () => setState(() => _selectedSource = i),
              ),
          ],
        ),
        const SizedBox(height: NexusSpacing.md),
        _EpisodeGrid(
          episodes: detail.sources[_selectedSource].episodes,
          onTap: _openEpisode,
        ),
      ],
    );
  }

  Widget _buildHeaderRow(BuildContext context, VideoDetail detail) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: NexusRadii.lgRadius,
          child: SizedBox(
            width: 140,
            height: 190,
            child: Image.network(
              detail.coverUrl.isEmpty ? widget.series.coverUrl : detail.coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: colorScheme.surfaceContainerHigh,
                child: Icon(
                  Icons.movie_outlined,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: NexusSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.title,
                style: NexusTypography.headlineSm,
              ),
              const SizedBox(height: NexusSpacing.sm),
              Wrap(
                spacing: NexusSpacing.xs,
                runSpacing: NexusSpacing.xs,
                children: [
                  if (detail.remarks.isNotEmpty) _MetaChip(detail.remarks),
                  if (detail.year.isNotEmpty) _MetaChip(detail.year),
                  if (detail.area.isNotEmpty) _MetaChip(detail.area),
                  if (detail.score != null)
                    _MetaChip('评分 ${detail.score!.toStringAsFixed(1)}'),
                ],
              ),
              if (detail.actors.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.sm),
                Text(
                  '演员：${detail.actors}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (detail.genres.isNotEmpty) ...[
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  '类型：${detail.genres}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: NexusTypography.bodyMd.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: NexusRadii.fullRadius,
      ),
      child: Text(
        label,
        style: NexusTypography.labelSm.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
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
          color: selected ? colorScheme.secondary : colorScheme.surfaceContainerHigh,
          borderRadius: NexusRadii.fullRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: NexusTypography.labelMd.copyWith(
                color: selected ? colorScheme.onSecondary : colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: NexusSpacing.xs),
            Text(
              '$count',
              style: NexusTypography.labelSm.copyWith(
                color: selected
                    ? colorScheme.onSecondary.withValues(alpha: 0.8)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Episode buttons for the selected playback source.
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.episodes, required this.onTap});

  final List<VideoEpisode> episodes;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: NexusSpacing.sm,
      runSpacing: NexusSpacing.sm,
      children: [
        for (final episode in episodes)
          InkWell(
            borderRadius: NexusRadii.mdRadius,
            onTap: () => onTap(episode.index - 1),
            child: Container(
              constraints: const BoxConstraints(minWidth: 56),
              padding: const EdgeInsets.symmetric(
                horizontal: NexusSpacing.sm,
                vertical: NexusSpacing.xs + 2,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                borderRadius: NexusRadii.mdRadius,
              ),
              child: Text(
                episode.label,
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
