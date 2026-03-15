import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class NominatimService {
  /// Reverse geocode using BigDataCloud first, then enrich with Nominatim fallback.
  Future<Map<String, String?>> reverseGeocode(
    double latitude,
    double longitude,
  ) async {
    Map<String, String?>? bigDataResult;

    try {
      final url = Uri.parse(
        '${AppConstants.bigDataCloudBaseUrl}/reverse-geocode-client'
        '?latitude=$latitude&longitude=$longitude&localityLanguage=en',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final localityInfo = data['localityInfo'] as Map<String, dynamic>?;

        var resolvedCity = _normalizeText(data['city'] as String?);
        var resolvedVillage = _normalizeText(data['village'] as String?);
        final locality = _normalizeText(data['locality'] as String?);

        final looksVillageLike = _extractVillageHint(localityInfo) ||
            (locality != null && locality.toLowerCase().contains('village'));

        if (resolvedVillage == null && locality != null) {
          if (resolvedCity == null || !_samePlace(locality, resolvedCity)) {
            resolvedVillage = locality;
          } else if (looksVillageLike) {
            // BigDataCloud can classify some villages under "city".
            resolvedVillage = locality;
            resolvedCity = null;
          }
        }

        bigDataResult = {
          'city': resolvedCity,
          'village': resolvedVillage,
          'state': _normalizeText(data['principalSubdivision'] as String?),
          'country': _normalizeText(data['countryName'] as String?),
          'country_code':
              _normalizeText((data['countryCode'] as String?)?.toUpperCase()),
          'place_name': resolvedVillage ?? resolvedCity ?? locality,
        };
      }
    } catch (_) {
      // Fall through to Nominatim fallback.
    }

    final fallback = await _nominatimFallback(latitude, longitude);
    if (bigDataResult == null) return fallback;

    // Prefer Nominatim for granular village names when available.
    var city = fallback['city'] ?? bigDataResult['city'];
    var village = fallback['village'] ?? bigDataResult['village'];
    if (village != null &&
        city != null &&
        village.toLowerCase() == city.toLowerCase()) {
      village = null;
    }
    final placeName =
        village ?? city ?? bigDataResult['place_name'] ?? fallback['place_name'];

    return {
      'city': city,
      'village': village,
      'state': bigDataResult['state'] ?? fallback['state'],
      'country': bigDataResult['country'] ?? fallback['country'],
      'country_code': bigDataResult['country_code'] ?? fallback['country_code'],
      'place_name': placeName,
    };
  }

  Future<Map<String, String?>> _nominatimFallback(
    double latitude,
    double longitude,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.nominatimBaseUrl}/reverse'
        '?lat=$latitude&lon=$longitude&format=json&addressdetails=1',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'TravelSync/1.0',
        'Accept': 'application/json',
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          String? firstNonEmpty(List<String?> values) {
            for (final v in values) {
              final n = _normalizeText(v);
              if (n != null) return n;
            }
            return null;
          }

          final city = firstNonEmpty([
            address['city'] as String?,
            address['town'] as String?,
            address['municipality'] as String?,
            address['city_district'] as String?,
            address['county'] as String?,
          ]);

          var village = firstNonEmpty([
            address['village'] as String?,
            address['hamlet'] as String?,
            address['locality'] as String?,
            address['isolated_dwelling'] as String?,
            address['allotments'] as String?,
            address['quarter'] as String?,
            address['neighbourhood'] as String?,
            address['suburb'] as String?,
            address['farm'] as String?,
          ]);

          if (village != null &&
              city != null &&
              village.toLowerCase() == city.toLowerCase()) {
            village = null;
          }

          return {
            'city': city,
            'village': village,
            'state': _normalizeText(address['state'] as String?),
            'country': _normalizeText(address['country'] as String?),
            'country_code':
                _normalizeText((address['country_code'] as String?)?.toUpperCase()),
            'place_name': village ?? city,
          };
        }
      }
    } catch (_) {
      // Return empty fallback.
    }

    return {
      'city': null,
      'village': null,
      'state': null,
      'country': null,
      'country_code': null,
      'place_name': null,
    };
  }

  String? _normalizeText(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  bool _samePlace(String a, String b) {
    return a.toLowerCase() == b.toLowerCase();
  }

  bool _extractVillageHint(Map<String, dynamic>? localityInfo) {
    if (localityInfo == null) return false;

    final informative = localityInfo['informative'];
    if (informative is! List) return false;

    for (final item in informative) {
      if (item is! Map<String, dynamic>) continue;
      final name = (item['name'] as String?)?.toLowerCase();
      final description = (item['description'] as String?)?.toLowerCase();
      if ((name != null && name.contains('village')) ||
          (description != null && description.contains('village'))) {
        return true;
      }
    }
    return false;
  }
}

class NearbyPlaceSuggestion {
  final String name;
  final String category; // food | rest | attraction
  final String emoji;
  final double distanceKm;
  final double rating;

  const NearbyPlaceSuggestion({
    required this.name,
    required this.category,
    required this.emoji,
    required this.distanceKm,
    required this.rating,
  });
}

class OverpassService {
  Future<List<NearbyPlaceSuggestion>> getNearbySuggestions(
    double latitude,
    double longitude, {
    int radiusMeters = 5000,
    int limit = 24,
  }) async {
    final query = '''
[out:json][timeout:20];
(
  node(around:$radiusMeters,$latitude,$longitude)["amenity"~"restaurant|cafe|fast_food|bar|pub|hotel|guest_house|hostel|motel"];
  node(around:$radiusMeters,$latitude,$longitude)["tourism"~"attraction|museum|viewpoint|gallery|theme_park|zoo"];
  node(around:$radiusMeters,$latitude,$longitude)["leisure"~"park|garden|nature_reserve"];
  node(around:$radiusMeters,$latitude,$longitude)["historic"];
);
out body;
''';

    final uri = Uri.parse('${AppConstants.overpassBaseUrl}/interpreter');
    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            },
            body: {'data': query},
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return [];
    }

    if (response.statusCode != 200) return [];

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final elements = decoded['elements'] as List?;
    if (elements == null || elements.isEmpty) return [];

    final suggestions = <NearbyPlaceSuggestion>[];
    final seenNames = <String>{};
    for (final item in elements) {
      if (item is! Map<String, dynamic>) continue;
      final tags = item['tags'] as Map<String, dynamic>?;
      if (tags == null) continue;

      final name = (tags['name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      if (!seenNames.add(name.toLowerCase())) continue;

      final lat = (item['lat'] as num?)?.toDouble();
      final lon = (item['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final distanceKm = _haversineKm(latitude, longitude, lat, lon);
      if (distanceKm > (radiusMeters / 1000.0)) continue;

      final category = _resolveCategory(tags);
      suggestions.add(
        NearbyPlaceSuggestion(
          name: name,
          category: category,
          emoji: _categoryEmoji(category),
          distanceKm: distanceKm,
          rating: _derivePseudoRating(name),
        ),
      );
    }

    suggestions.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
    if (suggestions.length > limit) {
      return suggestions.sublist(0, limit);
    }
    return suggestions;
  }

  String _resolveCategory(Map<String, dynamic> tags) {
    final amenity = (tags['amenity'] as String?)?.toLowerCase();
    final tourism = (tags['tourism'] as String?)?.toLowerCase();

    const foodAmenities = {'restaurant', 'cafe', 'fast_food', 'bar', 'pub'};
    const restAmenities = {'hotel', 'guest_house', 'hostel', 'motel'};

    if (amenity != null && foodAmenities.contains(amenity)) return 'food';
    if (amenity != null && restAmenities.contains(amenity)) return 'rest';
    if (tourism != null) return 'attraction';
    if (tags.containsKey('historic')) return 'attraction';

    final leisure = (tags['leisure'] as String?)?.toLowerCase();
    if (leisure != null && leisure.isNotEmpty) return 'attraction';

    return 'attraction';
  }

  String _categoryEmoji(String category) {
    switch (category) {
      case 'food':
        return '🍽';
      case 'rest':
        return '🏨';
      default:
        return '🗺';
    }
  }

  double _derivePseudoRating(String name) {
    var hash = 0;
    for (final unit in name.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final bucket = (hash % 9) / 10.0; // 0.0..0.8
    return 4.1 + bucket;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLon = _toRad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _toRad(double degrees) => degrees * (math.pi / 180.0);
}

class WeatherService {
  /// Get current weather for a location using Open-Meteo
  Future<Map<String, dynamic>?> getCurrentWeather(
    double latitude,
    double longitude,
  ) async {
    try {
      final url = Uri.parse(
        '${AppConstants.openMeteoBaseUrl}/forecast?latitude=$latitude'
        '&longitude=$longitude&current_weather=true'
        '&hourly=temperature_2m,weathercode&forecast_days=1',
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
    } catch (_) {
      // Silently fail
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
