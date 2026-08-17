import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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
/// Playback is delegated to an HTML5 `<audio>` element running inside a
/// headless WebView, so tracks keep streaming even after the player window
/// is closed — mirroring how macOS apps keep playing in the background.
/// The Dart side only sends control commands (play/pause/seek/volume) via
/// `evaluateJavascript` and receives progress events back through a
/// JavaScript handler.
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

  HeadlessInAppWebView? _webview;
  InAppWebViewController? _controller;
  Future<void>? _boot;

  /// Boots the headless audio tab. Idempotent — the first call creates the
  /// WebView, later calls return the same future.
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
    final pageReady = Completer<void>();
    final webview = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(data: _audioHtml),
      initialSettings: InAppWebViewSettings(
        // The Flutter play button is the user gesture; the audio element
        // itself never receives one, so it must not require it.
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        controller.addJavaScriptHandler(
          handlerName: 'audioEvent',
          callback: (args) => _onAudioEvent(args),
        );
      },
      onLoadStop: (_, _) {
        if (!pageReady.isCompleted) pageReady.complete();
      },
    );
    _webview = webview;
    await webview.run();
    // Give the audio page a moment to load; on timeout the first command
    // simply retries when the user interacts again.
    await pageReady.future.timeout(const Duration(seconds: 5), onTimeout: () {});
  }

  /// Starts streaming [index], replacing whatever was playing.
  Future<void> playTrack(int index) async {
    final list = playlist.value;
    if (index < 0 || index >= list.length) return;
    currentIndex.value = index;
    positionSeconds.value = 0;
    durationSeconds.value = 0;
    isBuffering.value = true;
    await init();
    await _runJs("playerLoad('${list[index].url}')");
    await _runJs('playerSetVolume(${volume.value})');
  }

  /// Plays the first track when nothing is loaded, otherwise toggles
  /// between play and pause.
  void togglePlay() {
    if (currentTrack == null) {
      playTrack(0);
      return;
    }
    if (isPlaying.value) {
      _runJs('playerPause()');
    } else {
      _runJs('playerPlay()');
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
    _runJs('playerSeek($seconds)');
  }

  /// Sets the output volume in the 0..1 range.
  void setVolume(double value) {
    volume.value = value.clamp(0.0, 1.0).toDouble();
    _runJs('playerSetVolume(${volume.value})');
  }

  void toggleShuffle() => shuffle.value = !shuffle.value;

  void cycleRepeat() {
    repeatMode.value = switch (repeatMode.value) {
      MusicRepeatMode.off => MusicRepeatMode.all,
      MusicRepeatMode.all => MusicRepeatMode.one,
      MusicRepeatMode.one => MusicRepeatMode.off,
    };
  }

  /// Stops the audio engine and releases the headless browser tab.
  Future<void> disposeEngine() async {
    await _webview?.dispose();
    _webview = null;
    _controller = null;
    _boot = null;
    isPlaying.value = false;
    isBuffering.value = false;
  }

  void _handleTrackEnded() {
    final list = playlist.value;
    switch (repeatMode.value) {
      case MusicRepeatMode.one:
        positionSeconds.value = 0;
        _runJs('playerSeek(0)');
        _runJs('playerPlay()');
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

  /// Decodes progress reports coming from the audio element.
  void _onAudioEvent(List<dynamic> args) {
    if (args.isEmpty) return;
    final Map<String, dynamic> event;
    try {
      event = jsonDecode(args.first.toString()) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final name = event['event'] as String?;
    final currentTime =
        (event['currentTime'] as num?)?.toDouble() ?? positionSeconds.value;
    final duration =
        (event['duration'] as num?)?.toDouble() ?? durationSeconds.value;
    switch (name) {
      case 'timeupdate':
        positionSeconds.value = currentTime;
      case 'durationchange':
        if (duration > 0) durationSeconds.value = duration;
      case 'play' || 'playing':
        isPlaying.value = true;
        isBuffering.value = false;
      case 'pause':
        isPlaying.value = false;
      case 'waiting' || 'loadstart':
        isBuffering.value = true;
      case 'ended':
        _handleTrackEnded();
      case 'error':
        isPlaying.value = false;
        isBuffering.value = false;
    }
  }

  Future<void> _runJs(String source) async {
    try {
      await _controller?.evaluateJavascript(source: source);
    } catch (_) {
      // The audio tab may not be ready yet; the next command retries.
    }
  }

  /// Minimal page hosting the audio element and its control bridge.
  static const String _audioHtml = '''
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
<audio id="player" preload="auto"></audio>
<script>
(function() {
  var player = document.getElementById('player');
  function send(event) {
    try {
      window.flutter_inappwebview.callHandler('audioEvent', JSON.stringify({
        event: event,
        currentTime: player.currentTime || 0,
        duration: isFinite(player.duration) ? player.duration : 0
      }));
    } catch (e) { /* bridge not ready yet */ }
  }
  ['timeupdate', 'durationchange', 'play', 'pause', 'waiting', 'playing',
   'loadstart', 'ended', 'error'].forEach(function(evt) {
    player.addEventListener(evt, function() { send(evt); });
  });
  window.playerLoad = function(url) {
    player.src = url;
    var p = player.play();
    if (p && p.catch) p.catch(function() {});
  };
  window.playerPlay = function() {
    var p = player.play();
    if (p && p.catch) p.catch(function() {});
  };
  window.playerPause = function() { player.pause(); };
  window.playerSeek = function(t) { try { player.currentTime = t; } catch (e) {} };
  window.playerSetVolume = function(v) { try { player.volume = v; } catch (e) {} };
})();
</script>
</body>
</html>
''';
}
