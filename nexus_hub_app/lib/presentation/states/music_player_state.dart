import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../data/models/music_track_model.dart';

/// Repeat behaviour of the playlist.
enum MusicRepeatMode { off, all, one }

/// Signals-backed singleton for the online music player.
///
/// Playback is delegated to an HTML5 `<audio>` element running inside a
/// headless WebView, so tracks keep streaming even after the player window
/// is closed — mirroring how macOS apps keep playing in the background.
/// The Dart side only sends control commands (play/pause/seek/volume) via
/// `evaluateJavascript` and receives progress events back through a
/// JavaScript handler.
class MusicPlayerState {
  MusicPlayerState._();

  /// The singleton instance used across the app.
  static final MusicPlayerState instance = MusicPlayerState._();

  /// Curated online playlist — royalty-free demo streams from SoundHelix.
  static const List<MusicTrack> playlist = [
    MusicTrack(
      id: 'aurora-dawn',
      title: 'Aurora Dawn',
      artist: 'SoundHelix',
      album: 'Nightfall Echoes',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    ),
    MusicTrack(
      id: 'neon-skyline',
      title: 'Neon Skyline',
      artist: 'SoundHelix',
      album: 'Nightfall Echoes',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    ),
    MusicTrack(
      id: 'midnight-drive',
      title: 'Midnight Drive',
      artist: 'SoundHelix',
      album: 'Chrome Highways',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    ),
    MusicTrack(
      id: 'emerald-tides',
      title: 'Emerald Tides',
      artist: 'SoundHelix',
      album: 'Chrome Highways',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    ),
    MusicTrack(
      id: 'solar-winds',
      title: 'Solar Winds',
      artist: 'SoundHelix',
      album: 'Distant Signals',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    ),
    MusicTrack(
      id: 'velvet-horizon',
      title: 'Velvet Horizon',
      artist: 'SoundHelix',
      album: 'Distant Signals',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    ),
    MusicTrack(
      id: 'crimson-cascade',
      title: 'Crimson Cascade',
      artist: 'SoundHelix',
      album: 'Painted Gravity',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3',
    ),
    MusicTrack(
      id: 'lunar-drift',
      title: 'Lunar Drift',
      artist: 'SoundHelix',
      album: 'Painted Gravity',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-8.mp3',
    ),
    MusicTrack(
      id: 'electric-bloom',
      title: 'Electric Bloom',
      artist: 'SoundHelix',
      album: 'Painted Gravity',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-9.mp3',
    ),
    MusicTrack(
      id: 'amber-waves',
      title: 'Amber Waves',
      artist: 'SoundHelix',
      album: 'Golden Hour',
      url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-10.mp3',
    ),
  ];

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

  MusicTrack? get currentTrack =>
      currentIndex.value >= 0 ? playlist[currentIndex.value] : null;

  HeadlessInAppWebView? _webview;
  InAppWebViewController? _controller;
  Future<void>? _boot;

  /// Boots the headless audio tab. Idempotent — the first call creates the
  /// WebView, later calls return the same future.
  Future<void> init() => _boot ??= _bootEngine();

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
    if (index < 0 || index >= playlist.length) return;
    currentIndex.value = index;
    positionSeconds.value = 0;
    durationSeconds.value = 0;
    isBuffering.value = true;
    await init();
    await _runJs("playerLoad('${playlist[index].url}')");
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
    if (playlist.isEmpty) return;
    if (shuffle.value && playlist.length > 1) {
      final random = math.Random();
      var target = currentIndex.value;
      while (target == currentIndex.value) {
        target = random.nextInt(playlist.length);
      }
      playTrack(target);
      return;
    }
    var target = currentIndex.value + delta;
    if (repeatMode.value == MusicRepeatMode.all) {
      target = (target % playlist.length + playlist.length) % playlist.length;
    } else {
      target = target.clamp(0, playlist.length - 1).toInt();
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
    switch (repeatMode.value) {
      case MusicRepeatMode.one:
        positionSeconds.value = 0;
        _runJs('playerSeek(0)');
        _runJs('playerPlay()');
      case MusicRepeatMode.all:
        next();
      case MusicRepeatMode.off:
        if (currentIndex.value < playlist.length - 1) {
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
