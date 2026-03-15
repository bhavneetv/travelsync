import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/models/travel_memory.dart';
import '../../../services/memory_service.dart';
import 'route_map_screen.dart';

/// Provider to fetch routes related to a city (by city name or coordinates)
final routesForCityProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, PlaceCityQuery>((ref, query) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final placeName = query.cityName.trim();
  final merged = <int, Map<String, dynamic>>{};

  // 1) Name-based matches (case-insensitive, partial).
  if (placeName.isNotEmpty) {
    try {
      final pattern = '%$placeName%';
      final startRoutes = await AppConstants.supabase
          .from('routes')
          .select()
          .eq('user_id', userId)
          .ilike('start_city', pattern)
          .order('started_at', ascending: false)
          .limit(100);
      final endRoutes = await AppConstants.supabase
          .from('routes')
          .select()
          .eq('user_id', userId)
          .ilike('end_city', pattern)
          .order('started_at', ascending: false)
          .limit(100);
      for (final r in startRoutes) {
        merged[r['id'] as int] = Map<String, dynamic>.from(r);
      }
      for (final r in endRoutes) {
        merged[r['id'] as int] = Map<String, dynamic>.from(r);
      }
    } catch (_) {
      // Ignore and continue to coordinate fallback.
    }
  }

  // 2) Coordinate fallback: include both start and end near this place.
  if (query.lat != null && query.lng != null) {
    try {
      const delta = 0.5; // ~55km; forgiving for sparse geocoding points.
      final startNearby = await AppConstants.supabase
          .from('routes')
          .select()
          .eq('user_id', userId)
          .gte('start_lat', query.lat! - delta)
          .lte('start_lat', query.lat! + delta)
          .gte('start_lng', query.lng! - delta)
          .lte('start_lng', query.lng! + delta)
          .order('started_at', ascending: false)
          .limit(100);
      final endNearby = await AppConstants.supabase
          .from('routes')
          .select()
          .eq('user_id', userId)
          .gte('end_lat', query.lat! - delta)
          .lte('end_lat', query.lat! + delta)
          .gte('end_lng', query.lng! - delta)
          .lte('end_lng', query.lng! + delta)
          .order('started_at', ascending: false)
          .limit(100);
      for (final r in startNearby) {
        merged[r['id'] as int] = Map<String, dynamic>.from(r);
      }
      for (final r in endNearby) {
        merged[r['id'] as int] = Map<String, dynamic>.from(r);
      }
    } catch (_) {
      // Continue to generic fallback.
    }
  }

  // 3) Pass-through fallback: routes whose time window includes logs from this place.
  if (placeName.isNotEmpty) {
    try {
      final pattern = '%$placeName%';
      final placeLogs = await AppConstants.supabase
          .from('travel_logs')
          .select('recorded_at')
          .eq('user_id', userId)
          .ilike('city', pattern)
          .order('recorded_at', ascending: false)
          .limit(300);

      if ((placeLogs as List).isNotEmpty) {
        final routePool = await AppConstants.supabase
            .from('routes')
            .select()
            .eq('user_id', userId)
            .order('started_at', ascending: false)
            .limit(300);

        final logTimes = placeLogs
            .map((l) => l['recorded_at'] as String?)
            .where((t) => t != null && t.isNotEmpty)
            .map((t) => DateTime.parse(t!))
            .toList();

        for (final r in routePool) {
          final startedAtStr = r['started_at'] as String?;
          if (startedAtStr == null || startedAtStr.isEmpty) continue;
          final startedAt = DateTime.tryParse(startedAtStr);
          if (startedAt == null) continue;
          final endedAtStr = r['ended_at'] as String?;
          final endedAt =
              endedAtStr != null ? DateTime.tryParse(endedAtStr) : null;
          final windowEnd = endedAt ?? startedAt.add(const Duration(hours: 24));

          final hasIntersection = logTimes.any(
            (t) => !t.isBefore(startedAt) && !t.isAfter(windowEnd),
          );
          if (hasIntersection) {
            merged[r['id'] as int] = Map<String, dynamic>.from(r);
          }
        }
      }
    } catch (_) {
      // Ignore and continue.
    }
  }

  // 4) Final fallback: recent routes so memories page never looks empty.
  if (merged.isEmpty) {
    final data = await AppConstants.supabase
        .from('routes')
        .select()
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(data);
  }

  final results = merged.values.toList();
  results.sort((a, b) {
    final aTime = a['started_at'] as String?;
    final bTime = b['started_at'] as String?;
    if (aTime == null || bTime == null) return 0;
    return bTime.compareTo(aTime);
  });
  return results;
});

class PlaceCityQuery {
  final String cityName;
  final double? lat;
  final double? lng;

  const PlaceCityQuery({required this.cityName, this.lat, this.lng});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaceCityQuery &&
          cityName == other.cityName &&
          lat == other.lat &&
          lng == other.lng;

  @override
  int get hashCode => cityName.hashCode ^ (lat?.hashCode ?? 0) ^ (lng?.hashCode ?? 0);
}

class PlaceDetailScreen extends ConsumerStatefulWidget {
  final String cityName;
  final String placeType;
  final String stateName;
  final String countryName;
  final String countryCode;
  final double? lat;
  final double? lng;

  const PlaceDetailScreen({
    super.key,
    required this.cityName,
    this.placeType = 'city',
    required this.stateName,
    required this.countryName,
    required this.countryCode,
    this.lat,
    this.lng,
  });

  @override
  ConsumerState<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends ConsumerState<PlaceDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _uploadMemory() async {
    final service = ref.read(memoryServiceProvider);

    // Show source picker
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add Memory',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.camera_alt_rounded,
                    color: AppColors.primary),
              ),
              title: const Text('Take Photo',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text('Use camera',
                  style: TextStyle(color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.photo_library_rounded,
                    color: AppColors.accent),
              ),
              title: const Text('Choose from Gallery',
                  style: TextStyle(color: Colors.white)),
              subtitle: Text('Pick existing photo',
                  style: TextStyle(color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final file = await service.pickImage(fromCamera: source == 'camera');
    if (file == null || !mounted) return;

    // Show caption dialog
    final caption = await _showCaptionDialog(file);
    if (!mounted) return;

    // Upload with loading indicator
    TravelMemory? memory;
    var uploadDialogShown = false;
    _showUploadingDialog();
    uploadDialogShown = true;

    try {
      memory = await service.uploadMemory(
        imageFile: file,
        caption: caption,
        placeType: widget.placeType,
        placeName: widget.cityName,
        countryCode: widget.countryCode,
        lat: widget.lat,
        lng: widget.lng,
      );
    } catch (_) {
      memory = null;
    } finally {
      if (mounted && uploadDialogShown) {
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop();
        uploadDialogShown = false;
      }
    }

    if (mounted) {
      if (memory != null) {
        // Refresh memories
        ref.invalidate(memoriesProvider);
        ref.invalidate(latestMemoryProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Memory saved!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to upload memory'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
    }
  }

  Future<String?> _showCaptionDialog(File imageFile) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  imageFile,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Add a caption (optional)',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: Text('Skip',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUploadingDialog() {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: AppColors.darkCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: const Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 20),
              Text(
                'Uploading memory...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a contextual route label relative to this city
  String _getContextualRouteLabel(Map<String, dynamic> route) {
    final startCity = route['start_city'] as String?;
    final endCity = route['end_city'] as String?;
    final currentCity = widget.cityName;
    final isDestination = route['is_destination'] as bool? ?? false;

    // If this city is the start city, show "To {endCity}"
    if (startCity != null &&
        startCity.toLowerCase() == currentCity.toLowerCase()) {
      final dest = endCity ?? 'Unknown';
      return isDestination ? 'To $dest 🏁' : 'To $dest';
    }

    // If this city is the end city, show "From {startCity}"
    if (endCity != null &&
        endCity.toLowerCase() == currentCity.toLowerCase()) {
      return 'From ${startCity ?? 'Unknown'}';
    }

    // Default: just show route name
    return route['name'] as String? ?? 'Route';
  }

  IconData _getContextualIcon(Map<String, dynamic> route) {
    final startCity = route['start_city'] as String?;
    final endCity = route['end_city'] as String?;
    final currentCity = widget.cityName;

    if (startCity != null &&
        startCity.toLowerCase() == currentCity.toLowerCase()) {
      return Icons.flight_takeoff_rounded; // Departure
    }

    if (endCity != null &&
        endCity.toLowerCase() == currentCity.toLowerCase()) {
      return Icons.flight_land_rounded; // Arrival
    }

    return Icons.route_rounded;
  }

  Color _getContextualColor(Map<String, dynamic> route) {
    final startCity = route['start_city'] as String?;
    final endCity = route['end_city'] as String?;
    final currentCity = widget.cityName;
    final isDestination = route['is_destination'] as bool? ?? false;

    if (endCity != null &&
        endCity.toLowerCase() == currentCity.toLowerCase()) {
      return isDestination ? Colors.amber : AppColors.primary;
    }

    if (startCity != null &&
        startCity.toLowerCase() == currentCity.toLowerCase()) {
      return AppColors.accent;
    }

    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final memoriesAsync = ref.watch(memoriesProvider(
      MemoryQuery(placeType: widget.placeType, placeName: widget.cityName),
    ));
    final routesAsync = ref.watch(routesForCityProvider(
      PlaceCityQuery(
          cityName: widget.cityName, lat: widget.lat, lng: widget.lng),
    ));

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppColors.darkBg,
            leading: IconButton(
              onPressed: () => context.pop(),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.darkBg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.cityName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFFFF6B6B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: -20,
                      bottom: -10,
                      child: Icon(
                        Icons.photo_camera_rounded,
                        size: 150,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Breadcrumb
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.go('/memories'),
                      child: Text(widget.countryName,
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary, size: 16),
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Text(widget.stateName,
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textSecondary, size: 16),
                    Text(widget.cityName,
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),

          // Tab bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: Colors.white,
                  unselectedLabelColor: AppColors.textSecondary,
                  dividerColor: Colors.transparent,
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14),
                  tabs: const [
                    Tab(text: '📸 Memories'),
                    Tab(text: '🗺️ Routes'),
                  ],
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            // Memories tab
            memoriesAsync.when(
              data: (memories) {
                if (memories.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_album_rounded,
                            size: 60,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No memories yet',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap + to add your first memory',
                          style: TextStyle(
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: memories.length,
                  itemBuilder: (context, index) {
                    final memory = memories[index];
                    return GestureDetector(
                      onTap: () {
                        context.push(
                          '/memories/viewer?index=$index&placeType=${widget.placeType}&placeName=${widget.cityName}',
                        );
                      },
                      child: Hero(
                        tag: 'memory_${memory.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: CachedNetworkImage(
                            imageUrl: memory.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppColors.darkSurface,
                              child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: AppColors.darkSurface,
                              child: const Icon(Icons.broken_image_rounded,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),

            // Routes tab
            routesAsync.when(
              data: (routes) {
                if (routes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.route_rounded,
                            size: 60,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'No routes recorded for this city',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: routes.length,
                  itemBuilder: (context, index) {
                    final route = routes[index];
                    final contextLabel = _getContextualRouteLabel(route);
                    final contextIcon = _getContextualIcon(route);
                    final contextColor = _getContextualColor(route);
                    final distance = route['distance_km'];
                    final duration = route['duration_min'] as int?;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: AppColors.cardGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: contextColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              contextIcon,
                              color: contextColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  contextLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (distance != null) ...[
                                      Text(
                                        '${(distance is num ? distance.toStringAsFixed(1) : distance)} km',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                    ],
                                    if (duration != null)
                                      Text(
                                        '${duration}m',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          // View Route button
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RouteMapScreen(routeData: route),
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.map_rounded,
                                      color: AppColors.primary, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'View Route',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ],
        ),
      ),

      // FAB for uploading memory
      floatingActionButton: FloatingActionButton(
        onPressed: _uploadMemory,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_a_photo_rounded, color: Colors.white),
      ),
    );
  }
}
