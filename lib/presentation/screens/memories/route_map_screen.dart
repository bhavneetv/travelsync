import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';

class RoutePassPlace {
  final String name;
  final String type; // city | village | place

  const RoutePassPlace({required this.name, required this.type});
}

final routePlacesProvider = FutureProvider.autoDispose
    .family<List<RoutePassPlace>, Map<String, dynamic>>((ref, routeData) async {
  final userId = routeData['user_id'] as String?;
  final startedAtStr = routeData['started_at'] as String?;
  final endedAtStr = routeData['ended_at'] as String?;

  if (userId == null || startedAtStr == null) return [];

  var query = AppConstants.supabase
      .from('travel_logs')
      .select('city')
      .eq('user_id', userId)
      .gte('recorded_at', startedAtStr);

  if (endedAtStr != null) {
    query = query.lte('recorded_at', endedAtStr);
  }

  final data = await query.order('recorded_at', ascending: true);

  // Preserve chronological order of unique places.
  final List<String> orderedNames = [];
  final Set<String> seen = {};
  for (final row in data) {
    final city = row['city'] as String?;
    if (city != null && city.isNotEmpty) {
      if (seen.add(city)) {
        orderedNames.add(city);
      }
    }
  }

  if (orderedNames.isEmpty) return [];

  // Classify each passed place as city or village where possible.
  final cityRows = await AppConstants.supabase
      .from('visited_cities')
      .select('name')
      .eq('user_id', userId)
      .inFilter('name', orderedNames);
  final villageRows = await AppConstants.supabase
      .from('visited_villages')
      .select('name')
      .eq('user_id', userId)
      .inFilter('name', orderedNames);

  final citySet = (cityRows as List)
      .map((row) => row['name'] as String?)
      .where((name) => name != null && name.isNotEmpty)
      .cast<String>()
      .toSet();
  final villageSet = (villageRows as List)
      .map((row) => row['name'] as String?)
      .where((name) => name != null && name.isNotEmpty)
      .cast<String>()
      .toSet();

  return orderedNames.map((name) {
    final type = villageSet.contains(name)
        ? 'village'
        : citySet.contains(name)
            ? 'city'
            : 'place';
    return RoutePassPlace(name: name, type: type);
  }).toList();
});

final routeTrackPointsProvider = FutureProvider.autoDispose
    .family<List<LatLng>, Map<String, dynamic>>((ref, routeData) async {
  final userId = routeData['user_id'] as String?;
  final startedAtStr = routeData['started_at'] as String?;
  final endedAtStr = routeData['ended_at'] as String?;
  if (userId == null || startedAtStr == null) return [];

  var query = AppConstants.supabase
      .from('travel_logs')
      .select('latitude,longitude')
      .eq('user_id', userId)
      .gte('recorded_at', startedAtStr);

  if (endedAtStr != null) {
    query = query.lte('recorded_at', endedAtStr);
  }

  final rows = await query.order('recorded_at', ascending: true).limit(3000);
  final points = <LatLng>[];
  for (final row in rows) {
    final lat = (row['latitude'] as num?)?.toDouble();
    final lng = (row['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) continue;
    points.add(LatLng(lat, lng));
  }
  return points;
});

class RouteMapScreen extends ConsumerWidget {
  final Map<String, dynamic> routeData;

  const RouteMapScreen({super.key, required this.routeData});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(routePlacesProvider(routeData));
    final trackPointsAsync = ref.watch(routeTrackPointsProvider(routeData));
    final logTrackPoints = trackPointsAsync.valueOrNull ?? const <LatLng>[];

    // Decode polyline
    final polylineJson = routeData['polyline'] as String?;
    final List<LatLng> polylinePoints = [];

    if (polylineJson != null && polylineJson.isNotEmpty) {
      try {
        final decoded = json.decode(polylineJson) as List;
        for (final point in decoded) {
          if (point is List && point.length >= 2) {
            polylinePoints.add(LatLng(
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ));
          }
        }
      } catch (_) {}
    }

    final renderedRoutePoints = polylinePoints.length >= 2
        ? List<LatLng>.from(polylinePoints)
        : List<LatLng>.from(logTrackPoints);

    // Get start & end positions
    final startLat = (routeData['start_lat'] as num?)?.toDouble();
    final startLng = (routeData['start_lng'] as num?)?.toDouble();
    final endLat = (routeData['end_lat'] as num?)?.toDouble();
    final endLng = (routeData['end_lng'] as num?)?.toDouble();

    if (renderedRoutePoints.length < 2 &&
        startLat != null &&
        startLng != null &&
        endLat != null &&
        endLng != null &&
        (startLat != endLat || startLng != endLng)) {
      renderedRoutePoints
        ..clear()
        ..add(LatLng(startLat, startLng))
        ..add(LatLng(endLat, endLng));
    }


    // Calculate map center and bounds
    LatLng center = const LatLng(20.5937, 78.9629); // Default: India
    double zoom = 5.0;

    if (renderedRoutePoints.isNotEmpty) {
      double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
      for (final p in renderedRoutePoints) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

      // Rough zoom calculation from lat/lng span
      final latSpan = maxLat - minLat;
      final lngSpan = maxLng - minLng;
      final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
      if (maxSpan < 0.01) {
        zoom = 15;
      } else if (maxSpan < 0.05) {
        zoom = 13;
      } else if (maxSpan < 0.1) {
        zoom = 12;
      } else if (maxSpan < 0.5) {
        zoom = 10;
      } else if (maxSpan < 1) {
        zoom = 9;
      } else if (maxSpan < 3) {
        zoom = 7;
      } else {
        zoom = 5;
      }
    } else if (startLat != null && startLng != null) {
      center = LatLng(startLat, startLng);
      zoom = 12;
    }

    // Route info
    final name = routeData['name'] as String? ?? 'Route';
    final distance = routeData['distance_km'];
    final duration = routeData['duration_min'] as int?;
    final avgSpeed = routeData['avg_speed_kmh'];
    final startCity = routeData['start_city'] as String?;
    final endCity = routeData['end_city'] as String?;
    final isDestination = routeData['is_destination'] as bool? ?? false;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: zoom,
              maxZoom: 18,
              minZoom: 3,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.osmTileUrl,
                userAgentPackageName: 'com.travelsync.app',
                maxZoom: 19,
              ),

              // Route polyline
              if (renderedRoutePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: renderedRoutePoints,
                      strokeWidth: 5.0,
                      color: const Color(0xFF6C63FF),
                      borderStrokeWidth: 2.0,
                      borderColor: const Color(0xFF4A42D9),
                    ),
                  ],
                ),

              // Start & end markers
              MarkerLayer(
                markers: [
                  // Start marker (green)
                  if (startLat != null && startLng != null)
                    Marker(
                      point: LatLng(startLat, startLng),
                      width: 44,
                      height: 44,
                      child: _buildMarker(
                        Colors.green,
                        Icons.trip_origin_rounded,
                        startCity ?? 'Start',
                      ),
                    ),
                  // End marker (red)
                  if (endLat != null && endLng != null)
                    Marker(
                      point: LatLng(endLat, endLng),
                      width: 44,
                      height: 44,
                      child: _buildMarker(
                        isDestination ? Colors.amber : Colors.redAccent,
                        isDestination
                            ? Icons.flag_rounded
                            : Icons.location_on_rounded,
                        endCity ?? 'End',
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Back button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.darkBg.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.darkBg.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom stats card
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.darkBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Drag handle
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // City-to-city info
                      if (startCity != null || endCity != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              if (startCity != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.trip_origin_rounded,
                                          color: Colors.green, size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        startCity,
                                        style: const TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (startCity != null && endCity != null)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                  child: Icon(
                                    Icons.arrow_forward_rounded,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                ),
                              if (endCity != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isDestination
                                        ? Colors.amber.withValues(alpha: 0.15)
                                        : Colors.redAccent
                                            .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isDestination
                                            ? Icons.flag_rounded
                                            : Icons.location_on_rounded,
                                        color: isDestination
                                            ? Colors.amber
                                            : Colors.redAccent,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        endCity,
                                        style: TextStyle(
                                          color: isDestination
                                              ? Colors.amber
                                              : Colors.redAccent,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isDestination)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.amber.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      '🏁 Destination',
                                      style: TextStyle(
                                        color: Colors.amber,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                      // Stats row
                      Row(
                        children: [
                          _buildStat(
                            icon: Icons.straighten_rounded,
                            label: 'Distance',
                            value: distance != null
                                ? '${(distance is num ? distance.toStringAsFixed(1) : distance)} km'
                                : '—',
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 12),
                          _buildStat(
                            icon: Icons.timer_outlined,
                            label: 'Duration',
                            value: duration != null
                                ? _formatDuration(duration)
                                : '—',
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 12),
                          _buildStat(
                            icon: Icons.speed_rounded,
                            label: 'Avg Speed',
                            value: avgSpeed != null
                                ? '${(avgSpeed is num ? avgSpeed.toStringAsFixed(1) : avgSpeed)} km/h'
                                : '—',
                            color: AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Crossed places
                      placesAsync.when(
                        data: (places) {
                          if (places.isEmpty) return const SizedBox.shrink();
                          final villageCount =
                              places.where((p) => p.type == 'village').length;
                          final cityCount =
                              places.where((p) => p.type == 'city').length;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Passed through ${places.length} places ($cityCount cities, $villageCount villages)',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: places
                                      .map((place) => Container(
                                            margin:
                                                const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: AppColors.darkSurface,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color: AppColors.textSecondary
                                                    .withValues(alpha: 0.2),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  place.type == 'village'
                                                      ? Icons
                                                          .holiday_village_rounded
                                                      : place.type == 'city'
                                                          ? Icons
                                                              .location_city_rounded
                                                          : Icons
                                                              .location_on_rounded,
                                                  size: 13,
                                                  color: place.type == 'village'
                                                      ? AppColors.success
                                                      : place.type == 'city'
                                                          ? AppColors.accent
                                                          : AppColors
                                                              .textSecondary,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  place.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                          );
                        },
                        loading: () => const Center(
                            child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarker(Color color, IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ],
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }
}
