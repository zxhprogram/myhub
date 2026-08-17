/// A single streamable track in the online music player.
class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.url,
    this.pic = '',
    this.lrc = '',
  });

  /// Unique identifier from the source API (e.g. netease song id).
  final String id;
  final String title;
  final String artist;
  final String album;

  /// Direct stream URL played by the embedded browser audio engine.
  ///
  /// For the mu-jie.cc musicBox API this is a meting endpoint URL that
  /// redirects (302) to the real audio CDN when requested with an audio
  /// `Accept` header — the headless WebView's `<audio>` element does this
  /// automatically.
  final String url;

  /// Cover-art image URL, empty when not provided by the source.
  final String pic;

  /// Lyrics endpoint URL, empty when not provided.
  final String lrc;

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: (json['id'] ?? '').toString(),
      title: (json['name'] ?? '') as String,
      artist: (json['artist'] ?? '') as String,
      album: (json['album'] ?? '') as String,
      url: (json['url'] ?? '') as String,
      pic: (json['pic'] ?? '') as String,
      lrc: (json['lrc'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': title,
        'artist': artist,
        'album': album,
        'url': url,
        'pic': pic,
        'lrc': lrc,
      };
}
