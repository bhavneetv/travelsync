import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants.dart';
import '../data/models/travel_log.dart';
import 'api_services.dart';
import 'xp_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService(ref);
});

final isTrackingProvider = StateProvider<bool>((ref) => false);

final currentPositionProvider = StateProvider<Position?>((ref) => null);

class LocationService {
  final Ref _ref;
  final _nominatim = NominatimService();
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastSavedPosition;

  LocationService(this._ref);

  /// Check and request location permissions
  Future<bool> checkPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }

    if (permission == LocationPermission.deniedForever) return false;

    return true;
  }

  /// Get current position
  Future<Position?> getCurrentPosition() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // Medium accuracy is enough for centering the map and avoids ANR-like stalls on slow devices.
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _ref.read(currentPositionProvider.notifier).state = position;
      return position;
    } catch (e) {
      return null;
    }
  }

  /// Start continuous tracking
  Future<bool> startTracking() async {
    final hasPermission = await checkPermission();
    if (!hasPermission) {
      _ref.read(isTrackingProvider.notifier).state = false;
      return false;
    }

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _ref.read(isTrackingProvider.notifier).state = true;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 500, // Minimum 500m displacement
      ),
    ).listen((position) async {
      _ref.read(currentPositionProvider.notifier).state = position;

      // Only save if moved >100m from last saved position
      if (_shouldSavePosition(position)) {
        try {
          await _savePosition(position);
          _lastSavedPosition = position;
        } catch (_) {
          // Keep tracking alive even if one save attempt fails.
        }
      }
    }, onError: (_, __) {
      stopTracking();
    });

    return true;
  }

  /// Stop tracking
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _ref.read(isTrackingProvider.notifier).state = false;
  }

  bool _shouldSavePosition(Position position) {
    if (_lastSavedPosition == null) return true;

    final distance = Geolocator.distanceBetween(
      _lastSavedPosition!.latitude,
      _lastSavedPosition!.longitude,
      position.latitude,
      position.longitude,
    );

    return distance >= 100; // 100m threshold
  }

  Future<void> _savePosition(Position position) async {
    final userId = AppConstants.supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Reverse geocode
    final geoData = await _nominatim.reverseGeocode(
      position.latitude,
      position.longitude,
    );

    final log = TravelLog(
      userId: userId,
      latitude: position.latitude,
      longitude: position.longitude,
      altitudeM: position.altitude,
      speedKmh: position.speed * 3.6, // m/s to km/h
      heading: position.heading,
      accuracyM: position.accuracy,
      city: geoData['city'],
      state: geoData['state'],
      country: geoData['country'],
      countryCode: geoData['country_code'],
      recordedAt: DateTime.now(),
    );

    await AppConstants.supabase.from('travel_logs').insert(log.toJson());

    // Check for new city/state/country visits
    await _checkNewVisits(userId, geoData, position);
  }

  Future<void> _checkNewVisits(
    String userId,
    Map<String, String?> geoData,
    Position position,
  ) async {
    final xpService = _ref.read(xpServiceProvider);

    // Check new city
    if (geoData['city'] != null) {
      final existing = await AppConstants.supabase
          .from('visited_cities')
          .select()
          .eq('user_id', userId)
          .eq('name', geoData['city']!)
          .maybeSingle();

      if (existing == null) {
        await AppConstants.supabase.from('visited_cities').insert({
          'user_id': userId,
          'name': geoData['city'],
          'country_code': geoData['country_code'],
          'lat': position.latitude,
          'lng': position.longitude,
          'xp_awarded': true,
        });

        await xpService.awardXP(
          userId: userId,
          delta: AppConstants.xpNewCity,
          reason: 'New city: ${geoData['city']}',
        );

        // Update denormalized counter
        await AppConstants.supabase.rpc('increment_counter', params: {
          'row_id': userId,
          'column_name': 'cities_visited',
        }).catchError((_) async {
          // Fallback: manual increment
          final user = await AppConstants.supabase
              .from('users')
              .select('cities_visited')
              .eq('id', userId)
              .single();
          await AppConstants.supabase.from('users').update({
            'cities_visited': (user['cities_visited'] as int? ?? 0) + 1,
          }).eq('id', userId);
        });
      } else {
        // Increment visit count
        await AppConstants.supabase
            .from('visited_cities')
            .update({'visit_count': (existing['visit_count'] as int) + 1})
            .eq('id', existing['id']);
      }
    }

    // Check new country
    if (geoData['country_code'] != null) {
      final existing = await AppConstants.supabase
          .from('visited_countries')
          .select()
          .eq('user_id', userId)
          .eq('country_code', geoData['country_code']!)
          .maybeSingle();

      if (existing == null) {
        await AppConstants.supabase.from('visited_countries').insert({
          'user_id': userId,
          'name': geoData['country'] ?? '',
          'country_code': geoData['country_code'],
          'lat': position.latitude,
          'lng': position.longitude,
          'xp_awarded': true,
        });

        await xpService.awardXP(
          userId: userId,
          delta: AppConstants.xpNewCountry,
          reason: 'New country: ${geoData['country']}',
        );

        await AppConstants.supabase.from('users').update({
          'countries_visited': await _getCount('visited_countries', userId),
        }).eq('id', userId);
      }
    }

    // Check new state
    if (geoData['state'] != null) {
      final existing = await AppConstants.supabase
          .from('visited_states')
          .select()
          .eq('user_id', userId)
          .eq('name', geoData['state']!)
          .maybeSingle();

      if (existing == null) {
        await AppConstants.supabase.from('visited_states').insert({
          'user_id': userId,
          'name': geoData['state'],
          'country_code': geoData['country_code'],
          'lat': position.latitude,
          'lng': position.longitude,
          'xp_awarded': true,
        });

        await xpService.awardXP(
          userId: userId,
          delta: AppConstants.xpNewState,
          reason: 'New state: ${geoData['state']}',
        );
      }
    }
  }

  Future<int> _getCount(String table, String userId) async {
    final result = await AppConstants.supabase
        .from(table)
        .select()
        .eq('user_id', userId);
    return (result as List).length;
  }
}
