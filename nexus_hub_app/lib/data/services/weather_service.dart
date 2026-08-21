import 'package:dio/dio.dart';

import '../models/weather_model.dart';
import 'local_database.dart';

/// Service for fetching current weather and today's sunrise/sunset times
/// from Open-Meteo (free, no API key required).
///
/// Results are cached in Hive for [_cacheTtl] so the menu bar widget does
/// not hit the network on every rebuild.
class WeatherService {
  WeatherService({Dio? dio, this.latitude = 39.9042, this.longitude = 116.4074})
      : _dio = dio ?? Dio();

  final Dio _dio;

  /// Location used for the forecast. Defaults to Beijing; the app has no
  /// geolocation dependency, so the coordinates are fixed for now.
  final double latitude;
  final double longitude;

  static const _cacheKey = 'current_weather';
  static const _cacheTtl = Duration(minutes: 10);

  /// Returns cached weather if fresh, otherwise fetches from the web.
  Future<WeatherInfo?> fetchWeather() async {
    final cached = await _loadCached();
    if (cached != null) return cached;
    try {
      return await _fetchAndCache();
    } catch (_) {
      // Network failures must not break the menu bar; show nothing instead.
      return null;
    }
  }

  Future<WeatherInfo> _fetchAndCache() async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': latitude,
        'longitude': longitude,
        'current': 'temperature_2m,weather_code',
        'daily': 'sunrise,sunset',
        'timezone': 'auto',
        'forecast_days': 1,
      },
    );

    final data = response.data;
    if (data == null) {
      throw StateError('Empty weather response');
    }

    final current = Map<String, dynamic>.from(data['current'] as Map? ?? {});
    final daily = Map<String, dynamic>.from(data['daily'] as Map? ?? {});
    final sunriseList = (daily['sunrise'] as List?)?.cast<String>();
    final sunsetList = (daily['sunset'] as List?)?.cast<String>();

    final weather = WeatherInfo(
      temperature: (current['temperature_2m'] as num?)?.toDouble() ?? 0.0,
      weatherCode: (current['weather_code'] as num?)?.toInt() ?? 0,
      sunrise: DateTime.tryParse(_firstOrEmpty(sunriseList)) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sunset: DateTime.tryParse(_firstOrEmpty(sunsetList)) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.now(),
    );

    final box = await LocalDatabase.box('weather');
    await box.put(_cacheKey, weather.toJson());
    return weather;
  }

  /// First element of the daily list as a string, or '' when absent.
  static String _firstOrEmpty(List<String>? list) =>
      list != null && list.isNotEmpty ? list.first : '';

  Future<WeatherInfo?> _loadCached() async {
    final box = await LocalDatabase.box('weather');
    final raw = box.get(_cacheKey);
    if (raw == null) return null;

    final data = Map<String, dynamic>.from(raw as Map);
    final weather = WeatherInfo.fromJson(data);
    if (DateTime.now().difference(weather.updatedAt) > _cacheTtl) {
      return null;
    }
    return weather;
  }
}
