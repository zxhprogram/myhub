import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../data/models/video_models.dart';
import '../../../data/services/video_site_service.dart';
import '../../../theme/radii.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../components/nexus_button.dart';
import '../../components/nexus_empty_state.dart';

/// Episode player page.
///
/// Each episode's play page on the data source hides its resource reference
/// behind two layers of encryption; [VideoSiteService.resolvePlay] decrypts
/// both natively and returns a direct stream URL, which is played by the
/// libmpv-backed [Player] — no WebView involved.
class VideoPlayPage extends StatefulWidget {
  const VideoPlayPage({
    super.key,
    required this.seriesTitle,
    required this.sourceName,
    required this.episodes,
    required this.initialEpisode,
  });

  final String seriesTitle;
  final String sourceName;

  /// Episodes of the selected playback source, in site order.
  final List<VideoEpisode> episodes;

  /// 0-based index into [episodes].
  final int initialEpisode;

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> {
  final VideoSiteService _service = VideoSiteService();
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  VideoPlayInfo? _playInfo;
  bool _loading = false;
  String? _error;
  late int _current = widget.initialEpisode;
  StreamSubscription<bool>? _completedSub;

  VideoEpisode get _episode => widget.episodes[_current];

  @override
  void initState() {
    super.initState();
    // Auto-advance to the next episode when playback completes.
    _completedSub = _player.stream.completed.listen((_) {
      if (!mounted || _loading || _error != null) return;
      if (_current < widget.episodes.length - 1) {
        _switchEpisode(_current + 1);
      }
    });
    _resolve();
  }

  @override
  void dispose() {
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _service.resolvePlay(
        playPath: _episode.playPath,
        episodeLabel: _episode.label,
      );
      if (!mounted) return;
      setState(() {
        _playInfo = info;
        _loading = false;
      });
      await _player.open(Media(info.streamUrl));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '解析播放地址失败：$e';
        _loading = false;
      });
    }
  }

  void _switchEpisode(int index) {
    if (index < 0 || index >= widget.episodes.length || index == _current) {
      return;
    }
    _current = index;
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: Text(
        '${widget.seriesTitle} · ${_episode.label}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: NexusTypography.bodyMd.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.skip_previous),
          tooltip: '上一集',
          color: Colors.white,
          onPressed: _current > 0 ? () => _switchEpisode(_current - 1) : null,
        ),
        IconButton(
          icon: const Icon(Icons.skip_next),
          tooltip: '下一集',
          color: Colors.white,
          onPressed: _current < widget.episodes.length - 1
              ? () => _switchEpisode(_current + 1)
              : null,
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
      );
    }
    if (_error != null) {
      return NexusEmptyState(
        icon: Icons.cloud_off_outlined,
        title: '播放解析失败',
        subtitle: _error!,
        action: NexusButton(
          label: '重试',
          icon: Icons.refresh,
          onPressed: _resolve,
        ),
      );
    }
    if (_playInfo == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        Expanded(
          // media_kit's built-in controls provide play/pause, seek, volume
          // and fullscreen on top of the libmpv backend.
          child: Video(controller: _controller),
        ),
        _EpisodeStrip(
          episodes: widget.episodes,
          current: _current,
          onSelect: _switchEpisode,
        ),
      ],
    );
  }
}

/// Horizontal episode switcher docked under the player.
class _EpisodeStrip extends StatelessWidget {
  const _EpisodeStrip({
    required this.episodes,
    required this.current,
    required this.onSelect,
  });

  final List<VideoEpisode> episodes;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      color: Colors.black.withValues(alpha: 0.85),
      padding: const EdgeInsets.symmetric(horizontal: NexusSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 16,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          const SizedBox(width: NexusSpacing.sm),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: episodes.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(width: NexusSpacing.xs),
              itemBuilder: (context, index) {
                final selected = index == current;
                return InkWell(
                  borderRadius: NexusRadii.mdRadius,
                  onTap: () => onSelect(index),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: NexusSpacing.sm + 2,
                        vertical: NexusSpacing.xs + 2,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.red
                            : Colors.white.withValues(alpha: 0.12),
                        borderRadius: NexusRadii.mdRadius,
                      ),
                      child: Text(
                        episodes[index].label,
                        style: NexusTypography.labelMd.copyWith(
                          color: selected ? Colors.white : Colors.white70,
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
