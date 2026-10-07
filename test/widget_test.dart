import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_2/models/weather.dart';

void main() {
  test('Weather.fromJson разбирает ответ Open-Meteo', () {
    final weather = Weather.fromJson({
      'current': {
        'time': '2026-10-07T12:00',
        'temperature_2m': 12.4,
        'relative_humidity_2m': 70,
        'apparent_temperature': 10.1,
        'is_day': 1,
        'weather_code': 3,
        'wind_speed_10m': 4.2,
        'surface_pressure': 1013.0,
      },
      'hourly': {
        'time': ['2026-10-07T10:00', '2026-10-07T11:00', '2026-10-07T12:00'],
        'temperature_2m': [10.0, 11.0, 12.4],
        'weather_code': [0, 2, 3],
        'is_day': [1, 1, 1],
      },
      'daily': {
        'time': ['2026-10-07', '2026-10-08'],
        'weather_code': [3, 61],
        'temperature_2m_max': [14.0, 11.5],
        'temperature_2m_min': [6.0, 5.2],
      },
    });

    expect(weather.temperature, 12.4);
    expect(weather.pressureMmHg.round(), 760);
    expect(weather.hourly.map((h) => h.time.hour), [11, 12]);
    expect(weather.daily.length, 2);
    expect(WeatherCode.description(weather.daily[1].weatherCode),
        'Небольшой дождь');
  });

  test('Weather.fromMetNo разбирает ответ MET Norway', () {
    final start = DateTime.now().toUtc().subtract(const Duration(minutes: 30));
    Map<String, dynamic> point(int hoursFromStart, double temp, String symbol) => {
          'time': start.add(Duration(hours: hoursFromStart)).toIso8601String(),
          'data': {
            'instant': {
              'details': {
                'air_pressure_at_sea_level': 1013.25,
                'air_temperature': temp,
                'relative_humidity': 80.0,
                'wind_speed': 3.0,
              }
            },
            'next_1_hours': {
              'summary': {'symbol_code': symbol}
            },
          },
        };

    final weather = Weather.fromMetNo({
      'geometry': {
        'coordinates': [104.28, 52.28, 0]
      },
      'properties': {
        'timeseries': [
          point(0, 5.0, 'rainshowers_night'),
          point(1, 7.0, 'cloudy'),
          point(2, 3.0, 'heavysnow'),
        ]
      },
    });

    expect(weather.source, contains('MET Norway'));
    expect(weather.temperature, 5.0);
    expect(weather.weatherCode, 81);
    expect(weather.isDay, isFalse);
    expect(weather.pressureMmHg.round(), 760);
    expect(weather.hourly.length, 3);
    expect(weather.daily.first.maxTemp, greaterThanOrEqualTo(5.0));
  });
}
