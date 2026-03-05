import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/location_service.dart';
import '../../../services/api_services.dart';
import '../../../services/xp_service.dart';

final weatherProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final position = ref.watch(currentPositionProvider);
  if (position == null) return null;
  final weather = WeatherService();
  return weather.getCurrentWeather(position.latitude, position.longitude);
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _trackingActionInProgress = false;
  bool _locatingInProgress = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _toggleTracking(bool isTracking) async {
    if (_trackingActionInProgress) return;
    _trackingActionInProgress = true;
    final locService = ref.read(locationServiceProvider);
    try {
      if (isTracking) {
        locService.stopTracking();
        return;
      }

      final started = await locService.startTracking();
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Enable location services and grant location permission to start tracking.',
            ),
          ),
        );
      }
    } finally {
      _trackingActionInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(currentPositionProvider);
    final isTracking = ref.watch(isTrackingProvider);
    final userAsync = ref.watch(currentUserProvider);
    final weatherAsync = ref.watch(weatherProvider);

    final center = position != null
        ? LatLng(position.latitude, position.longitude)
        : const LatLng(20.5937, 78.9629); // Default: India

    return Scaffold(
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: position != null ? 14.0 : 4.0,
              onMapReady: () => _mapReady = true,
            ),
            children: [
              TileLayer(
                urlTemplate: AppConstants.osmTileUrl,
                userAgentPackageName: 'com.travelsync.app',
              ),
              if (position != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(position.latitude, position.longitude),
                      width: 60,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary.withValues(alpha: 0.2),
                          border: Border.all(
                            color: AppColors.primary,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Top bar overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Status bar
                  Row(
                    children: [
                      // User greeting card
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.darkBg.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 15,
                              ),
                            ],
                          ),
                          child: userAsync.when(
                            data: (userData) {
                              final user = userData;
                              return Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.flight_takeoff_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hi, ${user?.fullName ?? user?.username ?? 'Traveler'}!',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        'Lv.${user?.travelLevel ?? 1} ${XPService.getLevelName(user?.travelLevel ?? 1)}',
                                        style: TextStyle(
                                          color: AppColors.gold,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                            },
                            loading: () => const SizedBox(
                              height: 40,
                              child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            error: (_, __) => const Text('Error'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Settings button
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.darkBg.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: IconButton(
                          onPressed: () => context.push('/settings'),
                          icon: const Icon(
                            Icons.settings_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Weather card
                  weatherAsync.when(
                    data: (weather) {
                      if (weather == null) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.darkBg.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              weather['icon'] as String,
                              style: const TextStyle(fontSize: 24),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${weather['temperature']}°C',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              weather['description'] as String,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              children: [
                // My location button
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.darkBg.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () async {
                        if (_locatingInProgress) return;
                        _locatingInProgress = true;
                        final locService = ref.read(locationServiceProvider);
                        try {
                          final pos = await locService.getCurrentPosition();
                          if (pos != null && _mapReady) {
                            _mapController.move(
                              LatLng(pos.latitude, pos.longitude),
                              15,
                            );
                          }
                        } finally {
                          _locatingInProgress = false;
                        }
                      },
                      icon: const Icon(
                        Icons.my_location_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tracking toggle
                GestureDetector(
                  onTap: () => _toggleTracking(isTracking),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: isTracking
                          ? AppColors.accentGradient
                          : AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: (isTracking ? AppColors.accent : AppColors.primary)
                              .withValues(alpha: 0.4),
                          blurRadius: 25,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isTracking
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isTracking ? 'Tracking Active' : 'Start Tracking',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
