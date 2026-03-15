import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/memory_service.dart';

/// Provider to fetch visited states filtered by country code
final visitedStatesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, countryCode) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];

  var query = AppConstants.supabase
      .from('visited_states')
      .select()
      .eq('user_id', userId);

  if (countryCode.isNotEmpty) {
    query = query.eq('country_code', countryCode);
  }

  final data = await query.order('first_visited_at', ascending: false);
  return List<Map<String, dynamic>>.from(data);
});

class StatesScreen extends ConsumerWidget {
  final String countryName;
  final String countryCode;

  const StatesScreen({
    super.key,
    required this.countryName,
    required this.countryCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statesAsync = ref.watch(visitedStatesProvider(countryCode));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
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
                countryName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 20),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4A42E8), Color(0xFF2D2580)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -10,
                      child: Icon(
                        Icons.map_rounded,
                        size: 160,
                        color: Colors.white.withValues(alpha: 0.07),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Subtitle
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'States & Regions',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),

          statesAsync.when(
            data: (states) {
              if (states.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined,
                            size: 72,
                            color:
                                AppColors.textSecondary.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text(
                          'No states visited in $countryName',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final state = states[index];
                      final name = state['name'] as String? ?? 'Unknown';
                      final visitCount = state['visit_count'] as int? ?? 1;

                      return _StateCard(
                        name: name,
                        countryCode: countryCode,
                        countryName: countryName,
                        visitCount: visitCount,
                        index: index,
                        onTap: () {
                          context.push(
                            '/memories/cities?state=$name&country=$countryName&code=$countryCode',
                          );
                        },
                      );
                    },
                    childCount: states.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _StateCard extends ConsumerWidget {
  final String name;
  final String countryCode;
  final String countryName;
  final int visitCount;
  final int index;
  final VoidCallback onTap;

  const _StateCard({
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.visitCount,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(latestMemoryProvider(
      MemoryQuery(placeType: 'state', placeName: name),
    ));

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 350 + index * 80),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 24 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 90,
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
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
                        color: Colors.black.withValues(alpha: 0.6),
                        colorBlendMode: BlendMode.darken,
                      ),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: AppColors.primaryLight,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$visitCount visit${visitCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                        size: 24,
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
