import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../layout/page_scaffold.dart';
import '../states/music_player_state.dart';

/// Online music player page.
///
/// A macOS Music-style layout: a now-playing panel with generated artwork on
/// the left, the streaming playlist on the right and a transport bar with
/// seek/volume controls along the bottom. Audio keeps streaming while the
/// desktop window is closed because the engine lives in [MusicPlayerState].
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
                'Stream the SoundHelix demo playlist online',
                style: NexusTypography.bodyMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
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
              color: colorScheme.secondaryContainer,
              borderRadius: NexusRadii.fullRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 14,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: NexusSpacing.xs),
                Text(
                  'Streaming',
                  style: NexusTypography.labelMd.copyWith(
                    color: colorScheme.onSecondaryContainer,
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
                          Expanded(child: _PlaylistView()),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          _NowPlayingPanel(),
                          _PlaylistDivider(),
                          Expanded(child: _PlaylistView()),
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
      ).colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }
}

/// Gradient artwork generated from the track position in the playlist.
class _Artwork extends StatelessWidget {
  const _Artwork({required this.palette, this.iconSize = 44});

  final List<Color> palette;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        child: Icon(Icons.music_note, color: Colors.white70, size: iconSize),
      ),
    );
  }
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
              Icons.album_outlined,
              size: 72,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: NexusSpacing.md),
            Text(
              'Pick a track to start listening',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.onSurfaceVariant,
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
              child: _Artwork(palette: _paletteFor(state.currentIndex.value)),
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
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: NexusSpacing.xs),
            Text(
              track.album,
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurfaceVariant,
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
              Icons.album_outlined,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(width: NexusSpacing.sm),
            Text(
              'Pick a track below to start listening',
              style: NexusTypography.bodyMd.copyWith(
                color: colorScheme.onSurfaceVariant,
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
                  '${track.artist} · ${track.album}',
                  style: NexusTypography.bodyMd.copyWith(
                    color: colorScheme.onSurfaceVariant,
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

/// Scrollable list of the tracks in the playlist.
class _PlaylistView extends StatelessWidget {
  const _PlaylistView();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
              Text(
                'Up Next',
                style: NexusTypography.labelMd.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${MusicPlayerState.playlist.length} tracks · online',
                style: NexusTypography.labelMd.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: NexusSpacing.sm),
            itemCount: MusicPlayerState.playlist.length,
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
    final track = MusicPlayerState.playlist[index];
    final isCurrent = state.currentIndex.value == index;
    return InkWell(
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
                              : colorScheme.onSurfaceVariant,
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
                          : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: NexusTypography.labelMd.copyWith(
                      color: colorScheme.onSurfaceVariant,
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
                Icons.cloud_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
    final accent = colorScheme.onSurfaceVariant;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: NexusSpacing.sm,
        vertical: NexusSpacing.sm,
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.shuffle, size: 20),
            tooltip: 'Shuffle',
            color: state.shuffle.value ? colorScheme.primary : accent,
            onPressed: state.toggleShuffle,
          ),
          const SizedBox(width: NexusSpacing.xs),
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: 'Previous',
            color: accent,
            onPressed: state.previous,
          ),
          const SizedBox(width: NexusSpacing.xs),
          _PlayButton(onPressed: state.togglePlay),
          const SizedBox(width: NexusSpacing.xs),
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Next',
            color: accent,
            onPressed: state.next,
          ),
          const SizedBox(width: NexusSpacing.xs),
          IconButton(
            icon: Icon(
              state.repeatMode.value == MusicRepeatMode.one
                  ? Icons.repeat_one
                  : Icons.repeat,
              size: 20,
            ),
            tooltip: switch (state.repeatMode.value) {
              MusicRepeatMode.off => 'Repeat off',
              MusicRepeatMode.all => 'Repeat all',
              MusicRepeatMode.one => 'Repeat one',
            },
            color: state.repeatMode.value == MusicRepeatMode.off
                ? accent
                : colorScheme.primary,
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
      child: Material(
        color: colorScheme.primary,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Center(
            child: state.isBuffering.value
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Icon(
                    state.isPlaying.value ? Icons.pause : Icons.play_arrow,
                    color: colorScheme.onPrimary,
                    size: 26,
                  ),
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
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: enabled ? value.clamp(0.0, duration).toDouble() : 0.0,
              max: math.max(duration, 1),
              onChanged: enabled
                  ? (v) => setState(() => _dragValue = v)
                  : null,
              onChangeEnd: enabled
                  ? (v) {
                      state.seekTo(v);
                      setState(() => _dragValue = null);
                    }
                  : null,
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDuration(_dragValue ?? position),
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              duration > 0 ? _formatDuration(duration) : '--:--',
              style: NexusTypography.labelMd.copyWith(
                color: colorScheme.onSurfaceVariant,
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
              ? Icons.volume_off
              : value < 0.5
                  ? Icons.volume_down
                  : Icons.volume_up,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: NexusSpacing.xs),
        SizedBox(
          width: 110,
          height: 22,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value,
              max: 1,
              onChanged: state.setVolume,
            ),
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
