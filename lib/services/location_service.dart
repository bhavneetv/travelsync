import 'dart:async';
import 'dart:convert';
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

/// Stores the current active route ID (while tracking)
final activeRouteIdProvider = StateProvider<int?>((ref) => null);

/// Live route points for drawing on map while tracking
final routePointsProvider = StateProvider<List<List<double>>>((ref) => []);

/// Real-time accumulated distance in kilometers while tracking
final accumulatedDistanceKmProvider = StateProvider<double>((ref) => 0.0);

class LocationService {
  final Ref _ref;
  final _nominatim = NominatimService();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _destinationCheckTimer;
  Position? _lastSavedPosition;
  Position? _lastRoutePosition;
  Position? _lastUiPosition;
  DateTime? _lastUiUpdateAt;
  DateTime? _routeStartTime;
  double _accumulatedDistanceKm = 0;
  final List<List<double>> _routePoints = [];
  String? _startCityName;
  DateTime? _lastRouteCreateAttempt;
  bool _isStopping = false;

  // Destination detection fields
  Position?
  _stationaryAnchor; // The position where user first became stationary
  DateTime? _stationaryStartTime; // When user first became stationary at anchor
  bool _destinationDetected = false;
  static const double _destinationRadiusKm = 5.0; // 5km radius
  static const Duration _destinationDuration = Duration(hours: 5); // 5 hours

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
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100,
          timeLimit: Duration(seconds: 10),
        ),
      );
      _publishPositionToUi(position, force: true);
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
    _destinationCheckTimer?.cancel();
    _destinationCheckTimer = null;
    _isStopping = false;

    final hasActiveRoute =
        _ref.read(activeRouteIdProvider) != null && _routeStartTime != null;

    _ref.read(isTrackingProvider.notifier).state = true;

    if (!hasActiveRoute) {
      // Reset destination detection for a brand-new route only.
      _stationaryAnchor = null;
      _stationaryStartTime = null;
      _destinationDetected = false;
    }

    // Get starting position for route
    try {
      final startPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!hasActiveRoute) {
        _lastRoutePosition = startPos;
        _routeStartTime = DateTime.now();
        _accumulatedDistanceKm = 0;
        _ref.read(accumulatedDistanceKmProvider.notifier).state = 0.0;
        _routePoints.clear();
        _appendRoutePoint(startPos.latitude, startPos.longitude);
        _ref.read(routePointsProvider.notifier).state = List.from(_routePoints);

        // Initialize destination detection anchor
        _stationaryAnchor = startPos;
        _stationaryStartTime = DateTime.now();

        // Create a new route entry
        await _startRoute(startPos);
      } else {
        // Resume paused tracking without creating a new route.
        _lastRoutePosition = startPos;
        _stationaryAnchor ??= startPos;
        _stationaryStartTime ??= DateTime.now();
      }
    } catch (_) {
      // If we can't get start position, just continue without route
    }

    _startDestinationMonitor();

    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter:
                100, // Capture route shape and distance more accurately.
          ),
        ).listen(
          (position) async {
            _publishPositionToUi(position);

            // If initialization failed initially, bootstrap route state from first update.
            if (_routeStartTime == null) {
              _routeStartTime = DateTime.now();
              _accumulatedDistanceKm = 0;
              _ref.read(accumulatedDistanceKmProvider.notifier).state = 0.0;
              _routePoints.clear();
              _appendRoutePoint(position.latitude, position.longitude);
              _lastRoutePosition = position;
              _stationaryAnchor ??= position;
              _stationaryStartTime ??= DateTime.now();
            }

            // Ensure route record exists even if start geocode/insert previously failed.
            if (_ref.read(activeRouteIdProvider) == null) {
              final now = DateTime.now();
              if (_lastRouteCreateAttempt == null ||
                  now.difference(_lastRouteCreateAttempt!) >
                      const Duration(minutes: 2)) {
                _lastRouteCreateAttempt = now;
                await _startRoute(position);
              }
            }

            // Accumulate route distance from every position update
            if (_lastRoutePosition != null) {
              final segmentM = Geolocator.distanceBetween(
                _lastRoutePosition!.latitude,
                _lastRoutePosition!.longitude,
                position.latitude,
                position.longitude,
              );
              if (_isValidRouteSegment(
                segmentMeters: segmentM,
                previous: _lastRoutePosition!,
                current: position,
              )) {
                _accumulatedDistanceKm += segmentM / 1000;
                _ref.read(accumulatedDistanceKmProvider.notifier).state =
                    _accumulatedDistanceKm;
              }
            }
            _lastRoutePosition = position;

            // Collect polyline point
            _appendRoutePoint(position.latitude, position.longitude);
            _ref.read(routePointsProvider.notifier).state = List.from(
              _routePoints,
            );

            // Destination detection: check if user moved > 5km from anchor
            _updateDestinationDetection(position);

            // Only save to DB if moved >100m from last saved position
            if (_shouldSavePosition(position)) {
              try {
                await _savePosition(position);
                _lastSavedPosition = position;
              } catch (_) {
                // Keep tracking alive even if one save attempt fails.
              }
            }
          },
          onError: (_, __) {
            stopTracking();
          },
        );

    return true;
  }

  /// Update destination detection state
  void _updateDestinationDetection(Position position) {
    if (_stationaryAnchor == null) {
      _stationaryAnchor = position;
      _stationaryStartTime = DateTime.now();
      return;
    }

    final distFromAnchorM = Geolocator.distanceBetween(
      _stationaryAnchor!.latitude,
      _stationaryAnchor!.longitude,
      position.latitude,
      position.longitude,
    );

    final distFromAnchorKm = distFromAnchorM / 1000;

    if (distFromAnchorKm > _destinationRadiusKm) {
      // User moved away — reset anchor to new position
      _stationaryAnchor = position;
      _stationaryStartTime = DateTime.now();
      _destinationDetected = false;
    } else {
      // User is still within 5km — check duration
      if (_stationaryStartTime != null) {
        final elapsed = DateTime.now().difference(_stationaryStartTime!);
        if (elapsed >= _destinationDuration) {
          _destinationDetected = true;
          // Auto-stop tracking when destination is detected
          stopTracking(completeRoute: true);
        }
      }
    }
  }

  /// Stop tracking. Route is finalized only when destination condition is met.
  Future<void> stopTracking({bool completeRoute = false}) async {
    if (_isStopping) return;
    _isStopping = true;

    _destinationCheckTimer?.cancel();
    _destinationCheckTimer = null;

    _positionSubscription?.cancel();
    _positionSubscription = null;
    _ref.read(isTrackingProvider.notifier).state = false;

    if (completeRoute) {
      await _endRoute();
    }

    _isStopping = false;
  }

  /// Start a new route record
  Future<void> _startRoute(Position position) async {
    final userId = AppConstants.supabase.auth.currentUser?.id;
    if (userId == null) return;

    String? startCity;
    try {
      final geoData = await _nominatim.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      startCity = _resolvePrimaryPlaceName(geoData);
    } catch (_) {
      // Non-critical: geocode can fail but route row can still be created.
    }

    _startCityName ??= startCity;

    try {
      final result = await AppConstants.supabase
          .from('routes')
          .insert({
            'user_id': userId,
            'name': 'Route from ${_startCityName ?? 'Unknown'}',
            'start_lat': position.latitude,
            'start_lng': position.longitude,
            'start_city': _startCityName,
            'started_at': (_routeStartTime ?? DateTime.now()).toIso8601String(),
          })
          .select()
          .single();

      _ref.read(activeRouteIdProvider.notifier).state = result['id'] as int;
      _lastRouteCreateAttempt = DateTime.now();
    } catch (_) {
      // Non-critical - keep tracking and retry creating route later.
    }
  }

  /// End the current route with final position
  Future<void> _endRoute() async {
    var routeId = _ref.read(activeRouteIdProvider);
    final userId = AppConstants.supabase.auth.currentUser?.id;

    if (routeId == null && userId != null && _lastRoutePosition != null) {
      await _startRoute(_lastRoutePosition!);
      routeId = _ref.read(activeRouteIdProvider);
    }

    if (routeId != null && userId != null) {
      try {
        final currentPos = _ref.read(currentPositionProvider);
        final duration = _routeStartTime != null
            ? DateTime.now().difference(_routeStartTime!).inMinutes
            : null;

        double? avgSpeed;

        // Reverse geocode end position to get end place.
        final geoData = currentPos != null
            ? await _nominatim.reverseGeocode(
                currentPos.latitude,
                currentPos.longitude,
              )
            : <String, String?>{};
        final endCityName = _resolvePrimaryPlaceName(geoData);

        if (currentPos != null) {
          _appendRoutePoint(currentPos.latitude, currentPos.longitude);
        }

        // Use the best available distance estimate.
        double? distanceKm = _accumulatedDistanceKm > 0
            ? _accumulatedDistanceKm
            : null;
        final polylineDistanceKm = _computeRouteDistanceKm(_routePoints);
        if (polylineDistanceKm > 0) {
          if (distanceKm == null || polylineDistanceKm > distanceKm) {
            distanceKm = polylineDistanceKm;
          }
        }

        if (distanceKm != null && duration != null && duration > 0) {
          avgSpeed = distanceKm / (duration / 60); // km/h
        }

        final startName = _startCityName ?? 'Unknown';
        final endName = endCityName ?? 'Unknown';
        final routeName = '$startName -> $endName';
        final polylineJson = json.encode(_routePoints);

        await AppConstants.supabase
            .from('routes')
            .update({
              'end_lat': currentPos?.latitude,
              'end_lng': currentPos?.longitude,
              'end_city': endCityName,
              'ended_at': DateTime.now().toIso8601String(),
              'distance_km': distanceKm,
              'duration_min': duration,
              'avg_speed_kmh': avgSpeed,
              'polyline': polylineJson,
              'name': routeName,
              'is_destination': _destinationDetected,
            })
            .eq('id', routeId);

        // Update total distance in user profile.
        if (distanceKm != null && distanceKm > 0) {
          final user = await AppConstants.supabase
              .from('users')
              .select('total_distance_km')
              .eq('id', userId)
              .single();
          final currentDist =
              (user['total_distance_km'] as num?)?.toDouble() ?? 0;
          await AppConstants.supabase
              .from('users')
              .update({'total_distance_km': currentDist + distanceKm})
              .eq('id', userId);
        }
      } catch (_) {
        // Non-critical
      }
    }

    _resetTrackingState();
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
      // Store the most specific place name so villages are preserved.
      city: _resolvePrimaryPlaceName(geoData),
      state: geoData['state'],
      country: geoData['country'],
      countryCode: geoData['country_code'],
      recordedAt: DateTime.now(),
    );

    await AppConstants.supabase.from('travel_logs').insert(log.toJson());

    // Check for new visits
    await _checkNewVisits(userId, geoData, position);
  }

  Future<void> _checkNewVisits(
    String userId,
    Map<String, String?> geoData,
    Position position,
  ) async {
    final xpService = _ref.read(xpServiceProvider);
    var villageName = _normalizePlaceName(geoData['village']);
    final cityName = _normalizePlaceName(geoData['city']);
    final placeName = _normalizePlaceName(geoData['place_name']);
    final settlementKind = _normalizePlaceName(geoData['settlement_kind']);

    // If village key is missing but place_name is more specific than city,
    // treat it as village/locality to preserve actual village names.
    if (villageName == null &&
      placeName != null &&
      settlementKind?.toLowerCase() == 'village') {
      villageName = placeName;
    }

    // Count village first so village visits are not swallowed by city matches.
    if (villageName != null) {
      final existing = await AppConstants.supabase
          .from('visited_villages')
          .select()
          .eq('user_id', userId)
          .eq('name', villageName)
          .maybeSingle();

      if (existing == null) {
        await AppConstants.supabase.from('visited_villages').insert({
          'user_id': userId,
          'name': villageName,
          'country_code': geoData['country_code'],
          'state': geoData['state'],
          'lat': position.latitude,
          'lng': position.longitude,
          'xp_awarded': true,
        });

        await xpService.awardXP(
          userId: userId,
          delta: AppConstants.xpNewVillage,
          reason: 'New village: $villageName',
        );

        final user = await AppConstants.supabase
            .from('users')
            .select('villages_visited')
            .eq('id', userId)
            .single();
        await AppConstants.supabase
            .from('users')
            .update({
              'villages_visited': (user['villages_visited'] as int? ?? 0) + 1,
            })
            .eq('id', userId);
      } else {
        await AppConstants.supabase
            .from('visited_villages')
            .update({'visit_count': (existing['visit_count'] as int? ?? 1) + 1})
            .eq('id', existing['id']);
      }
    }

    // Count city only when this point is not already a village.
    if (villageName == null && cityName != null) {
      final existing = await AppConstants.supabase
          .from('visited_cities')
          .select()
          .eq('user_id', userId)
          .eq('name', cityName)
          .maybeSingle();

      if (existing == null) {
        await AppConstants.supabase.from('visited_cities').insert({
          'user_id': userId,
          'name': cityName,
          'country_code': geoData['country_code'],
          'state': geoData['state'],
          'lat': position.latitude,
          'lng': position.longitude,
          'xp_awarded': true,
        });

        await xpService.awardXP(
          userId: userId,
          delta: AppConstants.xpNewCity,
          reason: 'New city: $cityName',
        );

        await AppConstants.supabase
            .rpc(
              'increment_counter',
              params: {'row_id': userId, 'column_name': 'cities_visited'},
            )
            .catchError((_) async {
              final user = await AppConstants.supabase
                  .from('users')
                  .select('cities_visited')
                  .eq('id', userId)
                  .single();
              await AppConstants.supabase
                  .from('users')
                  .update({
                    'cities_visited': (user['cities_visited'] as int? ?? 0) + 1,
                  })
                  .eq('id', userId);
            });
      } else {
        await AppConstants.supabase
            .from('visited_cities')
            .update({'visit_count': (existing['visit_count'] as int? ?? 1) + 1})
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

        await AppConstants.supabase
            .from('users')
            .update({
              'countries_visited': await _getCount('visited_countries', userId),
            })
            .eq('id', userId);
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

  void _startDestinationMonitor() {
    _destinationCheckTimer?.cancel();
    _destinationCheckTimer = Timer.periodic(const Duration(minutes: 5), (
      _,
    ) async {
      if (!_ref.read(isTrackingProvider) || _destinationDetected) return;

      Position? position = _ref.read(currentPositionProvider);
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 12),
            ),
          );
        } catch (_) {
          return;
        }
      }

      _updateDestinationDetection(position);
    });
  }

  void _publishPositionToUi(Position position, {bool force = false}) {
    if (force || _lastUiPosition == null) {
      _lastUiPosition = position;
      _lastUiUpdateAt = DateTime.now();
      _ref.read(currentPositionProvider.notifier).state = position;
      return;
    }

    final movedMeters = Geolocator.distanceBetween(
      _lastUiPosition!.latitude,
      _lastUiPosition!.longitude,
      position.latitude,
      position.longitude,
    );
    final elapsed = DateTime.now().difference(_lastUiUpdateAt!);

    // Keep UI responsive by reducing high-frequency location-driven rebuilds.
    if (movedMeters >= 25 || elapsed >= const Duration(seconds: 4)) {
      _lastUiPosition = position;
      _lastUiUpdateAt = DateTime.now();
      _ref.read(currentPositionProvider.notifier).state = position;
    }
  }

  String? _normalizePlaceName(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }

  String? _resolvePrimaryPlaceName(Map<String, String?> geoData) {
    return _normalizePlaceName(geoData['village']) ??
        _normalizePlaceName(geoData['place_name']) ??
        _normalizePlaceName(geoData['city']);
  }

  void _appendRoutePoint(double lat, double lng) {
    if (_routePoints.isNotEmpty) {
      final last = _routePoints.last;
      if (last.length >= 2 && last[0] == lat && last[1] == lng) {
        return;
      }
    }
    _routePoints.add([lat, lng]);
  }

  double _computeRouteDistanceKm(List<List<double>> points) {
    if (points.length < 2) return 0;
    var totalMeters = 0.0;
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      if (prev.length < 2 || curr.length < 2) continue;
      totalMeters += Geolocator.distanceBetween(
        prev[0],
        prev[1],
        curr[0],
        curr[1],
      );
    }
    return totalMeters / 1000;
  }

  bool _isValidRouteSegment({
    required double segmentMeters,
    required Position previous,
    required Position current,
  }) {
    if (segmentMeters < 5) return false;

    // Guard against rare GPS spikes that can badly inflate route distance.
    if (segmentMeters > 3000) return false;

    final prevTs = previous.timestamp;
    final currTs = current.timestamp;
    if (prevTs != null && currTs != null) {
      final seconds = currTs.difference(prevTs).inSeconds;
      if (seconds > 0) {
        final speedMps = segmentMeters / seconds;
        final speedKmh = speedMps * 3.6;
        if (speedKmh > 220) return false;
      }
    }

    return true;
  }

  void _resetTrackingState() {
    _ref.read(activeRouteIdProvider.notifier).state = null;
    _lastSavedPosition = null;
    _lastRoutePosition = null;
    _lastUiPosition = null;
    _lastUiUpdateAt = null;
    _routeStartTime = null;
    _accumulatedDistanceKm = 0;
    _ref.read(accumulatedDistanceKmProvider.notifier).state = 0.0;
    _routePoints.clear();
    _startCityName = null;
    _lastRouteCreateAttempt = null;
    _stationaryAnchor = null;
    _stationaryStartTime = null;
    _destinationDetected = false;
    _destinationCheckTimer?.cancel();
    _destinationCheckTimer = null;
    _ref.read(routePointsProvider.notifier).state = [];
  }
}
