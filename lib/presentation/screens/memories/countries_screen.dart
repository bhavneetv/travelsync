import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
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

class CountriesScreen extends ConsumerStatefulWidget {
  const CountriesScreen({super.key});

  @override
  ConsumerState<CountriesScreen> createState() => _CountriesScreenState();
}

class _CountriesScreenState extends ConsumerState<CountriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _countryFlag(String? countryCode) {
    if (countryCode == null || countryCode.trim().length < 2) return '🌍';
    final code = countryCode.trim().toUpperCase();
    final flag = code.runes.map((r) => String.fromCharCode(r + 127397)).join();
    return flag;
  }

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final countriesAsync = ref.watch(visitedCountriesProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar (flat light) ───────────────────────────────────────
          SliverAppBar(
            floating: true,
            backgroundColor: AppColors.lightSurface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(
              'My Travels',
              style: GoogleFonts.manrope(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              color: AppColors.textSecondary,
              onPressed: () => context.pop(),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: AppColors.border, height: 1),
            ),
          ),

          // ── Search bar ────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: GoogleFonts.inter(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search country...',
                  prefixIcon:
                      const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
              ),
            ),
          ),

          countriesAsync.when(
            data: (countries) {
              final query = _searchQuery.trim().toLowerCase();
              final filtered = countries.where((country) {
                if (query.isEmpty) return true;
                final name =
                    (country['name'] as String? ?? '').toLowerCase();
                final code = (country['country_code'] as String? ?? '')
                    .toLowerCase();
                return name.contains(query) || code.contains(query);
              }).toList();

              final recent =
                  filtered.where((c) => _isRecent(c)).toList();
              final all = List<Map<String, dynamic>>.from(filtered);

              if (countries.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(
                    icon: Icons.explore_off_rounded,
                    title: 'No countries visited yet',
                    subtitle: 'Start tracking your journeys!',
                  ),
                );
              }

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No results',
                    subtitle: 'No countries match your search',
                  ),
                );
              }

              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: _SectionTitle(
                        title: 'Recent (24h)',
                        count: recent.length,
                      ),
                    ),
                  ),
                  if (recent.isEmpty)
                    const SliverToBoxAdapter(
                      child: _EmptySection(
                          text: 'No recent countries in last 24h'),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.45,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final country = recent[index];
                            final name =
                                country['name'] as String? ?? 'Unknown';
                            final code =
                                country['country_code'] as String?;
                            final visitCount =
                                country['visit_count'] as int? ?? 1;
                            return _CountryMiniCard(
                              name: name,
                              countryCode: code,
                              flag: _countryFlag(code),
                              visitCount: visitCount,
                              onTap: () {
                                context.push(
                                  '/memories/states?country=$name&code=${code ?? ''}',
                                );
                              },
                            );
                          },
                          childCount: recent.length,
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: _SectionTitle(
                          title: 'All Countries', count: all.length),
                    ),
                  ),
                  if (all.isEmpty)
                    const SliverToBoxAdapter(
                      child: _EmptySection(text: 'No more countries'),
                    )
                  else
                    SliverPadding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 0, 16, 32),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.45,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final country = all[index];
                            final name =
                                country['name'] as String? ?? 'Unknown';
                            final code =
                                country['country_code'] as String?;
                            final visitCount =
                                country['visit_count'] as int? ?? 1;
                            return _CountryMiniCard(
                              name: name,
                              countryCode: code,
                              flag: _countryFlag(code),
                              visitCount: visitCount,
                              onTap: () {
                                context.push(
                                  '/memories/states?country=$name&code=${code ?? ''}',
                                );
                              },
                            );
                          },
                          childCount: all.length,
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 2.5,
                ),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: _EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Something went wrong',
                subtitle: e.toString(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Country Mini Card ────────────────────────────────────────────────────────

class _CountryMiniCard extends ConsumerWidget {
  final String name;
  final String? countryCode;
  final String flag;
  final int visitCount;
  final VoidCallback onTap;

  const _CountryMiniCard({
    required this.name,
    required this.countryCode,
    required this.flag,
    required this.visitCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(latestMemoryProvider(
      MemoryQuery(placeType: 'country', placeName: name),
    ));
    final hasImage = memoryAsync.asData?.value != null;

    return GestureDetector(
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
                      color: Colors.black.withValues(alpha: 0.52),
                      colorBlendMode: BlendMode.darken,
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              // Content
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: hasImage
                            ? Colors.black.withValues(alpha: 0.3)
                            : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child:
                            Text(flag, style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                              color: hasImage
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '$visitCount visit${visitCount == 1 ? '' : 's'}',
                            style: GoogleFonts.inter(
                              color: hasImage
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.primary,
                        size: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.manrope(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
