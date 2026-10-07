import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/weather.dart';

class WeatherException implements Exception {
  final String message;
  const WeatherException(this.message);

  @override
  String toString() => message;
}

/// Работа с внешними API из списка https://github.com/public-apis/public-apis:
///  * Open-Meteo (раздел Weather) — основной источник погоды, без API-ключа;
///  * MET Norway (раздел Weather) — запасной источник: у части российских
///    провайдеров Open-Meteo недоступен (хостинг Hetzner блокируется);
///  * Nominatim / OpenStreetMap (раздел Geocoding) — название города по координатам.
class WeatherService {
  // Сервисы MET Norway и Nominatim требуют идентифицирующий User-Agent.
  static const _userAgent =
      'flutter_weather_app/1.0 github.com/public-apis/public-apis';

  final http.Client _client;

  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  Future<Weather> fetchWeather(double lat, double lon) async {
    try {
      return await _fetchOpenMeteo(lat, lon);
    } catch (_) {
      try {
        return await _fetchMetNo(lat, lon);
      } on TimeoutException {
        throw const WeatherException(
            'Серверы погоды не отвечают. Проверьте подключение к интернету '
            'или попробуйте через Wi-Fi.');
      } on http.ClientException {
        throw const WeatherException(
            'Нет связи с серверами погоды. Проверьте подключение к интернету '
            'или попробуйте через Wi-Fi.');
      } catch (_) {
        throw const WeatherException('Не удалось загрузить погоду.');
      }
    }
  }

  Future<Weather> _fetchOpenMeteo(double lat, double lon) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lon',
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'is_day,weather_code,wind_speed_10m,surface_pressure',
      'hourly': 'temperature_2m,weather_code,is_day',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
      'wind_speed_unit': 'ms',
      'timezone': 'auto',
      'forecast_days': '7',
    });

    // Короткий таймаут: если сервер заблокирован, быстрее уходим на запасной.
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw WeatherException('Open-Meteo: код ${response.statusCode}');
    }
    return Weather.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Weather> _fetchMetNo(double lat, double lon) async {
    final uri = Uri.https(
        'api.met.no', '/weatherapi/locationforecast/2.0/compact', {
      // API принимает не более 4 знаков после запятой.
      'lat': lat.toStringAsFixed(4),
      'lon': lon.toStringAsFixed(4),
    });

    final response = await _client
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw WeatherException('MET Norway: код ${response.statusCode}');
    }
    return Weather.fromMetNo(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Возвращает название населённого пункта или null, если определить не удалось.
  Future<String?> fetchCityName(double lat, double lon) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '$lat',
      'lon': '$lon',
      'zoom': '10',
      'accept-language': 'ru',
    });

    try {
      final response = await _client
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final address = json['address'] as Map<String, dynamic>?;
      if (address == null) return null;
      return (address['city'] ??
              address['town'] ??
              address['village'] ??
              address['municipality'] ??
              address['county'] ??
              address['state']) as String?;
    } catch (_) {
      return null;
    }
  }
}
