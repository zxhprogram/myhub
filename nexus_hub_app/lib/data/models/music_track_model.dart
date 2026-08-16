/// A single streamable track in the online music player.
class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.url,
  });

  final String id;
  final String title;
  final String artist;
  final String album;

  /// Direct HTTPS stream played by the embedded browser audio engine.
  final String url;
}
