import 'dart:async';
import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/music_playlist_model.dart';
import '../../data/models/music_track_model.dart';
import '../../data/services/music_service.dart';

/// Repeat behaviour of the playlist.
enum MusicRepeatMode { off, all, one }

/// High-level view mode shown in the playlist pane.
enum MusicBrowseMode { playlists, search }

/// Signals-backed singleton for the online music player.
///
/// Playback runs on a media_kit (libmpv) [Player] — no browser engine is
/// involved, and tracks keep streaming even after the player window is
/// closed. Track [MusicTrack.url] values are meting endpoints that
/// redirect (302) to the netease CDN, which only serves requests carrying
/// the mu-jie.cc site Referer (no Referer or any other domain gets a
/// 403), so every track is opened with explicit [_audioHeaders].
///
/// Track data is sourced from the mu-jie.cc musicBox API.
class MusicPlayerState {
  MusicPlayerState._();

  /// The singleton instance used across the app.
  static final MusicPlayerState instance = MusicPlayerState._();

  final MusicService _service = MusicService();

  /// The currently loaded track list (empty until a playlist or search
  /// result is loaded).
  final playlist = signal<List<MusicTrack>>(const []);

  /// Name of the currently loaded playlist or search result set.
  final playlistTitle = signal<String>('');

  /// Recommended playlists shown in the browse pane.
  final recommendPlaylists = signal<List<MusicPlaylist>>(const []);

  /// Whether the playlist pane is showing recommended playlists or
  /// search results.
  final browseMode = signal<MusicBrowseMode>(MusicBrowseMode.playlists);

  /// Search results for playlists.
  final searchPlaylistResults = signal<List<MusicPlaylist>>(const []);

  /// Whether a browse-pane operation (load recommends / search) is running.
  final isBrowseLoading = signal<bool>(false);

  /// Whether a track-list load is in progress.
  final isPlaylistLoading = signal<bool>(false);

  /// Error message from the last failed operation, cleared on success.
  final errorMessage = signal<String?>(null);

  /// Index of the loaded track in [playlist], `-1` before the first play.
  final currentIndex = signal<int>(-1);

  /// Whether audio is currently being produced.
  final isPlaying = signal<bool>(false);

  /// Whether the stream is buffering (loading more audio data).
  final isBuffering = signal<bool>(false);

  /// Playback head of the loaded track, in seconds.
  final positionSeconds = signal<double>(0);

  /// Total length of the loaded track, in seconds (0 until reported).
  final durationSeconds = signal<double>(0);

  /// Output volume in the 0..1 range.
  final volume = signal<double>(0.8);

  /// Whether track order is shuffled when skipping forward.
  final shuffle = signal<bool>(false);

  /// Playlist repeat behaviour.
  final repeatMode = signal<MusicRepeatMode>(MusicRepeatMode.off);

  MusicTrack? get currentTrack {
    final idx = currentIndex.value;
    final list = playlist.value;
    return idx >= 0 && idx < list.length ? list[idx] : null;
  }

  Player? _player;
  Future<void>? _boot;
  final List<StreamSubscription<void>> _subscriptions = [];
  Timer? _loadWatchdog;

  /// Headers required by the stream CDN — without the mu-jie.cc Referer
  /// every audio request is answered with HTTP 403.
  static const Map<String, String> _audioHeaders = {
    'Referer': 'https://mu-jie.cc/musicBox/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
  };

  /// Boots the audio engine. Idempotent — the first call creates the
  /// [Player], later calls return the same future.
  Future<void> init() => _boot ??= _bootEngine();

  /// Loads recommended playlists from the API. Called once when the music
  /// page is first opened.
  Future<void> loadRecommendPlaylists() async {
    if (isBrowseLoading.value) return;
    isBrowseLoading.value = true;
    errorMessage.value = null;
    try {
      final result = await _service.getRecommendPlaylists();
      recommendPlaylists.value = result;
      browseMode.value = MusicBrowseMode.playlists;
    } catch (e) {
      errorMessage.value = '加载推荐歌单失败: $e';
    } finally {
      isBrowseLoading.value = false;
    }
  }

  /// Searches for playlists by keyword.
  Future<void> searchPlaylists(String keywords) async {
    if (keywords.trim().isEmpty) return;
    isBrowseLoading.value = true;
    errorMessage.value = null;
    try {
      final result = await _service.searchPlaylists(keywords);
      searchPlaylistResults.value = result;
      browseMode.value = MusicBrowseMode.search;
    } catch (e) {
      errorMessage.value = '搜索歌单失败: $e';
    } finally {
      isBrowseLoading.value = false;
    }
  }

  /// Searches for songs by keyword and loads the results as the active
  /// playlist.
  Future<void> searchSongs(String keywords) async {
    if (keywords.trim().isEmpty) return;
    isPlaylistLoading.value = true;
    errorMessage.value = null;
    try {
      final result = await _service.searchSongs(keywords);
      playlist.value = result;
      playlistTitle.value = '搜索: $keywords';
      currentIndex.value = -1;
      isPlaying.value = false;
      isBuffering.value = false;
      positionSeconds.value = 0;
      durationSeconds.value = 0;
    } catch (e) {
      errorMessage.value = '搜索歌曲失败: $e';
    } finally {
      isPlaylistLoading.value = false;
    }
  }

  /// Loads a playlist's track list and makes it the active playlist.
  Future<void> loadPlaylist(MusicPlaylist plist) async {
    isPlaylistLoading.value = true;
    errorMessage.value = null;
    try {
      final detail = await _service.getPlaylistDetail(plist.id);
      playlist.value = detail.tracks;
      playlistTitle.value = detail.name;
      currentIndex.value = -1;
      isPlaying.value = false;
      isBuffering.value = false;
      positionSeconds.value = 0;
      durationSeconds.value = 0;
    } catch (e) {
      errorMessage.value = '加载歌单失败: $e';
    } finally {
      isPlaylistLoading.value = false;
    }
  }

  Future<void> _bootEngine() async {
    final player = Player();
    _player = player;
    await player.setVolume(volume.value * 100);
    _subscriptions.addAll([
      player.stream.playing.listen((value) {
        isPlaying.value = value;
        if (value) {
          isBuffering.value = false;
          _loadWatchdog?.cancel();
        }
      }),
      player.stream.buffering.listen((value) => isBuffering.value = value),
      player.stream.position.listen((position) {
        if (position > Duration.zero) _loadWatchdog?.cancel();
        positionSeconds.value = position.inMilliseconds / 1000;
      }),
      player.stream.duration.listen((duration) {
        final seconds = duration.inMilliseconds / 1000;
        if (seconds > 0) {
          durationSeconds.value = seconds;
          _loadWatchdog?.cancel();
        }
      }),
      player.stream.completed.listen((completed) {
        if (completed) _handleTrackEnded();
      }),
      player.stream.error.listen((_) => _handleLoadFailure()),
    ]);
  }

  /// Starts streaming [index], replacing whatever was playing.
  Future<void> playTrack(int index) async {
    final list = playlist.value;
    if (index < 0 || index >= list.length) return;
    currentIndex.value = index;
    positionSeconds.value = 0;
    durationSeconds.value = 0;
    isBuffering.value = true;
    errorMessage.value = null;
    await init();
    // libmpv reports some load failures only through its log (surfaced
    // as error-stream events), but a few fail silently — watch for the
    // first sign of life and treat its absence as a failed load.
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(const Duration(seconds: 15), _handleLoadFailure);
    await _player?.open(
      Media(list[index].url, httpHeaders: _audioHeaders),
    );
  }

  /// Plays the first track when nothing is loaded, otherwise toggles
  /// between play and pause.
  void togglePlay() {
    if (currentTrack == null) {
      playTrack(0);
      return;
    }
    if (isPlaying.value) {
      _player?.pause();
    } else {
      _player?.play();
    }
  }

  /// Advances to the next track (shuffled when [shuffle] is on).
  void next() => _skip(1);

  /// Goes back one track, or restarts the current one when it is well
  /// under way — the usual jukebox behaviour.
  void previous() {
    if (positionSeconds.value > 3) {
      seekTo(0);
      return;
    }
    _skip(-1);
  }

  void _skip(int delta) {
    final list = playlist.value;
    if (list.isEmpty) return;
    if (shuffle.value && list.length > 1) {
      final random = math.Random();
      var target = currentIndex.value;
      while (target == currentIndex.value) {
        target = random.nextInt(list.length);
      }
      playTrack(target);
      return;
    }
    var target = currentIndex.value + delta;
    if (repeatMode.value == MusicRepeatMode.all) {
      target = (target % list.length + list.length) % list.length;
    } else {
      target = target.clamp(0, list.length - 1).toInt();
      if (target == currentIndex.value) return; // already at the edge
    }
    playTrack(target);
  }

  /// Moves the playback head to [seconds] within the loaded track.
  void seekTo(double seconds) {
    positionSeconds.value = seconds;
    _player?.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  /// Sets the output volume in the 0..1 range.
  void setVolume(double value) {
    volume.value = value.clamp(0.0, 1.0).toDouble();
    _player?.setVolume(volume.value * 100);
  }

  void toggleShuffle() => shuffle.value = !shuffle.value;

  void cycleRepeat() {
    repeatMode.value = switch (repeatMode.value) {
      MusicRepeatMode.off => MusicRepeatMode.all,
      MusicRepeatMode.all => MusicRepeatMode.one,
      MusicRepeatMode.one => MusicRepeatMode.off,
    };
  }

  /// Stops the audio engine and releases the player.
  Future<void> disposeEngine() async {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    _player = null;
    _boot = null;
    await player?.dispose();
    isPlaying.value = false;
    isBuffering.value = false;
  }

  void _handleTrackEnded() {
    final list = playlist.value;
    switch (repeatMode.value) {
      case MusicRepeatMode.one:
        positionSeconds.value = 0;
        _player?.seek(Duration.zero);
        _player?.play();
      case MusicRepeatMode.all:
        next();
      case MusicRepeatMode.off:
        if (currentIndex.value < list.length - 1) {
          next();
        } else {
          isPlaying.value = false;
          isBuffering.value = false;
        }
    }
  }

  /// Marks the current track as unloadable. Only reacts while the track
  /// never produced audio (mid-playback hiccups are left to libmpv's own
  /// recovery, matching the silent stall of a dropped stream).
  void _handleLoadFailure() {
    _loadWatchdog?.cancel();
    if (durationSeconds.value > 0 || positionSeconds.value > 0) return;
    isPlaying.value = false;
    isBuffering.value = false;
    errorMessage.value = '音频加载失败，该歌曲可能暂时不可用';
  }
}
