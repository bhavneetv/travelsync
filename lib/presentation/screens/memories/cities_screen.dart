import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/memory_service.dart';
import '../../../services/haptic_service.dart';

/// Provider to fetch visited cities filtered by state
final visitedCitiesForStateProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, CityQuery>((ref, query) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];

  var cities = await AppConstants.supabase
      .from('visited_cities')
      .select()
      .eq('user_id', userId)
      .eq('state', query.stateName)
      .order('first_visited_at', ascending: false);

  if ((cities as List).isNotEmpty) {
    return List<Map<String, dynamic>>.from(cities);
  }

  final logsInState = await AppConstants.supabase
      .from('travel_logs')
      .select('city')
      .eq('user_id', userId)
      .eq('state', query.stateName)
      .not('city', 'is', null);

  final cityNames = (logsInState as List)
      .map((l) => l['city'] as String?)
      .where((c) => c != null && c.isNotEmpty)
      .toSet();

  if (cityNames.isEmpty) return [];

  final result = await AppConstants.supabase
      .from('visited_cities')
      .select()
      .eq('user_id', userId)
      .inFilter('name', cityNames.toList())
      .order('first_visited_at', ascending: false);

  return List<Map<String, dynamic>>.from(result);
});

/// Provider to fetch visited villages filtered by state
final visitedVillagesForStateProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, CityQuery>((ref, query) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];

  var villages = await AppConstants.supabase
      .from('visited_villages')
      .select()
      .eq('user_id', userId)
      .eq('state', query.stateName)
      .order('first_visited_at', ascending: false);

  if ((villages as List).isNotEmpty) {
    return List<Map<String, dynamic>>.from(villages);
  }

  final logsInState = await AppConstants.supabase
      .from('travel_logs')
      .select('city')
      .eq('user_id', userId)
      .eq('state', query.stateName)
      .not('city', 'is', null);

  final placeNames = (logsInState as List)
      .map((l) => l['city'] as String?)
      .where((c) => c != null && c.isNotEmpty)
      .toSet();

  if (placeNames.isEmpty) return [];

  final result = await AppConstants.supabase
      .from('visited_villages')
      .select()
      .eq('user_id', userId)
      .inFilter('name', placeNames.toList())
      .order('first_visited_at', ascending: false);

  return List<Map<String, dynamic>>.from(result);
});

class CityQuery {
  final String stateName;
  final String countryCode;

  const CityQuery({required this.stateName, required this.countryCode});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CityQuery &&
          stateName == other.stateName &&
          countryCode == other.countryCode;

  @override
  int get hashCode => stateName.hashCode ^ countryCode.hashCode;
}

class CitiesScreen extends ConsumerStatefulWidget {
  final String stateName;
  final String countryName;
  final String countryCode;

  const CitiesScreen({
    super.key,
    required this.stateName,
    required this.countryName,
    required this.countryCode,
  });

  @override
  ConsumerState<CitiesScreen> createState() => _CitiesScreenState();
}

class _CitiesScreenState extends ConsumerState<CitiesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isRecent(Map<String, dynamic> row) {
    DateTime? timestamp;
    const keys = [
      'last_visited_at',
      'updated_at',
      'first_visited_at',
      'created_at',
    ];
    for (final key in keys) {
      final raw = row[key];
      if (raw is String) {
        timestamp = DateTime.tryParse(raw);
        if (timestamp != null) break;
      }
    }
    if (timestamp == null) return false;
    return DateTime.now().difference(timestamp.toLocal()) <=
        const Duration(hours: 24);
  }

  bool _matchesSearch(Map<String, dynamic> row) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final name = (row['name'] as String? ?? '').toLowerCase();
    return name.contains(query);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final citiesAsync = ref.watch(visitedCitiesForStateProvider(
      CityQuery(stateName: widget.stateName, countryCode: widget.countryCode),
    ));
    final villagesAsync = ref.watch(visitedVillagesForStateProvider(
      CityQuery(stateName: widget.stateName, countryCode: widget.countryCode),
    ));

    final cities =
        citiesAsync.asData?.value ?? const <Map<String, dynamic>>[];
    final villages =
        villagesAsync.asData?.value ?? const <Map<String, dynamic>>[];
    final isLoading = citiesAsync.isLoading || villagesAsync.isLoading;
    final hasError = citiesAsync.hasError || villagesAsync.hasError;

    final filteredCities = cities.where(_matchesSearch).toList();
    final filteredVillages = villages.where(_matchesSearch).toList();

    final recentCities = filteredCities.where(_isRecent).toList();
    final recentVillages = filteredVillages.where(_isRecent).toList();

    final allCities = List<Map<String, dynamic>>.from(filteredCities);
    final allVillages = List<Map<String, dynamic>>.from(filteredVillages);

    final recentMixed = <Map<String, dynamic>>[
      ...recentCities.map((e) => {...e, '_type': 'city'}),
      ...recentVillages.map((e) => {...e, '_type': 'village'}),
    ];
    recentMixed.sort((a, b) {
      DateTime? aTime;
      DateTime? bTime;
      const keys = [
        'last_visited_at',
        'updated_at',
        'first_visited_at',
        'created_at'
      ];
      for (final key in keys) {
        final rawA = a[key];
        final rawB = b[key];
        aTime ??= rawA is String ? DateTime.tryParse(rawA) : null;
        bTime ??= rawB is String ? DateTime.tryParse(rawB) : null;
      }
      return (bTime ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(aTime ?? DateTime.fromMillisecondsSinceEpoch(0));
    });

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ────────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.lightSurface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: AppColors.textSecondary,
              onPressed: () async {
                await HapticService.selection();
                if (context.mounted) context.pop();
              },
            ),
            title: Text(
              widget.stateName,
              style: GoogleFonts.manrope(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: AppColors.border, height: 1),
            ),
          ),

          // ── Breadcrumb ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      await HapticService.selection();
                      if (context.mounted) context.go('/memories');
                    },
                    child: Text(
                      widget.countryName,
                      style: GoogleFonts.inter(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 18),
                  Text(
                    widget.stateName,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Search bar ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _searchQuery = value),
                style: GoogleFonts.inter(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search city or village...',
                  prefixIcon:
                      const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon:
                              const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
              ),
            ),
          ),

          if (isLoading && cities.isEmpty && villages.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 2.5,
                ),
              ),
            )
          else if (hasError && cities.isEmpty && villages.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'Could not load places',
                  style:
                      GoogleFonts.manrope(color: AppColors.textSecondary),
                ),
              ),
            )
          else ...[
            // ── Recent places ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: _SectionTitle(
                  title: 'Recent (24h)',
                  count: recentMixed.length,
                ),
              ),
            ),
            if (recentMixed.isEmpty)
              const SliverToBoxAdapter(
                child: _EmptySection(
                    text: 'No recent places in last 24h'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final place = recentMixed[index];
                      final isVillage = place['_type'] == 'village';
                      final name =
                          place['name'] as String? ?? 'Unknown';
                      final visitCount =
                          place['visit_count'] as int? ?? 1;
                      final lat =
                          (place['lat'] as num?)?.toDouble();
                      final lng =
                          (place['lng'] as num?)?.toDouble();

                      return _PlaceCard(
                        name: name,
                        visitCount: visitCount,
                        index: index,
                        icon: isVillage
                            ? Icons.holiday_village_rounded
                            : Icons.location_city_rounded,
                        iconColor: isVillage
                            ? const Color(0xFF059669)
                            : AppColors.primary,
                        placeType: isVillage ? 'village' : 'city',
                        onTap: () {
                          HapticService.selection();
                          context.push(
                            '/memories/place?city=$name&type=${isVillage ? 'village' : 'city'}&state=${widget.stateName}&country=${widget.countryName}&code=${widget.countryCode}&lat=${lat ?? ''}&lng=${lng ?? ''}',
                          );
                        },
                      );
                    },
                    childCount: recentMixed.length,
                  ),
                ),
              ),

            // ── All Cities ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: _SectionTitle(
                    title: 'All Cities', count: allCities.length),
              ),
            ),
            if (allCities.isEmpty)
              const SliverToBoxAdapter(
                child: _EmptySection(text: 'No more cities'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final city = allCities[index];
                      final name =
                          city['name'] as String? ?? 'Unknown';
                      final visitCount =
                          city['visit_count'] as int? ?? 1;
                      final lat =
                          (city['lat'] as num?)?.toDouble();
                      final lng =
                          (city['lng'] as num?)?.toDouble();

                      return _PlaceCard(
                        name: name,
                        visitCount: visitCount,
                        index: index,
                        icon: Icons.location_city_rounded,
                        iconColor: AppColors.primary,
                        placeType: 'city',
                        onTap: () {
                          HapticService.selection();
                          context.push(
                            '/memories/place?city=$name&type=city&state=${widget.stateName}&country=${widget.countryName}&code=${widget.countryCode}&lat=${lat ?? ''}&lng=${lng ?? ''}',
                          );
                        },
                      );
                    },
                    childCount: allCities.length,
                  ),
                ),
              ),

            // ── All Villages ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
                child: _SectionTitle(
                    title: 'All Villages', count: allVillages.length),
              ),
            ),
            if (allVillages.isEmpty)
              const SliverToBoxAdapter(
                child: _EmptySection(text: 'No more villages'),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.55,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final village = allVillages[index];
                      final name =
                          village['name'] as String? ?? 'Unknown';
                      final visitCount =
                          village['visit_count'] as int? ?? 1;
                      final lat =
                          (village['lat'] as num?)?.toDouble();
                      final lng =
                          (village['lng'] as num?)?.toDouble();

                      return _PlaceCard(
                        name: name,
                        visitCount: visitCount,
                        index: index,
                        icon: Icons.holiday_village_rounded,
                        iconColor: const Color(0xFF059669),
                        placeType: 'village',
                        onTap: () {
                          HapticService.selection();
                          context.push(
                            '/memories/place?city=$name&type=village&state=${widget.stateName}&country=${widget.countryName}&code=${widget.countryCode}&lat=${lat ?? ''}&lng=${lng ?? ''}',
                          );
                        },
                      );
                    },
                    childCount: allVillages.length,
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }
}

// ─── Place Card ───────────────────────────────────────────────────────────────

class _PlaceCard extends ConsumerWidget {
  final String name;
  final int visitCount;
  final int index;
  final IconData icon;
  final Color iconColor;
  final String placeType;
  final VoidCallback onTap;

  const _PlaceCard({
    required this.name,
    required this.visitCount,
    required this.index,
    required this.icon,
    required this.iconColor,
    required this.placeType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(latestMemoryProvider(
      MemoryQuery(placeType: placeType, placeName: name),
    ));
    final hasImage = memoryAsync.asData?.value != null;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.85 + 0.15 * value,
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.lightSurface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: AppColors.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                // Memory image overlay
                memoryAsync.when(
                  data: (memory) {
                    if (memory == null) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: memory.imageUrl,
                        fit: BoxFit.cover,
                        color: Colors.black.withValues(alpha: 0.5),
                        colorBlendMode: BlendMode.darken,
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: hasImage
                              ? Colors.black.withValues(alpha: 0.3)
                              : iconColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon,
                            color: hasImage ? Colors.white70 : iconColor,
                            size: 15),
                      ),
                      const Spacer(),
                      Text(
                        name,
                        style: GoogleFonts.manrope(
                          color: hasImage
                              ? Colors.white
                              : AppColors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Row(
                        children: [
                          Icon(
                            Icons.visibility_rounded,
                            color: hasImage
                                ? Colors.white54
                                : AppColors.textMuted,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$visitCount visit${visitCount == 1 ? '' : 's'}',
                            style: GoogleFonts.inter(
                              color: hasImage
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ],
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

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final int count;

  const _SectionTitle({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.inter(
              color: AppColors.primaryDark,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  final String text;

  const _EmptySection({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
