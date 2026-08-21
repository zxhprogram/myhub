import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/music_playlist_model.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../components/nexus_cached_image.dart';
import '../layout/page_scaffold.dart';
import '../states/music_player_state.dart';

/// Online music player page.
///
/// A macOS Music-style layout: a now-playing panel with artwork on the
/// left, the browse / track-list pane on the right and a transport bar
/// with seek/volume controls along the bottom. Audio keeps streaming while
/// the desktop window is closed because the engine lives in
/// [MusicPlayerState]. Track data is sourced from the mu-jie.cc musicBox
/// API.
class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({super.key});

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  @override
  void initState() {
    super.initState();
    // Boots the headless browser tab that streams the audio. Idempotent.
    MusicPlayerState.instance.init();
    // Load recommended playlists on first open.
    MusicPlayerState.instance.loadRecommendPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PageScaffold(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Music', style: NexusTypography.headlineXl),
              const SizedBox(height: NexusSpacing.xs),
              Text(
                'mu-jie.cc musicBox · 在线音乐',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.sm + NexusSpacing.xs,
              vertical: NexusSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: NexusRadii.fullRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.cloud,
                  size: 14,
                  color: colorScheme.secondaryForeground,
                ),
                const SizedBox(width: NexusSpacing.xs),
                Text(
                  'Streaming',
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.secondaryForeground,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          return Column(
            children: [
              Expanded(
                child: compact
                    ? Column(
                        children: const [
                          _CompactNowPlaying(),
                          Expanded(child: _RightPane()),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          _NowPlayingPanel(),
                          _PlaylistDivider(),
                          Expanded(child: _RightPane()),
                        ],
                      ),
              ),
              const _PlayerBar(),
            ],
          );
        },
      ),
    );
  }
}

/// Hairline between the now-playing panel and the playlist.
class _PlaylistDivider extends StatelessWidget {
  const _PlaylistDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: Theme.of(
        context,
      ).colorScheme.border.withValues(alpha: 0.5),
    );
  }
}

/// Artwork widget: shows the cover image when available, otherwise a
/// generated gradient.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.palette,
    this.imageUrl = '',
    this.iconSize = 44,
  });

  final List<Color> palette;
  final String imageUrl;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: NexusRadii.xlRadius,
        child: NexusCachedImage(
          url: imageUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _) => _gradientArtwork,
        ),
      );
    }
    return _gradientArtwork;
  }

  Widget get _gradientArtwork => Container(
        decoration: BoxDecoration(
          borderRadius: NexusRadii.xlRadius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette,
          ),
          boxShadow: [
            BoxShadow(
              color: palette.last.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: Icon(LucideIcons.music, color: const Color(0xB3FFFFFF), size: iconSize),
        ),
      );
}

/// Full-height now-playing panel shown on wide layouts.
class _NowPlayingPanel extends StatelessWidget {
  const _NowPlayingPanel();

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.currentIndex.watch(context);
    state.isPlaying.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final track = state.currentTrack;
    if (track == null) {
      return SizedBox(
        width: 280,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.disc,
              size: 72,
              color: colorScheme.mutedForeground.withValues(alpha: 0.4),
            ),
            const SizedBox(height: NexusSpacing.md),
            Text(
              'Pick a track to start listening',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return SizedBox(
      width: 280,
      child: Padding(
        padding: const EdgeInsets.all(NexusSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: _Artwork(
                palette: _paletteFor(state.currentIndex.value),
                imageUrl: track.pic,
              ),
            ),
            const SizedBox(height: NexusSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    track.title,
                    style: NexusTypography.headlineSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.isPlaying.value)
                  _EqualizerIndicator(color: colorScheme.primary),
              ],
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              track.artist,
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              track.album.isEmpty ? track.artist : track.album,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact horizontal now-playing strip shown on narrow layouts.
class _CompactNowPlaying extends StatelessWidget {
  const _CompactNowPlaying();

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.currentIndex.watch(context);
    state.isPlaying.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final track = state.currentTrack;
    if (track == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          NexusSpacing.md,
          0,
          NexusSpacing.md,
          NexusSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(
              LucideIcons.disc,
              size: 20,
              color: colorScheme.mutedForeground.withValues(alpha: 0.5),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(
              'Pick a track below to start listening',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.md,
        0,
        NexusSpacing.md,
        NexusSpacing.sm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: _Artwork(
              palette: _paletteFor(state.currentIndex.value),
              imageUrl: track.pic,
              iconSize: 24,
            ),
          ),
          const SizedBox(width: NexusSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.title,
                  style: NexusTypography.headlineSm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: NexusSpacing.xs),
                Text(
                  track.artist,
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.mutedForeground,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (state.isPlaying.value)
            _EqualizerIndicator(color: colorScheme.primary),
        ],
      ),
    );
  }
}

/// Right pane: search bar + browse grid / track list.
class _RightPane extends StatefulWidget {
  const _RightPane();

  @override
  State<_RightPane> createState() => _RightPaneState();
}

class _RightPaneState extends State<_RightPane> {
  final _searchController = TextEditingController();
  bool _searchSongs = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final keywords = _searchController.text.trim();
    if (keywords.isEmpty) return;
    final state = MusicPlayerState.instance;
    if (_searchSongs) {
      await state.searchSongs(keywords);
    } else {
      await state.searchPlaylists(keywords);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.playlistTitle.watch(context);
    state.isPlaylistLoading.watch(context);
    state.isBrowseLoading.watch(context);
    state.browseMode.watch(context);
    state.errorMessage.watch(context);
    final colorScheme = Theme.of(context).colorScheme;

    final showBrowse = state.playlist.value.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexusSpacing.md,
            NexusSpacing.sm,
            NexusSpacing.md,
            NexusSpacing.xs,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  hintText: '搜索歌单或歌曲',
                  onSubmitted: (_) => _doSearch(),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: NexusSpacing.xs),
              TabList(
                index: _searchSongs ? 1 : 0,
                onChanged: (index) => setState(() => _searchSongs = index == 1),
                children: const [
                  TabChildWidget(
                    indexed: true,
                    child: TabButton(
                      child: Text('歌单', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  TabChildWidget(
                    indexed: true,
                    child: TabButton(
                      child: Text('歌曲', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Error banner
        if (state.errorMessage.value != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NexusSpacing.md,
            ),
            child: Text(
              state.errorMessage.value!,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.destructive,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        // Content
        Expanded(
          child: showBrowse ? _BrowseContent() : _TrackListContent(),
        ),
      ],
    );
  }
}

/// Browse pane showing recommended playlists or search results.
class _BrowseContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.isBrowseLoading.watch(context);
    state.browseMode.watch(context);
    state.recommendPlaylists.watch(context);
    state.searchPlaylistResults.watch(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (state.isBrowseLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    final playlists = state.browseMode.value == MusicBrowseMode.search
        ? state.searchPlaylistResults.value
        : state.recommendPlaylists.value;

    if (playlists.isEmpty) {
      return Center(
        child: Text(
          '暂无歌单',
          style: NexusTypography.bodyMd.copyWith(
            color: colorScheme.mutedForeground,
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
        NexusSpacing.md,
        NexusSpacing.xs,
        NexusSpacing.md,
        NexusSpacing.sm,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        childAspectRatio: 0.72,
        crossAxisSpacing: NexusSpacing.sm,
        mainAxisSpacing: NexusSpacing.sm,
      ),
      itemCount: playlists.length,
      itemBuilder: (context, index) =>
          _PlaylistCard(playlist: playlists[index]),
    );
  }
}

/// A single playlist card in the browse grid.
class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({required this.playlist});

  final MusicPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
  onTap: () => MusicPlayerState.instance.loadPlaylist(playlist),
  child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: NexusRadii.mdRadius,
              child: AspectRatio(
                aspectRatio: 1,
                child: playlist.coverImgUrl.isNotEmpty
                    ? NexusCachedImage(
                        url: playlist.coverImgUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _) => _placeholderCover(colorScheme),
                      )
                    : _placeholderCover(colorScheme),
              ),
            ),
          ),
          const SizedBox(height: NexusSpacing.xs),
          Text(
            playlist.name,
            style: NexusTypography.labelMd.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (playlist.playCount > 0)
            Text(
              _formatPlayCount(playlist.playCount),
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
                fontSize: 11,
              ),
              maxLines: 1,
            ),
        ],
      ),
);
  }

  Widget _placeholderCover(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.accent,
        borderRadius: NexusRadii.mdRadius,
      ),
      child: Icon(
        LucideIcons.listMusic,
        color: colorScheme.mutedForeground.withValues(alpha: 0.5),
      ),
    );
  }
}

/// Track list content for the currently loaded playlist.
class _TrackListContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.playlist.watch(context);
    state.isPlaylistLoading.watch(context);
    state.playlistTitle.watch(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (state.isPlaylistLoading.value) {
      return const Center(child: CircularProgressIndicator());
    }

    final tracks = state.playlist.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            NexusSpacing.md,
            NexusSpacing.sm,
            NexusSpacing.md,
            NexusSpacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  state.playlistTitle.value.isEmpty
                      ? 'Up Next'
                      : state.playlistTitle.value,
                  style: NexusTypography.labelMd.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: NexusSpacing.sm),
              GestureDetector(
  onTap: () {
                  state.playlist.value = const [];
                  state.playlistTitle.value = '';
                  state.currentIndex.value = -1;
                },
  child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: NexusSpacing.xs,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        RadixIcons.arrowLeft,
                        size: 14,
                        color: colorScheme.mutedForeground,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '歌单',
                        style: NexusTypography.labelMd.copyWith(
                          color: colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
),
              const SizedBox(width: NexusSpacing.sm),
              Text(
                '${tracks.length} tracks',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
            itemCount: tracks.length,
            itemBuilder: (context, index) => _TrackRow(index: index),
          ),
        ),
      ],
    );
  }
}

/// A single playlist row.
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.currentIndex.watch(context);
    state.isPlaying.watch(context);
    state.durationSeconds.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final track = state.playlist.value[index];
    final isCurrent = state.currentIndex.value == index;
    return GestureDetector(
  onTap: () => state.playTrack(index),
  child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NexusSpacing.md,
          vertical: NexusSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              child: Center(
                child: isCurrent && state.isPlaying.value
                    ? _EqualizerIndicator(color: colorScheme.primary)
                    : Text(
                        '${index + 1}',
                        style: NexusTypography.labelMd.copyWith(
                          color: isCurrent
                              ? colorScheme.primary
                              : colorScheme.mutedForeground,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: NexusSpacing.sm),
            SizedBox(
              width: 34,
              height: 34,
              child: _Artwork(
                palette: _paletteFor(index),
                imageUrl: track.pic,
                iconSize: 16,
              ),
            ),
            const SizedBox(width: NexusSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    style: NexusTypography.bodyMd.copyWith(
                      fontWeight: FontWeight.w600,
                      color: isCurrent
                          ? colorScheme.primary
                          : colorScheme.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.mutedForeground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isCurrent && state.durationSeconds.value > 0)
              Text(
                _formatDuration(state.durationSeconds.value),
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.primary,
                ),
              )
            else
              Icon(
                LucideIcons.cloud,
                size: 14,
                color: colorScheme.mutedForeground.withValues(alpha: 0.6),
              ),
          ],
        ),
      ),
);
  }
}

/// Bottom transport bar: transport buttons, seek bar and volume.
class _PlayerBar extends StatelessWidget {
  const _PlayerBar();

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.currentIndex.watch(context);
    state.isPlaying.watch(context);
    state.isBuffering.watch(context);
    state.shuffle.watch(context);
    state.repeatMode.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final accent = colorScheme.mutedForeground;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.border.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton.ghost(
  icon: Icon(LucideIcons.shuffle, size: 20),
  onPressed: state.toggleShuffle,
),
          const SizedBox(width: NexusSpacing.xs),
          IconButton.ghost(
  icon: const Icon(LucideIcons.skipBack),
  onPressed: state.previous,
),
          const SizedBox(width: NexusSpacing.xs),
          _PlayButton(onPressed: state.togglePlay),
          const SizedBox(width: NexusSpacing.xs),
          IconButton.ghost(
  icon: const Icon(LucideIcons.skipForward),
  onPressed: state.next,
),
          const SizedBox(width: NexusSpacing.xs),
          IconButton.ghost(
  icon: Icon(
              state.repeatMode.value == MusicRepeatMode.one
                  ? LucideIcons.repeat1
                  : LucideIcons.repeat,
              size: 20,
            ),
  onPressed: state.cycleRepeat,
),
          const SizedBox(width: NexusSpacing.md),
          const Expanded(child: _SeekBar()),
          const SizedBox(width: NexusSpacing.md),
          const _VolumeControl(),
        ],
      ),
    );
  }
}

/// Primary round play/pause button with a buffering spinner.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.isPlaying.watch(context);
    state.isBuffering.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 44,
      height: 44,
      child: GestureDetector(
  onTap: onPressed,
  child: Center(
            child: state.isBuffering.value
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primaryForeground,
                    ),
                  )
                : Icon(
                    state.isPlaying.value ? LucideIcons.pause : RadixIcons.play,
                    color: colorScheme.primaryForeground,
                    size: 26,
                  ),
          ),
),
    );
  }
}

/// Draggable seek bar with current/total time labels.
class _SeekBar extends StatefulWidget {
  const _SeekBar();

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.currentIndex.watch(context);
    state.positionSeconds.watch(context);
    state.durationSeconds.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final duration = state.durationSeconds.value;
    final position = state.positionSeconds.value;
    final enabled = state.currentTrack != null && duration > 0;
    final value = _dragValue ?? (duration > 0 ? math.min(position, duration) : 0.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 22,
          child: Slider(
            value: SliderValue.single(
              enabled ? value.clamp(0.0, duration).toDouble() : 0.0,
            ),
            max: math.max(duration, 1),
            onChanged: enabled
                ? (v) => setState(() => _dragValue = v.value)
                : null,
            onChangeEnd: enabled
                ? (v) {
                    state.seekTo(v.value);
                    setState(() => _dragValue = null);
                  }
                : null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(_dragValue ?? position),
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
            Text(
              duration > 0 ? _formatDuration(duration) : '--:--',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Compact volume slider with a mute-aware icon.
class _VolumeControl extends StatelessWidget {
  const _VolumeControl();

  @override
  Widget build(BuildContext context) {
    final state = MusicPlayerState.instance;
    state.volume.watch(context);
    final colorScheme = Theme.of(context).colorScheme;
    final value = state.volume.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          value == 0
              ? LucideIcons.volumeX
              : value < 0.5
                  ? LucideIcons.volume1
                  : LucideIcons.volume2,
          size: 18,
          color: colorScheme.mutedForeground,
        ),
        const SizedBox(width: NexusSpacing.xs),
        SizedBox(
          width: 110,
          height: 22,
          child: Slider(
            value: SliderValue.single(value),
            max: 1,
            onChanged: (v) => state.setVolume(v.value),
          ),
        ),
      ],
    );
  }
}

/// Animated three-bar indicator shown next to the playing track.
class _EqualizerIndicator extends StatefulWidget {
  const _EqualizerIndicator({this.color});

  final Color? color;

  @override
  State<_EqualizerIndicator> createState() => _EqualizerIndicatorState();
}

class _EqualizerIndicatorState extends State<_EqualizerIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = _controller.value * 2 * math.pi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : 2),
                child: Container(
                  width: 3,
                  height: 4 + 8 * (0.5 + 0.5 * math.sin(phase + i * 1.3)),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Artwork gradient palettes, cycled per playlist position.
const List<List<Color>> _artworkPalettes = [
  [Color(0xFF7F7FD5), Color(0xFF91EAE4)],
  [Color(0xFFFF6B6B), Color(0xFF556270)],
  [Color(0xFFFF9F1C), Color(0xFF2D4059)],
  [Color(0xFF00B4DB), Color(0xFF0083B0)],
  [Color(0xFFC471ED), Color(0xFFF7797D)],
  [Color(0xFF11998E), Color(0xFF38EF7D)],
  [Color(0xFFFC4A1A), Color(0xFFF7B733)],
  [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
  [Color(0xFFEE9CA7), Color(0xFFFFDDE1)],
  [Color(0xFF2193B0), Color(0xFF6DD5ED)],
];

List<Color> _paletteFor(int index) => _artworkPalettes[
    index < 0 ? 0 : index % _artworkPalettes.length];

String _formatDuration(double seconds) {
  if (seconds.isNaN || seconds < 0) seconds = 0;
  final total = seconds.round();
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final secs = total % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = secs.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String _formatPlayCount(int count) {
  if (count >= 100000000) {
    return '${(count / 100000000).toStringAsFixed(1)}亿';
  }
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万';
  }
  return count.toString();
}
