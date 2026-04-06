/// Pure-Dart helper — no Flutter imports required.
///
/// Detects the most likely transport mode from speed (km/h) and
/// nearby POI context (airport / railway station).
class TransportModeDetector {
  TransportModeDetector._();

  // Speed brackets (km/h)
  static const double _footMax = 6;
  static const double _cycleMax = 30;
  static const double _carMin = 18;
  static const double _carMax = 160;
  static const double _trainMin = 60;
  static const double _trainMax = 400;
  static const double _flightMin = 250;

  /// Returns one of: walking · cycling · car · train · flight · unknown
  static String fromSpeed(double speedKmh) {
    if (speedKmh < 0) return 'unknown';
    if (speedKmh <= _footMax) return 'walking';
    if (speedKmh <= _cycleMax) return 'cycling';
    if (speedKmh >= _flightMin) return 'flight';
    if (speedKmh >= _trainMin && speedKmh <= _trainMax) return 'train';
    if (speedKmh >= _carMin && speedKmh <= _carMax) return 'car';
    return 'car'; // fallback for ambiguous range
  }

  /// Refines speed-based guess with OSM POI context.
  ///
  /// [poiTags] – lowercase OSM tag value strings near the current position,
  ///              e.g. ['railway=station', 'aeroway=aerodrome'].
  static String refine(double speedKmh, List<String> poiTags) {
    final raw = fromSpeed(speedKmh);

    final nearAirport = poiTags.any(
      (t) =>
          t.contains('aeroway') ||
          t.contains('airport') ||
          t.contains('aerodrome'),
    );
    final nearStation = poiTags.any(
      (t) =>
          t.contains('railway=station') ||
          t.contains('railway=halt') ||
          t.contains('train_station'),
    );
    final nearBusStop = poiTags.any(
      (t) => t.contains('bus_stop') || t.contains('bus_station'),
    );

    if (nearAirport && speedKmh >= _flightMin) return 'flight';
    if (nearStation && speedKmh >= _trainMin) return 'train';
    if (nearBusStop && speedKmh < _carMax) return 'bus';

    return raw;
  }

  /// Human-readable label for UI display.
  static String label(String mode) {
    switch (mode) {
      case 'walking':
        return 'Walking';
      case 'cycling':
        return 'Cycling';
      case 'car':
        return 'Driving';
      case 'train':
        return 'Train';
      case 'bus':
        return 'Bus';
      case 'flight':
        return 'Flight';
      default:
        return 'Travelling';
    }
  }

  /// Emoji icon for quick display.
  static String emoji(String mode) {
    switch (mode) {
      case 'walking':
        return '🚶';
      case 'cycling':
        return '🚲';
      case 'car':
        return '🚗';
      case 'train':
        return '🚆';
      case 'bus':
        return '🚌';
      case 'flight':
        return '✈️';
      default:
        return '📍';
    }
  }
}
