import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Текущая погода + почасовой и дневной прогноз.
class Weather {
  /// Откуда получены данные — для подписи внизу экрана.
  final String source;
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final double pressureMmHg;
  final int weatherCode;
  final bool isDay;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;

  const Weather({
    required this.source,
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.pressureMmHg,
    required this.weatherCode,
    required this.isDay,
    required this.hourly,
    required this.daily,
  });

  /// Ответ Open-Meteo.
  factory Weather.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final currentTime = DateTime.parse(current['time'] as String);

    final h = json['hourly'] as Map<String, dynamic>;
    final hourTimes = (h['time'] as List).cast<String>();
    final hourly = <HourlyForecast>[];
    for (var i = 0; i < hourTimes.length; i++) {
      final time = DateTime.parse(hourTimes[i]);
      // Берём ближайшие 24 часа, начиная с текущего.
      if (time.isBefore(currentTime.subtract(const Duration(hours: 1)))) {
        continue;
      }
      hourly.add(HourlyForecast(
        time: time,
        temperature: (h['temperature_2m'][i] as num).toDouble(),
        weatherCode: h['weather_code'][i] as int,
        isDay: h['is_day'][i] == 1,
      ));
      if (hourly.length == 24) break;
    }

    final d = json['daily'] as Map<String, dynamic>;
    final dayTimes = (d['time'] as List).cast<String>();
    final daily = [
      for (var i = 0; i < dayTimes.length; i++)
        DailyForecast(
          date: DateTime.parse(dayTimes[i]),
          minTemp: (d['temperature_2m_min'][i] as num).toDouble(),
          maxTemp: (d['temperature_2m_max'][i] as num).toDouble(),
          weatherCode: d['weather_code'][i] as int,
        ),
    ];

    return Weather(
      source: 'Open-Meteo.com',
      temperature: (current['temperature_2m'] as num).toDouble(),
      feelsLike: (current['apparent_temperature'] as num).toDouble(),
      humidity: (current['relative_humidity_2m'] as num).toInt(),
      windSpeed: (current['wind_speed_10m'] as num).toDouble(),
      // Open-Meteo отдаёт гПа, переводим в мм рт. ст.
      pressureMmHg: (current['surface_pressure'] as num).toDouble() * 0.750062,
      weatherCode: current['weather_code'] as int,
      isDay: current['is_day'] == 1,
      hourly: hourly,
      daily: daily,
    );
  }

  /// Ответ MET Norway (api.met.no, locationforecast/2.0/compact).
  /// Время в ответе — UTC, переводим в часовой пояс устройства.
  factory Weather.fromMetNo(Map<String, dynamic> json) {
    final coords = (json['geometry']['coordinates'] as List).cast<num>();
    final altitude = coords.length > 2 ? coords[2].toDouble() : 0.0;
    final series =
        (json['properties']['timeseries'] as List).cast<Map<String, dynamic>>();

    // Текущий момент — последняя точка, которая уже наступила.
    final now = DateTime.now();
    var startIndex = 0;
    for (var i = 0; i < series.length; i++) {
      if (DateTime.parse(series[i]['time'] as String).isAfter(now)) break;
      startIndex = i;
    }

    final current = series[startIndex];
    final details = current['data']['instant']['details'] as Map<String, dynamic>;
    final temperature = (details['air_temperature'] as num).toDouble();
    final humidity = (details['relative_humidity'] as num).toDouble();
    final wind = (details['wind_speed'] as num).toDouble();
    final symbol = _metNoSymbol(current);
    final currentTime = DateTime.parse(current['time'] as String).toLocal();

    final hourly = <HourlyForecast>[];
    for (final entry in series.skip(startIndex)) {
      // Почасовые данные есть только на ближайшие ~2 суток.
      if (entry['data']['next_1_hours'] == null) break;
      final time = DateTime.parse(entry['time'] as String).toLocal();
      final s = _metNoSymbol(entry);
      hourly.add(HourlyForecast(
        time: time,
        temperature:
            (entry['data']['instant']['details']['air_temperature'] as num)
                .toDouble(),
        weatherCode: _metNoToWmo(s),
        isDay: _metNoIsDay(s, time),
      ));
      if (hourly.length == 24) break;
    }

    // Дневной прогноз: min/max по всем точкам дня, иконка — ближе к полудню.
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final entry in series) {
      final t = DateTime.parse(entry['time'] as String).toLocal();
      byDay.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(entry);
    }
    final today = DateTime(now.year, now.month, now.day);
    final daily = <DailyForecast>[];
    for (final MapEntry(key: date, value: entries) in byDay.entries) {
      if (date.isBefore(today)) continue;
      final temps = entries
          .map((e) =>
              (e['data']['instant']['details']['air_temperature'] as num)
                  .toDouble())
          .toList();
      final noon = entries.reduce((a, b) {
        int dist(Map<String, dynamic> e) =>
            (DateTime.parse(e['time'] as String).toLocal().hour - 12).abs();
        return dist(b) < dist(a) && _metNoSymbol(b) != null ? b : a;
      });
      daily.add(DailyForecast(
        date: date,
        minTemp: temps.reduce(math.min),
        maxTemp: temps.reduce(math.max),
        weatherCode: _metNoToWmo(_metNoSymbol(noon)),
      ));
      if (daily.length == 7) break;
    }

    // MET Norway даёт давление на уровне моря, приводим к высоте точки,
    // чтобы цифры совпадали с Open-Meteo (surface_pressure).
    final seaLevel = (details['air_pressure_at_sea_level'] as num).toDouble();
    final surface = seaLevel *
        math.pow(
            1 - 0.0065 * altitude / (temperature + 0.0065 * altitude + 273.15),
            5.257);

    return Weather(
      source: 'MET Norway (api.met.no)',
      temperature: temperature,
      feelsLike: _apparentTemperature(temperature, humidity, wind),
      humidity: humidity.round(),
      windSpeed: wind,
      pressureMmHg: surface * 0.750062,
      weatherCode: _metNoToWmo(symbol),
      isDay: _metNoIsDay(symbol, currentTime),
      hourly: hourly,
      daily: daily,
    );
  }
}

String? _metNoSymbol(Map<String, dynamic> entry) {
  final data = entry['data'] as Map<String, dynamic>;
  for (final key in ['next_1_hours', 'next_6_hours', 'next_12_hours']) {
    final code = data[key]?['summary']?['symbol_code'] as String?;
    if (code != null) return code;
  }
  return null;
}

bool _metNoIsDay(String? symbol, DateTime localTime) {
  if (symbol != null && symbol.endsWith('_night')) return false;
  if (symbol != null && symbol.endsWith('_day')) return true;
  // У символов без суффикса (cloudy, rain…) время суток не указано.
  return localTime.hour >= 7 && localTime.hour < 20;
}

/// Символы MET Norway → WMO-коды, чтобы переиспользовать [WeatherCode].
int _metNoToWmo(String? symbol) {
  if (symbol == null) return -1;
  final s = symbol.split('_').first;
  if (s.contains('thunder')) return 95;
  return switch (s) {
    'clearsky' => 0,
    'fair' => 1,
    'partlycloudy' => 2,
    'cloudy' => 3,
    'fog' => 45,
    'lightrain' => 61,
    'rain' => 63,
    'heavyrain' => 65,
    'lightrainshowers' => 80,
    'rainshowers' => 81,
    'heavyrainshowers' => 82,
    'lightsleet' || 'lightsleetshowers' => 66,
    'sleet' || 'heavysleet' || 'sleetshowers' || 'heavysleetshowers' => 67,
    'lightsnow' => 71,
    'snow' => 73,
    'heavysnow' => 75,
    'lightsnowshowers' || 'snowshowers' => 85,
    'heavysnowshowers' => 86,
    _ => -1,
  };
}

/// «Ощущается как» по формуле Steadman (Australian Apparent Temperature).
double _apparentTemperature(double t, double rh, double wind) {
  final e = rh / 100 * 6.105 * math.exp(17.27 * t / (237.7 + t));
  return t + 0.33 * e - 0.70 * wind - 4.00;
}

class HourlyForecast {
  final DateTime time;
  final double temperature;
  final int weatherCode;
  final bool isDay;

  const HourlyForecast({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.isDay,
  });
}

class DailyForecast {
  final DateTime date;
  final double minTemp;
  final double maxTemp;
  final int weatherCode;

  const DailyForecast({
    required this.date,
    required this.minTemp,
    required this.maxTemp,
    required this.weatherCode,
  });
}

/// Расшифровка WMO-кодов погоды: https://open-meteo.com/en/docs
class WeatherCode {
  static String description(int code) => switch (code) {
        0 => 'Ясно',
        1 => 'Преимущественно ясно',
        2 => 'Переменная облачность',
        3 => 'Пасмурно',
        45 || 48 => 'Туман',
        51 || 53 || 55 => 'Морось',
        56 || 57 => 'Ледяная морось',
        61 => 'Небольшой дождь',
        63 => 'Дождь',
        65 => 'Сильный дождь',
        66 || 67 => 'Ледяной дождь',
        71 => 'Небольшой снег',
        73 => 'Снег',
        75 => 'Сильный снег',
        77 => 'Снежная крупа',
        80 || 81 || 82 => 'Ливень',
        85 || 86 => 'Снегопад',
        95 => 'Гроза',
        96 || 99 => 'Гроза с градом',
        _ => 'Неизвестно',
      };

  static IconData icon(int code, {bool isDay = true}) => switch (code) {
        0 || 1 => isDay ? Icons.wb_sunny : Icons.nightlight_round,
        2 => isDay ? Icons.wb_cloudy : Icons.nights_stay,
        3 => Icons.cloud,
        45 || 48 => Icons.foggy,
        >= 51 && <= 67 || >= 80 && <= 82 => Icons.water_drop,
        >= 71 && <= 77 || 85 || 86 => Icons.ac_unit,
        >= 95 => Icons.thunderstorm,
        _ => Icons.help_outline,
      };

  /// Цвета фона в зависимости от погоды и времени суток.
  static List<Color> gradient(int code, {bool isDay = true}) {
    if (!isDay) return const [Color(0xFF0F2027), Color(0xFF2C5364)];
    return switch (code) {
      0 || 1 => const [Color(0xFF2980B9), Color(0xFF6DD5FA)],
      2 || 3 || 45 || 48 => const [Color(0xFF606C88), Color(0xFF8E9EAB)],
      >= 71 && <= 77 || 85 || 86 => const [Color(0xFF83A4D4), Color(0xFFB6FBFF)],
      >= 95 => const [Color(0xFF232526), Color(0xFF414345)],
      _ => const [Color(0xFF3A6073), Color(0xFF16222A)],
    };
  }
}
