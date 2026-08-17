import 'music_track_model.dart';

/// Summary of a playlist returned by the recommend / search endpoints.
class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.server,
    this.coverImgUrl = '',
    this.trackCount = 0,
    this.playCount = 0,
  });

  /// Playlist identifier on the source server (e.g. netease).
  final String id;
  final String name;
  final String server;
  final String coverImgUrl;
  final int trackCount;
  final int playCount;

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) {
    return MusicPlaylist(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '') as String,
      server: (json['server'] ?? 'netease') as String,
      coverImgUrl: (json['coverImgUrl'] ?? '') as String,
      trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Full playlist detail including the track list.
class MusicPlaylistDetail {
  const MusicPlaylistDetail({
    required this.name,
    required this.server,
    required this.tracks,
    this.coverImgUrl = '',
    this.description = '',
    this.tags = const [],
    this.playCount = 0,
  });

  final String name;
  final String server;
  final List<MusicTrack> tracks;
  final String coverImgUrl;
  final String description;
  final List<String> tags;
  final int playCount;

  factory MusicPlaylistDetail.fromJson(Map<String, dynamic> json) {
    final rawTracks = json['tracks'] as List<dynamic>? ?? const [];
    return MusicPlaylistDetail(
      name: (json['name'] ?? '') as String,
      server: (json['server'] ?? 'netease') as String,
      tracks: rawTracks
          .whereType<Map<String, dynamic>>()
          .map(MusicTrack.fromJson)
          .toList(),
      coverImgUrl: (json['coverImgUrl'] ?? '') as String,
      description: (json['description'] ?? '') as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      playCount: (json['playCount'] as num?)?.toInt() ?? 0,
    );
  }
}
