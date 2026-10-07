import 'dart:async';

import 'package:flutter/material.dart';

import '../models/weather.dart';
import '../services/location_service.dart';
import '../services/weather_service.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final _locationService = LocationService();
  final _weatherService = WeatherService();

  Weather? _weather;
  String? _city;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final pos = await _locationService.getCurrentPosition();
      final results = await Future.wait([
        _weatherService.fetchWeather(pos.latitude, pos.longitude),
        _weatherService.fetchCityName(pos.latitude, pos.longitude),
      ]);
      if (!mounted) return;
      setState(() {
        _weather = results[0] as Weather;
        _city = (results[1] as String?) ??
            '${pos.latitude.toStringAsFixed(2)}, ${pos.longitude.toStringAsFixed(2)}';
      });
    } on LocationException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on WeatherException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on TimeoutException {
      if (mounted) {
        setState(() => _error =
            'Не удалось определить местоположение. Выйдите на открытое место и повторите.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Что-то пошло не так. Повторите попытку.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    final colors = weather == null
        ? const [Color(0xFF2980B9), Color(0xFF6DD5FA)]
        : WeatherCode.gradient(weather.weatherCode, isDay: weather.isDay);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
        child: SafeArea(
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white),
            child: IconTheme(
              data: const IconThemeData(color: Colors.white),
              child: _buildBody(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _weather == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Определяем местоположение…'),
          ],
        ),
      );
    }

    if (_error != null && _weather == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 64),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    final weather = _weather!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Header(city: _city ?? '', loading: _loading, onRefresh: _load),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Не удалось обновить: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.amberAccent)),
            ),
          const SizedBox(height: 16),
          _CurrentWeather(weather: weather),
          const SizedBox(height: 24),
          _DetailsRow(weather: weather),
          const SizedBox(height: 24),
          _HourlyList(hours: weather.hourly),
          const SizedBox(height: 24),
          _DailyList(days: weather.daily),
          const SizedBox(height: 16),
          Text('Данные: ${weather.source}, © OpenStreetMap',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String city;
  final bool loading;
  final VoidCallback onRefresh;

  const _Header(
      {required this.city, required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.location_on),
        const SizedBox(width: 6),
        Expanded(
          child: Text(city,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
        ),
        loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Обновить',
              ),
      ],
    );
  }
}

class _CurrentWeather extends StatelessWidget {
  final Weather weather;
  const _CurrentWeather({required this.weather});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(WeatherCode.icon(weather.weatherCode, isDay: weather.isDay),
            size: 96),
        Text(_formatTemp(weather.temperature),
            style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w300)),
        Text(WeatherCode.description(weather.weatherCode),
            style: const TextStyle(fontSize: 20)),
        const SizedBox(height: 4),
        Text('Ощущается как ${_formatTemp(weather.feelsLike)}',
            style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}

class _DetailsRow extends StatelessWidget {
  final Weather weather;
  const _DetailsRow({required this.weather});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Detail(Icons.air, '${weather.windSpeed.toStringAsFixed(1)} м/с',
              'Ветер'),
          _Detail(Icons.water_drop_outlined, '${weather.humidity}%',
              'Влажность'),
          _Detail(Icons.speed, '${weather.pressureMmHg.round()} мм',
              'Давление'),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _Detail(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
      ],
    );
  }
}

class _HourlyList extends StatelessWidget {
  final List<HourlyForecast> hours;
  const _HourlyList({required this.hours});

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Почасовой прогноз',
      child: SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: hours.length,
          separatorBuilder: (_, _) => const SizedBox(width: 16),
          itemBuilder: (_, i) {
            final h = hours[i];
            return Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(i == 0
                    ? 'Сейчас'
                    : '${h.time.hour.toString().padLeft(2, '0')}:00'),
                Icon(WeatherCode.icon(h.weatherCode, isDay: h.isDay)),
                Text(_formatTemp(h.temperature),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DailyList extends StatelessWidget {
  final List<DailyForecast> days;
  const _DailyList({required this.days});

  static const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Прогноз на неделю',
      child: Column(
        children: [
          for (var i = 0; i < days.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: Text(i == 0
                        ? 'Сегодня'
                        : '${_weekdays[days[i].date.weekday - 1]}, ${days[i].date.day}'),
                  ),
                  Icon(WeatherCode.icon(days[i].weatherCode)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(WeatherCode.description(days[i].weatherCode),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  Text(
                      '${_formatTemp(days[i].minTemp)} / ${_formatTemp(days[i].maxTemp)}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String? title;
  final Widget child;
  const _Card({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!,
                style: const TextStyle(
                    fontSize: 13, color: Colors.white70, letterSpacing: 0.5)),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

String _formatTemp(double t) {
  final r = t.round();
  return '${r > 0 ? '+' : ''}$r°';
}
