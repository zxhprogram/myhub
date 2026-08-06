import 'package:dio/dio.dart';

import '../models/wallpaper_item.dart';

/// Fetches wallpapers from the Bing daily wallpaper API.
///
/// The endpoint needs no API key and is fast and reachable from mainland
/// China, which is why it is preferred over Pexels/Unsplash (both require a
/// key) and Lorem Picsum (unreliable from this network).
class WallpaperService {
  static const _baseUrl = 'https://www.bing.com';
  static const _apiPath = '/HPImageArchive.aspx';

  final Dio _dio;

  WallpaperService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                responseType: ResponseType.json,
              ),
            );

  /// Returns the most recent [count] Bing daily wallpapers (newest first).
  Future<List<WallpaperItem>> fetchRecent({int count = 8}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      _apiPath,
      queryParameters: {'format': 'js', 'idx': 0, 'n': count},
    );
    final images = response.data?['images'] as List<dynamic>? ?? const [];
    return images
        .whereType<Map<String, dynamic>>()
        .map(WallpaperItem.fromBingJson)
        .toList();
  }
}
