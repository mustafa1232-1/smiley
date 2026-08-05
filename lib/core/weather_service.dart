import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Real-world weather conditions the scene reacts to.
enum WeatherCondition { clear, partlyCloudy, overcast, fog, rain, snow, storm }

class WeatherNow {
  const WeatherNow(this.condition, this.cloudCover);

  final WeatherCondition condition;
  final double cloudCover; // 0..1

  Map<String, dynamic> toJson() => {'c': condition.index, 'cc': cloudCover};

  static WeatherNow fromJson(Map<String, dynamic> j) => WeatherNow(
    WeatherCondition.values[(j['c'] as num).toInt().clamp(
      0,
      WeatherCondition.values.length - 1,
    )],
    (j['cc'] as num).toDouble(),
  );
}

/// Fetches the current weather for the device's approximate area so the world's
/// sky matches reality (clouds when it's cloudy, rain when it's raining, …).
///
/// Location is derived coarsely from the public IP (no location permission),
/// then the free Open-Meteo API supplies the conditions. Everything is cached
/// for 30 minutes and fails soft: if anything is unreachable, callers get the
/// last value (or null) and the scene falls back to a clear time-of-day sky.
class WeatherService {
  WeatherService._();
  static final WeatherService instance = WeatherService._();

  static const _ttl = Duration(minutes: 30);

  WeatherNow? _cache;
  DateTime? _cacheAt;

  Future<WeatherNow?> current() async {
    final now = DateTime.now();
    if (_cache != null &&
        _cacheAt != null &&
        now.difference(_cacheAt!) < _ttl) {
      return _cache;
    }

    // Persisted cache survives restarts and avoids hammering the APIs.
    try {
      final prefs = await SharedPreferences.getInstance();
      final ts = prefs.getInt('weather_at');
      final raw = prefs.getString('weather_json');
      if (ts != null && raw != null) {
        final at = DateTime.fromMillisecondsSinceEpoch(ts);
        if (now.difference(at) < _ttl) {
          _cache = WeatherNow.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          _cacheAt = at;
          return _cache;
        }
      }
    } catch (_) {
      // ignore cache read errors
    }

    try {
      final loc = await _approxLocation();
      if (loc == null) return _cache;
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${loc.$1}&longitude=${loc.$2}'
        '&current=weather_code,cloud_cover',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return _cache;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final cur = data['current'] as Map<String, dynamic>?;
      if (cur == null) return _cache;
      final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
      final cc = ((cur['cloud_cover'] as num?)?.toDouble() ?? 0) / 100.0;
      final wx = WeatherNow(_mapCode(code), cc.clamp(0.0, 1.0));
      _cache = wx;
      _cacheAt = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('weather_at', now.millisecondsSinceEpoch);
        await prefs.setString('weather_json', jsonEncode(wx.toJson()));
      } catch (_) {
        // ignore cache write errors
      }
      return wx;
    } catch (_) {
      return _cache;
    }
  }

  /// Approximate (city-level) location from the public IP. Returns (lat, lon).
  Future<(double, double)?> _approxLocation() async {
    try {
      final res = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['success'] == false) return null;
      final lat = (j['latitude'] as num?)?.toDouble();
      final lon = (j['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      return (lat, lon);
    } catch (_) {
      return null;
    }
  }

  WeatherCondition _mapCode(int c) {
    if (c == 0) return WeatherCondition.clear;
    if (c == 1 || c == 2) return WeatherCondition.partlyCloudy;
    if (c == 3) return WeatherCondition.overcast;
    if (c == 45 || c == 48) return WeatherCondition.fog;
    if (c >= 95) return WeatherCondition.storm;
    if ((c >= 71 && c <= 77) || c == 85 || c == 86) {
      return WeatherCondition.snow;
    }
    if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) {
      return WeatherCondition.rain;
    }
    return WeatherCondition.partlyCloudy;
  }
}
