import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../services/location_service.dart';
import '../../../services/api_services.dart';
import '../../../services/xp_service.dart';
import '../../../services/memory_service.dart';
import '../../../data/models/travel_memory.dart';

// Backdrop blur over a live map is expensive on many Android devices.
const bool _enableLiveBlurEffects = false;

final weatherProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((
  ref,
) async {
  final position = ref.watch(currentPositionProvider);
  if (position == null) return null;
  // Reduce weather refresh churn while tracking by snapping to ~5km buckets.
  final latBucket = (position.latitude * 20).round() / 20.0;
  final lngBucket = (position.longitude * 20).round() / 20.0;
  final weather = WeatherService();
  return weather.getCurrentWeather(latBucket, lngBucket);
});

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  AI Suggestion model
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class PlaceSuggestion {
  final String name;
  final String category; // food | rest | attraction
  final String emoji;
  final String distance;
  final double rating;

  const PlaceSuggestion({
    required this.name,
    required this.category,
    required this.emoji,
    required this.distance,
    required this.rating,
  });
}

// Dummy suggestions â€” replace with real API call
final _demoSuggestions = [
  PlaceSuggestion(
    name: 'Spice Garden',
    category: 'food',
    emoji: 'ðŸ›',
    distance: '0.8 km',
    rating: 4.6,
  ),
  PlaceSuggestion(
    name: 'The Brew Bar',
    category: 'food',
    emoji: 'â˜•',
    distance: '1.2 km',
    rating: 4.4,
  ),
  PlaceSuggestion(
    name: 'City Inn',
    category: 'rest',
    emoji: 'ðŸ¨',
    distance: '2.1 km',
    rating: 4.7,
  ),
  PlaceSuggestion(
    name: 'Lotus Retreat',
    category: 'rest',
    emoji: 'ðŸ§˜',
    distance: '3.4 km',
    rating: 4.5,
  ),
  PlaceSuggestion(
    name: 'Heritage Fort',
    category: 'attraction',
    emoji: 'ðŸ°',
    distance: '4.2 km',
    rating: 4.8,
  ),
  PlaceSuggestion(
    name: 'Sunset Viewpoint',
    category: 'attraction',
    emoji: 'ðŸŒ…',
    distance: '4.9 km',
    rating: 4.9,
  ),
];

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
//  Home Screen
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _mapReady = false;
  bool _locatingInProgress = false;
  bool _memoryInProgress = false;

  // Selected marker on map
  LatLng? _selectedPoint;
  bool _showPlaceCard = false;

  // Animation controller for bottom sheet
  late final AnimationController _sheetAnim;
  late final Animation<double> _sheetSlide;

  @override
  void initState() {
    super.initState();
    _sheetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _sheetSlide = CurvedAnimation(
      parent: _sheetAnim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _sheetAnim.dispose();
    super.dispose();
  }

  // â”€â”€ map tap â”€â”€
  void _onMapTap(TapPosition tapPos, LatLng point) {
    setState(() {
      _selectedPoint = point;
      _showPlaceCard = true;
    });
    _sheetAnim.forward(from: 0);
  }

  void _dismissCard() {
    _sheetAnim.reverse().then((_) {
      if (mounted) setState(() => _showPlaceCard = false);
    });
  }

  // â”€â”€ AI Suggestions sheet â”€â”€
  Future<void> _showAISuggestions() async {
    final locService = ref.read(locationServiceProvider);
    var position = ref.read(currentPositionProvider);
    position ??= await locService.getCurrentPosition();
    if (!mounted) return;

    List<PlaceSuggestion> suggestions = _demoSuggestions;
    var loaderShown = false;
    if (position != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      loaderShown = true;
      try {
        final nearby = await OverpassService().getNearbySuggestions(
          position.latitude,
          position.longitude,
          radiusMeters: 5000,
          limit: 24,
        );
        if (nearby.isNotEmpty) {
          suggestions = nearby
              .map(
                (s) => PlaceSuggestion(
                  name: s.name,
                  category: s.category,
                  emoji: s.emoji,
                  distance: '${s.distanceKm.toStringAsFixed(1)} km',
                  rating: s.rating,
                ),
              )
              .toList();
        }
      } catch (_) {
        // Keep demo suggestions as fallback.
      } finally {
        if (mounted && loaderShown) {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
          loaderShown = false;
        }
      }
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AISuggestionsSheet(suggestions: suggestions),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  Memory capture
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _captureMemory() async {
    if (_memoryInProgress) return;
    _memoryInProgress = true;
    try {
      final service = ref.read(memoryServiceProvider);
      final position = ref.read(currentPositionProvider);

      final source = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => const _MemorySourceSheet(),
      );

      if (source == null || !mounted) return;

      final file = await service.pickImage(fromCamera: source == 'camera');
      if (file == null || !mounted) return;

      double? lat = position?.latitude;
      double? lng = position?.longitude;
      String placeName = 'Unknown location';
      String placeType = 'city';
      String? countryCode;

      if (lat != null && lng != null) {
        final nominatim = NominatimService();
        final geoData = await nominatim.reverseGeocode(lat, lng);
        placeName =
            geoData['village'] ??
            geoData['city'] ??
            geoData['place_name'] ??
            'Unknown location';
        placeType = geoData['village'] != null ? 'village' : 'city';
        countryCode = geoData['country_code'];
      }

      if (!mounted) return;
      final caption = await _showCaptionDialog(file, placeName);
      if (!mounted) return;

      TravelMemory? memory;
      var uploadDialogShown = false;
      _showUploadingDialog();
      uploadDialogShown = true;

      try {
        memory = await service.uploadMemory(
          imageFile: file,
          caption: caption,
          placeType: placeType,
          placeName: placeName,
          countryCode: countryCode,
          lat: lat,
          lng: lng,
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
          ref.invalidate(memoriesProvider);
          ref.invalidate(latestMemoryProvider);
          _showToast('âœ¨ Memory saved at $placeName!', isSuccess: true);
        } else {
          _showToast('Failed to upload memory', isSuccess: false);
        }
      }
    } finally {
      _memoryInProgress = false;
    }
  }

  void _showToast(String message, {required bool isSuccess}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontFamily: 'SF Pro Display',
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isSuccess
            ? const Color(0xFF30D158)
            : const Color(0xFFFF453A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
    );
  }

  Future<String?> _showCaptionDialog(File imageFile, String placeName) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E).withOpacity(0.92),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(
                      imageFile,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.location_fill,
                        color: Color(0xFFFF9F0A),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          placeName,
                          style: const TextStyle(
                            color: Color(0xFFFF9F0A),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    placeholderStyle: const TextStyle(color: Color(0xFF8E8E93)),
                    placeholder: 'Add a captionâ€¦',
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C2C2E),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => Navigator.pop(ctx, null),
                          child: const Text(
                            'Skip',
                            style: TextStyle(color: Color(0xFF8E8E93)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PillButton(
                          label: 'Save',
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0A84FF), Color(0xFF0066CC)],
                          ),
                          onTap: () =>
                              Navigator.pop(ctx, controller.text.trim()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E).withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(
                    radius: 16,
                    color: Color(0xFF0A84FF),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'Saving memoryâ€¦',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  //  BUILD
  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  @override
  Widget build(BuildContext context) {
    final position = ref.watch(currentPositionProvider);
    final isTracking = ref.watch(isTrackingProvider);

    final center = position != null
        ? LatLng(position.latitude, position.longitude)
        : const LatLng(20.5937, 78.9629);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // â”€â”€ Full-screen map â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          RepaintBoundary(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: position != null ? 15.0 : 4.0,
                onMapReady: () => _mapReady = true,
                onTap: _onMapTap,
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
                        width: 56,
                        height: 56,
                        child: const _PulseMarker(),
                      ),
                    ],
                  ),
                if (_selectedPoint != null && _showPlaceCard)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedPoint!,
                        width: 40,
                        height: 40,
                        child: const _TapMarker(),
                      ),
                    ],
                  ),
              ],
            ),
          ),

          // â”€â”€ Top gradient scrim â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 180,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // â”€â”€ Bottom gradient scrim â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 160,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // â”€â”€ TOP BAR â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Weather pill (left)
                  const _WeatherChip(),

                  const Spacer(),

                  // Right cluster: Profile | GPS | Settings
                  Row(
                    children: [
                      // Profile avatar
                      const _ProfileButton(),

                      const SizedBox(width: 8),

                      // GPS indicator
                      _GlassIconButton(
                        icon: isTracking
                            ? CupertinoIcons.location_fill
                            : CupertinoIcons.location_slash_fill,
                        color: isTracking
                            ? const Color(0xFF30D158)
                            : const Color(0xFF636366),
                        onTap: () {}, // toggle tracking if desired
                      ),

                      const SizedBox(width: 8),

                      // Settings
                      _GlassIconButton(
                        icon: CupertinoIcons.settings,
                        color: Colors.white,
                        onTap: () => context.push('/settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // â”€â”€ PLACE CARD (on map tap) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (_showPlaceCard)
            Positioned(
              left: 16,
              right: 16,
              bottom: 110,
              child: AnimatedBuilder(
                animation: _sheetSlide,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, 24 * (1 - _sheetSlide.value)),
                  child: Opacity(opacity: _sheetSlide.value, child: child),
                ),
                child: _MapTapCard(
                  point: _selectedPoint!,
                  onDismiss: _dismissCard,
                  onAddMemory: _captureMemory,
                ),
              ),
            ),

          // â”€â”€ BOTTOM CONTROLS â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (!_showPlaceCard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Left: Memories icon
                      _BottomFab(
                        icon: CupertinoIcons.photo_on_rectangle,
                        label: 'Memories',
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF9F0A), Color(0xFFFF6B00)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        onTap: _captureMemory,
                      ),

                      // Center: My location
                      _GlassIconButton(
                        icon: CupertinoIcons.location_fill,
                        color: const Color(0xFF0A84FF),
                        size: 44,
                        onTap: () async {
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
                      ),

                      // Right: AI Suggest icon
                      _BottomFab(
                        icon: CupertinoIcons.sparkles,
                        label: 'AI Suggest',
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5E5CE6), Color(0xFF0A84FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        onTap: _showAISuggestions,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  SUBWIDGETS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

// â”€â”€ Pulsing location marker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PulseMarker extends StatelessWidget {
  const _PulseMarker();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0A84FF).withOpacity(0.2),
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF0A84FF),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A84FF).withOpacity(0.35),
                blurRadius: 8,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Tap marker pin â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _TapMarker extends StatelessWidget {
  const _TapMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF453A),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF453A).withOpacity(0.5),
                blurRadius: 10,
              ),
            ],
          ),
        ),
        Container(width: 2, height: 10, color: const Color(0xFFFF453A)),
      ],
    );
  }
}

class _WeatherChip extends ConsumerWidget {
  const _WeatherChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(weatherProvider);
    return weatherAsync.when(
      data: (w) {
        if (w == null) return const SizedBox.shrink();
        return _GlassChip(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(w['icon'] as String, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 5),
              Text(
                '${w['temperature']}°',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _ProfileButton extends ConsumerWidget {
  const _ProfileButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    return userAsync.when(
      data: (user) => _GlassButton(
        onTap: () => context.push('/profile'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  (user?.fullName ?? user?.username ?? 'T')
                      .substring(0, 1)
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 7),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user?.fullName ?? user?.username ?? 'Traveler',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: -0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Lv.${user?.travelLevel ?? 1} · ${XPService.getLevelName(user?.travelLevel ?? 1)}',
                  style: const TextStyle(
                    color: Color(0xFFFFD60A),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      loading: () =>
          const _GlassButton(child: CupertinoActivityIndicator(radius: 10)),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// â”€â”€ Glass chip â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GlassChip extends StatelessWidget {
  final Widget child;
  const _GlassChip({required this.child});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      child: child,
    );

    if (!_enableLiveBlurEffects) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: content,
      ),
    );
  }
}

// â”€â”€ Glass button (pressable chip) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _GlassButton({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      child: child,
    );

    return GestureDetector(
      onTap: onTap,
      child: !_enableLiveBlurEffects
          ? content
          : ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: content,
              ),
            ),
    );
  }
}

// â”€â”€ Glass icon button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 42,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );

    return GestureDetector(
      onTap: onTap,
      child: !_enableLiveBlurEffects
          ? content
          : ClipRRect(
              borderRadius: BorderRadius.circular(size / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: content,
              ),
            ),
    );
  }
}

// â”€â”€ Bottom FAB (icon only, gradient bg) â”€â”€â”€â”€â”€
class _BottomFab extends StatelessWidget {
  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _BottomFab({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient.colors.first.withOpacity(0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

// â”€â”€ Pill button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _PillButton extends StatelessWidget {
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  MAP TAP CARD
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _MapTapCard extends StatelessWidget {
  final LatLng point;
  final VoidCallback onDismiss;
  final VoidCallback onAddMemory;

  const _MapTapCard({
    required this.point,
    required this.onDismiss,
    required this.onAddMemory,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withOpacity(0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF453A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      CupertinoIcons.location_fill,
                      color: Color(0xFFFF453A),
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pinned Location',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A3A3C),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: Color(0xFF8E8E93),
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFF2C2C2E), height: 1),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  _CardAction(
                    icon: CupertinoIcons.camera_fill,
                    label: 'Memory',
                    color: const Color(0xFF0A84FF),
                    onTap: () {
                      onDismiss();
                      onAddMemory();
                    },
                  ),
                  const SizedBox(width: 10),
                  _CardAction(
                    icon: CupertinoIcons.bookmark_fill,
                    label: 'Save Spot',
                    color: const Color(0xFFFF9F0A),
                    onTap: onDismiss,
                  ),
                  const SizedBox(width: 10),
                  _CardAction(
                    icon: CupertinoIcons.location_north_fill,
                    label: 'Navigate',
                    color: const Color(0xFF30D158),
                    onTap: onDismiss,
                  ),
                  const SizedBox(width: 10),
                  _CardAction(
                    icon: CupertinoIcons.share,
                    label: 'Share',
                    color: const Color(0xFF5E5CE6),
                    onTap: onDismiss,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CardAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  MEMORY SOURCE SHEET
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _MemorySourceSheet extends StatelessWidget {
  const _MemorySourceSheet();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A3A3C),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'ðŸ“¸  Capture Memory',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Save this moment at your current location',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
              const SizedBox(height: 22),
              _SourceTile(
                emoji: 'ðŸ“·',
                title: 'Take Photo',
                subtitle: 'Open camera',
                color: const Color(0xFF0A84FF),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              const SizedBox(height: 10),
              _SourceTile(
                emoji: 'ðŸ–¼ï¸',
                title: 'Choose from Gallery',
                subtitle: 'Pick existing photo',
                color: const Color(0xFF5E5CE6),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SourceTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C2E),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              CupertinoIcons.chevron_right,
              color: Color(0xFF636366),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
//  AI SUGGESTIONS SHEET
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
class _AISuggestionsSheet extends StatefulWidget {
  final List<PlaceSuggestion> suggestions;
  const _AISuggestionsSheet({required this.suggestions});

  @override
  State<_AISuggestionsSheet> createState() => _AISuggestionsSheetState();
}

class _AISuggestionsSheetState extends State<_AISuggestionsSheet> {
  String _filter = 'all';

  static const _categories = [
    {'id': 'all', 'label': 'All', 'emoji': 'âœ¨'},
    {'id': 'food', 'label': 'Food', 'emoji': 'ðŸ½'},
    {'id': 'rest', 'label': 'Rest', 'emoji': 'ðŸ¨'},
    {'id': 'attraction', 'label': 'Travel', 'emoji': 'ðŸ—º'},
  ];

  List<PlaceSuggestion> get _filtered => _filter == 'all'
      ? widget.suggestions
      : widget.suggestions.where((s) => s.category == _filter).toList();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C1E).withOpacity(0.97),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(
                top: BorderSide(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
            ),
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
              children: [
                // Handle
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5E5CE6), Color(0xFF0A84FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.sparkles,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'AI Suggestions',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Within 5 km of you',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Category filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final active = _filter == cat['id'];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => setState(() => _filter = cat['id']!),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: active
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF5E5CE6),
                                        Color(0xFF0A84FF),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: active ? null : const Color(0xFF2C2C2E),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${cat['emoji']}  ${cat['label']}',
                              style: TextStyle(
                                color: active
                                    ? Colors.white
                                    : const Color(0xFF8E8E93),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 16),

                // Place cards
                ..._filtered.map(
                  (place) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SuggestionCard(place: place),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final PlaceSuggestion place;
  const _SuggestionCard({required this.place});

  Color get _catColor {
    switch (place.category) {
      case 'food':
        return const Color(0xFFFF9F0A);
      case 'rest':
        return const Color(0xFF30D158);
      default:
        return const Color(0xFF5E5CE6);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _catColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(place.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      CupertinoIcons.location_fill,
                      size: 12,
                      color: _catColor,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      place.distance,
                      style: TextStyle(
                        color: _catColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      CupertinoIcons.star_fill,
                      size: 12,
                      color: Color(0xFFFFD60A),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      place.rating.toString(),
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _catColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.arrow_right, color: _catColor, size: 16),
          ),
        ],
      ),
    );
  }
}
