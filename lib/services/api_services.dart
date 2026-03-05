import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class NominatimService {
  static const _headers = {
    'User-Agent': 'TravelSync/1.0',
    'Accept': 'application/json',
  };

  /// Reverse geocode a coordinate to get city, state, country info
  Future<Map<String, String?>> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.nominatimBaseUrl}/reverse?lat=$latitude&lon=$longitude&format=json&addressdetails=1',
      );

      final response = await http.get(url, headers: _headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          return {
            'city': address['city'] as String? ??
                address['town'] as String? ??
                address['village'] as String? ??
                address['hamlet'] as String?,
            'state': address['state'] as String?,
            'country': address['country'] as String?,
            'country_code':
                (address['country_code'] as String?)?.toUpperCase(),
          };
        }
      }
    } catch (e) {
      // Return empty on error - will retry next time
    }

    return {
      'city': null,
      'state': null,
      'country': null,
      'country_code': null,
    };
  }
}

class WeatherService {
  /// Get current weather for a location using Open-Meteo
  Future<Map<String, dynamic>?> getCurrentWeather(
    double latitude,
    double longitude,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.openMeteoBaseUrl}/forecast?latitude=$latitude&longitude=$longitude&current_weather=true&hourly=temperature_2m,weathercode&forecast_days=1',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current_weather'] as Map<String, dynamic>?;

        if (current != null) {
          return {
            'temperature': current['temperature'],
            'windspeed': current['windspeed'],
            'weathercode': current['weathercode'],
            'description': _weatherCodeToDescription(
              current['weathercode'] as int,
            ),
            'icon': _weatherCodeToIcon(current['weathercode'] as int),
          };
        }
      }
    } catch (e) {
      // Silently fail for weather
    }
    return null;
  }

  String _weatherCodeToDescription(int code) {
    if (code == 0) return 'Clear sky';
    if (code <= 3) return 'Partly cloudy';
    if (code <= 48) return 'Foggy';
    if (code <= 57) return 'Drizzle';
    if (code <= 67) return 'Rain';
    if (code <= 77) return 'Snow';
    if (code <= 82) return 'Rain showers';
    if (code <= 86) return 'Snow showers';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  String _weatherCodeToIcon(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '🌫️';
    if (code <= 57) return '🌧️';
    if (code <= 67) return '🌧️';
    if (code <= 77) return '❄️';
    if (code <= 82) return '🌦️';
    if (code <= 86) return '🌨️';
    if (code <= 99) return '⛈️';
    return '🌡️';
  }
}
