import 'package:dio/dio.dart';

import '../models/music_playlist_model.dart';
import '../models/music_track_model.dart';

/// Music source server identifier used by the mu-jie.cc musicBox API.
///
/// Only `netease` is currently operational; other servers have been
/// deprecated by the upstream API.
enum MusicServer {
  netease('netease');

  const MusicServer(this.id);
  final String id;
}

/// Service that talks to the mu-jie.cc musicBox API (`fy-musicbox-api`).
///
/// The API is a meting-style music aggregator. Song stream URLs are
/// meting endpoints that redirect (302) to the real CDN audio. The CDN
/// only serves requests carrying the mu-jie.cc site Referer (any other
/// value — including none — gets a 403), which the music player engine
/// adds via per-media HTTP headers.
class MusicService {
  MusicService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'Referer': 'https://mu-jie.cc/musicBox/',
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/125.0.0.0 Safari/537.36',
                },
              ),
            );

  final Dio _dio;

  static const _baseUrl = 'https://fy-musicbox-api.mu-jie.cc';

  /// Searches for songs matching [keywords].
  ///
  /// [pn] is the 1-based page number, [limit] the page size.
  Future<List<MusicTrack>> searchSongs(
    String keywords, {
    MusicServer server = MusicServer.netease,
    int pn = 1,
    int limit = 30,
  }) async {
    if (keywords.trim().isEmpty) return const [];
    final response = await _dio.get<List<dynamic>>(
      '/${server.id}/search/song/',
      queryParameters: {
        'keywords': keywords,
        'pn': pn,
        'limit': limit,
      },
    );
    final list = response.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicTrack.fromJson)
        .where((t) => t.url.isNotEmpty)
        .toList();
  }

  /// Searches for playlists matching [keywords].
  Future<List<MusicPlaylist>> searchPlaylists(
    String keywords, {
    MusicServer server = MusicServer.netease,
    int limit = 20,
  }) async {
    if (keywords.trim().isEmpty) return const [];
    final response = await _dio.get<List<dynamic>>(
      '/${server.id}/search/playlist/',
      queryParameters: {
        'keywords': keywords,
        'limit': limit,
      },
    );
    final list = response.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicPlaylist.fromJson)
        .toList();
  }

  /// Returns recommended playlists for the given server.
  Future<List<MusicPlaylist>> getRecommendPlaylists({
    MusicServer server = MusicServer.netease,
    int limit = 30,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/${server.id}/playlist/recommend',
      queryParameters: {'limit': limit},
    );
    final list = response.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(MusicPlaylist.fromJson)
        .toList();
  }

  /// Fetches the full track list of a playlist.
  Future<MusicPlaylistDetail> getPlaylistDetail(
    String playlistId, {
    MusicServer server = MusicServer.netease,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/meting/',
      queryParameters: {
        'server': server.id,
        'type': 'playlist',
        'id': playlistId,
      },
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Empty playlist response',
      );
    }
    return MusicPlaylistDetail.fromJson(data);
  }
}
