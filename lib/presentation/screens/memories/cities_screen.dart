import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/memory_service.dart';

/// Provider to fetch visited cities filtered by state
final visitedCitiesForStateProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, CityQuery>((ref, query) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];

  // Try using the state column on visited_cities first
  var cities = await AppConstants.supabase
      .from('visited_cities')
      .select()
      .eq('user_id', userId)
      .eq('state', query.stateName)
      .order('first_visited_at', ascending: false);

  if ((cities as List).isNotEmpty) {
    return List<Map<String, dynamic>>.from(cities);
  }

  // Fallback: cross-reference with travel_logs
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

  // Try using the state column on visited_villages
  var villages = await AppConstants.supabase
      .from('visited_villages')
      .select()
      .eq('user_id', userId)
      .eq('state', query.stateName)
      .order('first_visited_at', ascending: false);

  if ((villages as List).isNotEmpty) {
    return List<Map<String, dynamic>>.from(villages);
  }

  // Fallback: cross-reference with travel_logs for village-class places
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

class CitiesScreen extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final citiesAsync = ref.watch(visitedCitiesForStateProvider(
      CityQuery(stateName: stateName, countryCode: countryCode),
    ));
    final villagesAsync = ref.watch(visitedVillagesForStateProvider(
      CityQuery(stateName: stateName, countryCode: countryCode),
    ));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 150,
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
                stateName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF5B52E0), Color(0xFF3B2FA5)],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: 10,
                      child: Icon(
                        Icons.apartment_rounded,
                        size: 140,
                        color: Colors.white.withValues(alpha: 0.06),
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
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.go('/memories'),
                    child: Text(
                      countryName,
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textSecondary, size: 18),
                  Text(
                    stateName,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Cities section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                '🏙️ Cities & Towns',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          citiesAsync.when(
            data: (cities) {
              if (cities.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.location_city_rounded,
                              color: AppColors.textSecondary.withValues(alpha: 0.4),
                              size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No cities recorded yet',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final city = cities[index];
                      final name = city['name'] as String? ?? 'Unknown';
                      final visitCount = city['visit_count'] as int? ?? 1;
                      final lat = (city['lat'] as num?)?.toDouble();
                      final lng = (city['lng'] as num?)?.toDouble();

                      return _PlaceCard(
                        name: name,
                        visitCount: visitCount,
                        index: index,
                        icon: Icons.location_city_rounded,
                        iconColor: AppColors.accentLight,
                        placeType: 'city',
                        onTap: () {
                          context.push(
                            '/memories/place?city=$name&type=city&state=$stateName&country=$countryName&code=$countryCode&lat=${lat ?? ''}&lng=${lng ?? ''}',
                          );
                        },
                      );
                    },
                    childCount: cities.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('Error: $e')),
            ),
          ),

          // Villages section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Text(
                '🏘️ Villages & Hamlets',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),

          villagesAsync.when(
            data: (villages) {
              if (villages.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.darkCard,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.holiday_village_rounded,
                              color: AppColors.textSecondary.withValues(alpha: 0.4),
                              size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'No villages recorded yet',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final village = villages[index];
                      final name = village['name'] as String? ?? 'Unknown';
                      final visitCount = village['visit_count'] as int? ?? 1;
                      final lat = (village['lat'] as num?)?.toDouble();
                      final lng = (village['lng'] as num?)?.toDouble();

                      return _PlaceCard(
                        name: name,
                        visitCount: visitCount,
                        index: index,
                        icon: Icons.holiday_village_rounded,
                        iconColor: AppColors.success,
                        placeType: 'village',
                        onTap: () {
                          context.push(
                            '/memories/place?city=$name&type=village&state=$stateName&country=$countryName&code=$countryCode&lat=${lat ?? ''}&lng=${lng ?? ''}',
                          );
                        },
                      );
                    },
                    childCount: villages.length,
                  ),
                ),
              );
            },
            loading: () => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Center(child: Text('Error: $e')),
            ),
          ),

          // Bottom spacing
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

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

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 80),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.8 + 0.2 * value,
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Background memory image
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: iconColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: iconColor, size: 22),
                      ),
                      const Spacer(),
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.visibility_rounded,
                              color: AppColors.textSecondary, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '$visitCount visit${visitCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
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
