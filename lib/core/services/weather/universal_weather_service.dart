import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cross-platform weather fetcher using Open-Meteo public API (no API key required).
class UniversalWeatherService {
  UniversalWeatherService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<Map<String, dynamic>> getWeather({
    required String location,
    double? latitude,
    double? longitude,
  }) async {
    final cleanLocation = location.trim();
    double? lat = latitude;
    double? lon = longitude;
    String placeName = cleanLocation;
    String? adminArea;
    String? country;

    // 1. Geocode if lat/lon not supplied
    if (lat == null || lon == null) {
      if (cleanLocation.isEmpty) {
        return {
          'error': 'missing_location',
          'message': 'Location or coordinates required.',
        };
      }

      final geoUri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(cleanLocation)}&count=1&language=en&format=json',
      );

      final geoResp = await _client
          .get(geoUri)
          .timeout(const Duration(seconds: 8));
      if (geoResp.statusCode != 200) {
        return {
          'error': 'geocode_failed',
          'message': 'Failed to resolve location: $cleanLocation',
        };
      }

      final geoData = jsonDecode(geoResp.body) as Map<String, dynamic>;
      final results = (geoData['results'] as List?) ?? const <dynamic>[];
      if (results.isEmpty) {
        return {
          'error': 'location_not_found',
          'message': 'Location "$cleanLocation" not found.',
        };
      }

      final top = results.first as Map<String, dynamic>;
      lat = (top['latitude'] as num).toDouble();
      lon = (top['longitude'] as num).toDouble();
      placeName = (top['name'] ?? cleanLocation).toString();
      adminArea = top['admin1']?.toString();
      country = top['country']?.toString();
    }

    // 2. Fetch forecast
    final forecastUri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m'
      '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
      '&timezone=auto',
    );

    final resp = await _client
        .get(forecastUri)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      return {
        'error': 'weather_fetch_failed',
        'message': 'Weather service error: ${resp.statusCode}',
      };
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final current = data['current'] as Map<String, dynamic>? ?? {};
    final daily = data['daily'] as Map<String, dynamic>? ?? {};

    final tempC = (current['temperature_2m'] as num?)?.toDouble();
    final apparentC = (current['apparent_temperature'] as num?)?.toDouble();
    final wmoCode = (current['weather_code'] as num?)?.toInt() ?? 0;
    final condition = _wmoDescription(wmoCode);
    final wind = (current['wind_speed_10m'] as num?)?.toDouble();
    final humidity = (current['relative_humidity_2m'] as num?)?.toDouble();

    final precipProbs =
        (daily['precipitation_probability_max'] as List?) ?? const <dynamic>[];
    final precipChance = precipProbs.isNotEmpty && precipProbs.first is num
        ? (precipProbs.first as num).toDouble() / 100.0
        : 0.0;

    return {
      'attribution': {
        'serviceName': 'Open-Meteo',
        'legalPageUrl': 'https://open-meteo.com',
        'displayText': 'Weather data from Open-Meteo',
      },
      'place': {
        'locality': placeName,
        if (adminArea != null) 'administrativeArea': adminArea,
        if (country != null) 'country': country,
      },
      'current': {
        'condition': condition,
        'temperature_c': tempC,
        'apparent_temperature_c': apparentC,
        'precipitation_chance': precipChance,
        'humidity_percent': humidity,
        'wind_speed_kmh': wind,
      },
    };
  }

  static String _wmoDescription(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
        return 'Mainly clear';
      case 2:
        return 'Partly cloudy';
      case 3:
        return 'Overcast';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
        return 'Rain';
      case 66:
      case 67:
        return 'Freezing rain';
      case 71:
      case 73:
      case 75:
        return 'Snowfall';
      case 77:
        return 'Snow grains';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
        return 'Thunderstorm';
      case 96:
      case 99:
        return 'Thunderstorm with hail';
      default:
        return 'Fair';
    }
  }
}
