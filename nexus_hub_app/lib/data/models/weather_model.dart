/// Current weather snapshot shown in the desktop menu bar.
class WeatherInfo {
  const WeatherInfo({
    required this.temperature,
    required this.weatherCode,
    required this.sunrise,
    required this.sunset,
    required this.updatedAt,
  });

  /// Current air temperature in degrees Celsius.
  final double temperature;

  /// WMO weather interpretation code returned by Open-Meteo
  /// (0 = clear sky, 61 = light rain, 71 = snow, 95 = thunderstorm, ...).
  final int weatherCode;

  /// Local sunrise time of today.
  final DateTime sunrise;

  /// Local sunset time of today.
  final DateTime sunset;

  /// When this snapshot was fetched.
  final DateTime updatedAt;

  factory WeatherInfo.fromJson(Map<String, dynamic> json) => WeatherInfo(
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
        weatherCode: (json['weather_code'] as num?)?.toInt() ?? 0,
        sunrise: DateTime.tryParse(json['sunrise'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        sunset: DateTime.tryParse(json['sunset'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'weather_code': weatherCode,
        'sunrise': sunrise.toIso8601String(),
        'sunset': sunset.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
