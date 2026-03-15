import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/memory_service.dart';

/// Provider to fetch visited countries for the current user
final visitedCountriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];

  final data = await AppConstants.supabase
      .from('visited_countries')
      .select()
      .eq('user_id', userId)
      .order('first_visited_at', ascending: false);

  return List<Map<String, dynamic>>.from(data);
});

class CountriesScreen extends ConsumerWidget {
  const CountriesScreen({super.key});

  String _countryFlag(String? countryCode) {
    if (countryCode == null || countryCode.trim().length < 2) return '🌍';
    final code = countryCode.trim().toUpperCase();
    final flag = code.runes.map((r) => String.fromCharCode(r + 127397)).join();
    return flag;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countriesAsync = ref.watch(visitedCountriesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Beautiful header
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppColors.darkBg,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'My Travels',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3B2FA5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      top: -20,
                      child: Icon(
                        Icons.flight_rounded,
                        size: 200,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    Positioned(
                      left: -20,
                      bottom: -10,
                      child: Icon(
                        Icons.public_rounded,
                        size: 120,
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Content
          countriesAsync.when(
            data: (countries) {
              if (countries.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.explore_off_rounded,
                          size: 80,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No countries visited yet',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start tracking your journeys!',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final country = countries[index];
                      final name = country['name'] as String? ?? 'Unknown';
                      final code = country['country_code'] as String?;
                      final visitCount = country['visit_count'] as int? ?? 1;

                      return _CountryCard(
                        name: name,
                        countryCode: code,
                        flag: _countryFlag(code),
                        visitCount: visitCount,
                        index: index,
                        onTap: () {
                          context.push(
                            '/memories/states?country=$name&code=${code ?? ''}',
                          );
                        },
                      );
                    },
                    childCount: countries.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.accent)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryCard extends ConsumerWidget {
  final String name;
  final String? countryCode;
  final String flag;
  final int visitCount;
  final int index;
  final VoidCallback onTap;

  const _CountryCard({
    required this.name,
    required this.countryCode,
    required this.flag,
    required this.visitCount,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(latestMemoryProvider(
      MemoryQuery(placeType: 'country', placeName: name),
    ));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + index * 100),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Background memory image if available
                memoryAsync.when(
                  data: (memory) {
                    if (memory == null) return const SizedBox.shrink();
                    return Positioned.fill(
                      child: CachedNetworkImage(
                        imageUrl: memory.imageUrl,
                        fit: BoxFit.cover,
                        color: Colors.black.withValues(alpha: 0.55),
                        colorBlendMode: BlendMode.darken,
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      // Flag
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.darkBg.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            flag,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Name and stats
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$visitCount visit${visitCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Arrow
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
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
