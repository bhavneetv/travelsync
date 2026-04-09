import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:ui';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import 'transport_mode_detector.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Constants (must not depend on AppSettingsService to keep isolate clean)
// ─────────────────────────────────────────────────────────────────────────────
const _kAlwaysOn = 'always_on_tracking';
const _kInterval = 'tracking_interval_seconds';
const _kChannelId = 'trailsync_tracking';

// ─────────────────────────────────────────────────────────────────────────────
//  Public API  (called from the UI isolate)
// ─────────────────────────────────────────────────────────────────────────────
class BackgroundLocationService {
  BackgroundLocationService._();

  static FlutterBackgroundService get _instance => FlutterBackgroundService();

  /// Call once at app start (inside main / after Supabase.initialize)
  static Future<void> configure() async {
    if (io.Platform.isAndroid) {
      final localNotifications = FlutterLocalNotificationsPlugin();
      const channel = AndroidNotificationChannel(
        _kChannelId,
        'TrailSync Background Tracking',
        description: 'Shows when location tracking is active in background.',
        importance: Importance.low,
      );

      await localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    await _instance.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _backgroundMain,
        autoStart: false,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: _kChannelId,
        initialNotificationTitle: 'TrailSync',
        initialNotificationContent: 'Using your location to store routes',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _backgroundMain,
        onBackground: _iosBackground,
      ),
    );
  }

  /// Start the background service (and enable always-on flag in prefs)
  static Future<bool> start() async {
    final prefs = await SharedPreferences.getInstance();

    final locationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!locationEnabled) {
      await prefs.setBool(_kAlwaysOn, false);
      return false;
    }

    if (io.Platform.isAndroid) {
      var status = await Permission.notification.status;
      if (!status.isGranted) {
        status = await Permission.notification.request();
      }
      if (!status.isGranted) {
        await prefs.setBool(_kAlwaysOn, false);
        return false;
      }
    }

    if (io.Platform.isIOS) {
      // iOS needs Always permission for reliable background updates.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse) {
        await Permission.locationAlways.request();
        permission = await Geolocator.checkPermission();
      }
      if (permission != LocationPermission.always) {
        await prefs.setBool(_kAlwaysOn, false);
        return false;
      }

      // Request notifications as well (optional on iOS, but needed for alerts).
      await Permission.notification.request();
    }

    await prefs.setBool(_kAlwaysOn, true);

    final running = await _instance.isRunning();
    if (!running) {
      await _instance.startService();
    }
    return true;
  }

  /// Stop the background service
  static Future<void> stop() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAlwaysOn, false);
    _instance.invoke('stop');
  }

  /// Update GPS polling interval while service is running
  static void updateInterval(int seconds) {
    _instance.invoke('update_interval', {'seconds': seconds});
  }

  static Future<bool> get isRunning => _instance.isRunning();
}

// ─────────────────────────────────────────────────────────────────────────────
//  iOS background handler  (keep-alive ping)
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<bool> _iosBackground(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Background isolate entry point
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
void _backgroundMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Init Supabase inside the isolate
  try {
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    ).timeout(const Duration(seconds: 15));
  } catch (_) {
    service.stopSelf();
    return;
  }

  final sb = Supabase.instance.client;
  final prefs = await SharedPreferences.getInstance();
  int intervalSeconds = prefs.getInt(_kInterval) ?? 300;
  if (intervalSeconds <= 0) {
    intervalSeconds = 300;
    await prefs.setInt(_kInterval, intervalSeconds);
  }

  // Route continuity is validated on first position update before resuming,
  // to avoid stale cross-device jumps.

  // Android foreground service notification
  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    _notify(
      service,
      'TrailSync · Background tracking active',
      '${_state.totalDistKm.toStringAsFixed(1)} km covered (${_intervalLabel(intervalSeconds)})',
    );
  }

  // ── IPC listeners ──────────────────────────────
  service.on('update_interval').listen((data) {
    if (data != null && data['seconds'] is int) {
      intervalSeconds = data['seconds'] as int;
      prefs.setInt(_kInterval, intervalSeconds);
      if (service is AndroidServiceInstance) {
        _notify(
          service,
          'TrailSync · Background tracking active',
          '${_state.totalDistKm.toStringAsFixed(1)} km covered (${_intervalLabel(intervalSeconds)})',
        );
      }
    }
  });
  service.on('stop').listen((_) async {
    await _endRoute(sb, _state, isDestination: false);
    service.stopSelf();
  });

  // ── Run tracking loop ──────────────────────────
  if (intervalSeconds == 0) {
    await _streamLoop(service, sb, prefs);
  } else {
    await _intervalLoop(service, sb, prefs, () => intervalSeconds);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mutable tracking state (shared across helpers in the isolate)
// ─────────────────────────────────────────────────────────────────────────────
final _state = _TrackState();

class _TrackState {
  Position? lastSaved;
  Position? lastAccumulated;
  int? activeRouteId;
  DateTime? routeStart;
  double totalDistKm = 0;
  final List<List<double>> points = [];
  String? startCity;
  bool creatingRoute = false;
  DateTime? lastRouteAttempt;
  Position? anchor; // for destination detection
  DateTime? anchorStart;

  void reset() {
    lastSaved = null;
    lastAccumulated = null;
    activeRouteId = null;
    routeStart = null;
    totalDistKm = 0;
    points.clear();
    startCity = null;
    creatingRoute = false;
    lastRouteAttempt = null;
    anchor = null;
    anchorStart = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Continuous stream loop
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _streamLoop(
  ServiceInstance service,
  SupabaseClient sb,
  SharedPreferences prefs,
) async {
  final stream = Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 40,
    ),
  );

  await for (final pos in stream) {
    if (!(prefs.getBool(_kAlwaysOn) ?? false)) {
      await _endRoute(sb, _state, isDestination: false);
      service.stopSelf();
      return;
    }
    await _processPosition(pos, service, sb);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Interval-based polling loop
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _intervalLoop(
  ServiceInstance service,
  SupabaseClient sb,
  SharedPreferences prefs,
  int Function() getInterval,
) async {
  while (true) {
    if (!(prefs.getBool(_kAlwaysOn) ?? false)) {
      await _endRoute(sb, _state, isDestination: false);
      service.stopSelf();
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    if (!serviceEnabled ||
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await _endRoute(sb, _state, isDestination: false);
      service.stopSelf();
      return;
    }

    try {
      final interval = getInterval();
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: interval <= 300
              ? LocationAccuracy.high
              : LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 20),
        ),
      );
      await _processPosition(pos, service, sb);
      await Future.delayed(Duration(seconds: interval));
    } catch (_) {
      await Future.delayed(const Duration(seconds: 60));
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Core position processor
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _processPosition(
  Position pos,
  ServiceInstance service,
  SupabaseClient sb,
) async {
  final state = _state;
  final userId = sb.auth.currentUser?.id;
  if (userId == null) return;

  // Ensure route row exists
  if (state.activeRouteId == null && !state.creatingRoute) {
    final now = DateTime.now();
    if (state.lastRouteAttempt == null ||
        now.difference(state.lastRouteAttempt!) > const Duration(minutes: 2)) {
      state.lastRouteAttempt = now;
      state.routeStart ??= now;
      state.anchor ??= pos;
      state.anchorStart ??= now;
      await _startRoute(pos, sb, state);
    }
  }

  // Accumulate distance & polyline
  if (state.lastAccumulated != null) {
    final seg = Geolocator.distanceBetween(
      state.lastAccumulated!.latitude,
      state.lastAccumulated!.longitude,
      pos.latitude, pos.longitude,
    );
    if (_isValidSegment(
      segmentMeters: seg,
      previous: state.lastAccumulated!,
      current: pos,
    )) {
      state.totalDistKm += seg / 1000;
      _appendPoint(pos, state);
    }
  } else {
    _appendPoint(pos, state);
  }
  state.lastAccumulated = pos;

  // Save position if moved ≥100 m
  final distFromLast = state.lastSaved == null
      ? double.infinity
      : Geolocator.distanceBetween(
          state.lastSaved!.latitude, state.lastSaved!.longitude,
          pos.latitude, pos.longitude,
        );

  if (distFromLast >= 100) {
    try {
      final geoData = await _reverseGeocode(pos.latitude, pos.longitude);
      final city = geoData['village'] ?? geoData['city'] ?? geoData['town'];
      final speedKmh = pos.speed >= 0 ? pos.speed * 3.6 : 0.0;
      final mode = TransportModeDetector.fromSpeed(speedKmh);

      await sb.from('travel_logs').insert({
        'user_id': userId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'altitude_m': pos.altitude,
        'speed_kmh': speedKmh,
        'heading': pos.heading,
        'accuracy_m': pos.accuracy,
        'city': city,
        'state': geoData['state'],
        'country': geoData['country'],
        'country_code': geoData['country_code'],
        'transport_mode': mode,
        'recorded_at': DateTime.now().toIso8601String(),
      });

      state.lastSaved = pos;

      // Push update to UI
      service.invoke('position_update', {
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speed': speedKmh,
        'mode': mode,
        'city': city,
        'dist_km': state.totalDistKm,
      });

      // Update notification text
      if (service is AndroidServiceInstance) {
        final emoji = TransportModeDetector.emoji(mode);
        final label = TransportModeDetector.label(mode);
        _notify(
          service,
          '$emoji $label · ${city ?? 'On the road'}',
          '${state.totalDistKm.toStringAsFixed(1)} km covered — tap to open',
        );
      }

      await _syncRouteProgress(sb, state);

      // New places check (cities/countries/states)
      await _checkNewPlaces(userId, geoData, pos, sb);
    } catch (_) {}
  }

  // Destination detection
  _checkDestination(pos, service, sb, state);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Route helpers
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _startRoute(
  Position pos,
  SupabaseClient sb,
  _TrackState state,
) async {
  final userId = sb.auth.currentUser?.id;
  if (userId == null) return;
  state.creatingRoute = true;
  try {
    final openRoute = await sb
        .from('routes')
        .select('id, started_at, start_city, distance_km')
        .eq('user_id', userId)
        .isFilter('ended_at', null)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (openRoute != null) {
      final shouldClose = await _shouldCloseOpenRouteForNewPosition(
        sb: sb,
        userId: userId,
        openRoute: openRoute,
        currentPos: pos,
      );
      if (!shouldClose) {
        state.activeRouteId = openRoute['id'] as int;
        state.startCity = openRoute['start_city'] as String?;

        final startedAtRaw = openRoute['started_at'] as String?;
        if (startedAtRaw != null && startedAtRaw.isNotEmpty) {
          state.routeStart = DateTime.tryParse(startedAtRaw) ?? state.routeStart;
        }

        final restoredDistance =
            (openRoute['distance_km'] as num?)?.toDouble() ?? 0.0;
        if (restoredDistance > state.totalDistKm) {
          state.totalDistKm = restoredDistance;
        }
        return;
      }
    }

    final geo = await _reverseGeocode(pos.latitude, pos.longitude);
    state.startCity = geo['village'] ?? geo['city'] ?? geo['town'];
    final result = await sb.from('routes').insert({
      'user_id': userId,
      'name': 'Route from ${state.startCity ?? 'Unknown'}',
      'start_lat': pos.latitude,
      'start_lng': pos.longitude,
      'start_city': state.startCity,
      'started_at': (state.routeStart ?? DateTime.now()).toIso8601String(),
    }).select().single();
    state.activeRouteId = result['id'] as int;
  } catch (_) {
  } finally {
    state.creatingRoute = false;
  }
}

Future<bool> _shouldCloseOpenRouteForNewPosition({
  required SupabaseClient sb,
  required String userId,
  required Map<String, dynamic> openRoute,
  required Position currentPos,
}) async {
  try {
    final lastLog = await sb
        .from('travel_logs')
        .select('latitude, longitude, recorded_at, city')
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastLog == null) return false;

    final lastLat = (lastLog['latitude'] as num?)?.toDouble();
    final lastLng = (lastLog['longitude'] as num?)?.toDouble();
    final recordedAtRaw = lastLog['recorded_at'] as String?;
    final recordedAt =
        recordedAtRaw != null ? DateTime.tryParse(recordedAtRaw) : null;
    if (lastLat == null || lastLng == null || recordedAt == null) {
      return false;
    }

    final distanceKm = Geolocator.distanceBetween(
          lastLat,
          lastLng,
          currentPos.latitude,
          currentPos.longitude,
        ) /
        1000;
    final idle = DateTime.now().difference(recordedAt);
    final movedFarAfterIdle = distanceKm >= 30 && idle >= const Duration(minutes: 30);
    final settledLongNearSameArea =
        distanceKm <= 5 && idle >= const Duration(hours: 3);

    if (!movedFarAfterIdle && !settledLongNearSameArea) {
      return false;
    }

    final routeId = openRoute['id'] as int;
    final startedAtRaw = openRoute['started_at'] as String?;
    final startedAt =
        startedAtRaw != null ? DateTime.tryParse(startedAtRaw) : null;
    final durationMin = startedAt != null
        ? recordedAt.difference(startedAt).inMinutes.clamp(0, 1000000)
        : null;
    final endCity = lastLog['city'] as String?;
    final startName = (openRoute['start_city'] as String?) ?? 'Unknown';
    final endName = endCity ?? 'Unknown';
    final distanceSaved = (openRoute['distance_km'] as num?)?.toDouble() ?? 0.0;

    await sb
        .from('routes')
        .update({
          'end_lat': lastLat,
          'end_lng': lastLng,
          'end_city': endCity,
          'ended_at': recordedAt.toIso8601String(),
          'distance_km': distanceSaved > 0 ? distanceSaved : null,
          'duration_min': durationMin,
          'name': '$startName -> $endName',
          'is_destination': settledLongNearSameArea,
        })
        .eq('id', routeId);

    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _endRoute(
  SupabaseClient sb,
  _TrackState state, {
  required bool isDestination,
}) async {
  final userId = sb.auth.currentUser?.id;
  if (userId == null || state.activeRouteId == null) {
    state.reset();
    return;
  }
  try {
    final geo = state.lastSaved != null
        ? await _reverseGeocode(
            state.lastSaved!.latitude, state.lastSaved!.longitude)
        : <String, String?>{};
    final endCity = geo['village'] ?? geo['city'] ?? geo['town'];
    final duration = state.routeStart != null
        ? DateTime.now().difference(state.routeStart!).inMinutes
        : null;
    final avgSpeed =
      (duration != null && duration > 0 && state.totalDistKm > 0)
      ? state.totalDistKm / (duration / 60)
      : null;
    final polyline = jsonEncode(state.points);

    await sb.from('routes').update({
      'end_lat': state.lastSaved?.latitude,
      'end_lng': state.lastSaved?.longitude,
      'end_city': endCity,
      'ended_at': DateTime.now().toIso8601String(),
      'distance_km': state.totalDistKm > 0 ? state.totalDistKm : null,
      'duration_min': duration,
      'avg_speed_kmh': avgSpeed,
      'polyline': polyline,
      'name':
          '${state.startCity ?? 'Unknown'} → ${endCity ?? 'Unknown'}',
      'is_destination': isDestination,
    }).eq('id', state.activeRouteId!);

    if (state.totalDistKm > 0) {
      try {
        final u = await sb
            .from('users')
            .select('total_distance_km')
            .eq('id', userId)
            .single();
        final cur = (u['total_distance_km'] as num?)?.toDouble() ?? 0;
        await sb
            .from('users')
            .update({'total_distance_km': cur + state.totalDistKm})
            .eq('id', userId);
      } catch (_) {}
    }
  } catch (_) {
  } finally {
    state.reset();
  }
}

Future<void> _restoreOpenRoute(SupabaseClient sb, _TrackState state) async {
  final userId = sb.auth.currentUser?.id;
  if (userId == null) return;

  try {
    final openRoute = await sb
        .from('routes')
        .select('id, started_at, start_city, distance_km, polyline')
        .eq('user_id', userId)
        .isFilter('ended_at', null)
        .order('started_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (openRoute == null) return;

    state.activeRouteId = openRoute['id'] as int;
    state.startCity = openRoute['start_city'] as String?;
    state.totalDistKm = (openRoute['distance_km'] as num?)?.toDouble() ?? 0.0;

    final startedAtRaw = openRoute['started_at'] as String?;
    if (startedAtRaw != null && startedAtRaw.isNotEmpty) {
      state.routeStart = DateTime.tryParse(startedAtRaw) ?? DateTime.now();
    }

    final polylineRaw = openRoute['polyline'];
    if (polylineRaw is String && polylineRaw.isNotEmpty) {
      final decoded = jsonDecode(polylineRaw);
      if (decoded is List) {
        state.points.clear();
        for (final point in decoded) {
          if (point is List && point.length >= 2) {
            final lat = (point[0] as num?)?.toDouble();
            final lng = (point[1] as num?)?.toDouble();
            if (lat != null && lng != null) {
              state.points.add([lat, lng]);
            }
          }
        }
      }
    }
  } catch (_) {}
}

Future<void> _syncRouteProgress(SupabaseClient sb, _TrackState state) async {
  if (state.activeRouteId == null) return;

  try {
    await sb.from('routes').update({
      'distance_km': state.totalDistKm > 0 ? state.totalDistKm : null,
      'polyline': jsonEncode(state.points),
    }).eq('id', state.activeRouteId!);
  } catch (_) {}
}

bool _isValidSegment({
  required double segmentMeters,
  required Position previous,
  required Position current,
}) {
  if (segmentMeters < 5) return false;

  final prevTs = previous.timestamp;
  final currTs = current.timestamp;
  final seconds = currTs.difference(prevTs).inSeconds;
  if (seconds > 0) {
    final speedKmh = (segmentMeters / seconds) * 3.6;
    if (speedKmh > 220) return false;
  } else if (segmentMeters > 10000) {
    return false;
  }

  return true;
}

void _appendPoint(Position pos, _TrackState state) {
  if (state.points.isNotEmpty) {
    final last = state.points.last;
    if (last[0] == pos.latitude && last[1] == pos.longitude) return;
  }
  state.points.add([pos.latitude, pos.longitude]);
}

void _checkDestination(
  Position pos,
  ServiceInstance service,
  SupabaseClient sb,
  _TrackState state,
) {
  if (state.anchor == null || state.anchorStart == null) {
    state.anchor = pos;
    state.anchorStart = DateTime.now();
    return;
  }
  final distM = Geolocator.distanceBetween(
    state.anchor!.latitude, state.anchor!.longitude,
    pos.latitude, pos.longitude,
  );
  if (distM > 400) {
    state.anchor = pos;
    state.anchorStart = DateTime.now();
  } else if (DateTime.now().difference(state.anchorStart!) >=
      const Duration(hours: 4)) {
    // User stayed in a small area for 4h -> destination reached.
    _endRoute(sb, state, isDestination: true);
    state.anchor = null;
    state.anchorStart = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  New-places tracker (villages / cities / countries / states)
// ─────────────────────────────────────────────────────────────────────────────
Future<void> _checkNewPlaces(
  String userId,
  Map<String, String?> geo,
  Position pos,
  SupabaseClient sb,
) async {
  // Village
  final village = geo['village']?.trim();
  if (village != null && village.isNotEmpty) {
    final ex = await sb
        .from('visited_villages')
        .select()
        .eq('user_id', userId)
        .eq('name', village)
        .maybeSingle();
    if (ex == null) {
      await sb.from('visited_villages').insert({
        'user_id': userId,
        'name': village,
        'country_code': geo['country_code'],
        'state': geo['state'],
        'lat': pos.latitude,
        'lng': pos.longitude,
        'xp_awarded': true,
      });
      try {
        final user = await sb
            .from('users')
            .select('villages_visited')
            .eq('id', userId)
            .single();
        final current = (user['villages_visited'] as num?)?.toInt() ?? 0;
        await sb
            .from('users')
            .update({'villages_visited': current + 1})
            .eq('id', userId);
      } catch (_) {}
    }
  }

  // City
  final city = geo['city']?.trim();
  if (city != null && city.isNotEmpty && village == null) {
    final ex = await sb
        .from('visited_cities')
        .select()
        .eq('user_id', userId)
        .eq('name', city)
        .maybeSingle();
    if (ex == null) {
      await sb.from('visited_cities').insert({
        'user_id': userId,
        'name': city,
        'country_code': geo['country_code'],
        'state': geo['state'],
        'lat': pos.latitude,
        'lng': pos.longitude,
        'xp_awarded': true,
      });
    }
  }

  // Country
  final cc = geo['country_code'];
  if (cc != null && cc.isNotEmpty) {
    final ex = await sb
        .from('visited_countries')
        .select()
        .eq('user_id', userId)
        .eq('country_code', cc)
        .maybeSingle();
    if (ex == null) {
      await sb.from('visited_countries').insert({
        'user_id': userId,
        'name': geo['country'] ?? '',
        'country_code': cc,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'xp_awarded': true,
      });
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Notification helper
// ─────────────────────────────────────────────────────────────────────────────
void _notify(AndroidServiceInstance service, String title, String content) {
  service.setForegroundNotificationInfo(title: title, content: content);
}

String _intervalLabel(int seconds) {
  if (seconds <= 0) return 'continuous';
  final minutes = (seconds / 60).round();
  return 'every $minutes min';
}

// ─────────────────────────────────────────────────────────────────────────────
//  Lightweight Nominatim reverse-geocode (dart:io only, no plugins)
// ─────────────────────────────────────────────────────────────────────────────
Future<Map<String, String?>> _reverseGeocode(double lat, double lng) async {
  try {
    final client = io.HttpClient();
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/reverse'
      '?format=json&lat=$lat&lon=$lng&zoom=14&addressdetails=1',
    );
    final request = await client.getUrl(uri);
    request.headers.set('User-Agent', 'TrailSync/1.0 (flutter-bg)');
    final response = await request.close();
    final body = await response.transform(const Utf8Decoder()).join();
    client.close();
    if (response.statusCode != 200) return {};
    final data = jsonDecode(body) as Map<String, dynamic>;
    final addr = (data['address'] as Map<String, dynamic>?) ?? {};
    return {
      'village': addr['village']?.toString() ??
          addr['hamlet']?.toString() ??
          addr['suburb']?.toString(),
      'city': addr['city']?.toString() ??
          addr['town']?.toString() ??
          addr['municipality']?.toString(),
      'town': addr['town']?.toString(),
      'state': addr['state']?.toString(),
      'country': addr['country']?.toString(),
      'country_code':
          (addr['country_code']?.toString() ?? '').toUpperCase(),
    };
  } catch (_) {
    return {};
  }
}
