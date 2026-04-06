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
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: AppColors.darkBg,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'My Travels',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF246BFD), Color(0xFF123D8D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -24,
                      top: -12,
                      child: Icon(
                        Icons.flight_rounded,
                        size: 150,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search country',
                  hintStyle: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.8),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close_rounded,
                              color: AppColors.textSecondary),
                        ),
                  filled: true,
                  fillColor: AppColors.darkCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
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
                final name = (country['name'] as String? ?? '').toLowerCase();
                final code =
                    (country['country_code'] as String? ?? '').toLowerCase();
                return name.contains(query) || code.contains(query);
              }).toList();

              final recent =
                  filtered.where((country) => _isRecent(country)).toList();
                final all = List<Map<String, dynamic>>.from(filtered);

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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start tracking your journeys!',
                          style: TextStyle(
                            color: AppColors.textSecondary.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No countries match your search',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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
                      child: _EmptySection(text: 'No recent countries in last 24h'),
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
                            final name = country['name'] as String? ?? 'Unknown';
                            final code = country['country_code'] as String?;
                            final visitCount = country['visit_count'] as int? ?? 1;
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
                      child: _SectionTitle(title: 'All Countries', count: all.length),
                    ),
                  ),
                  if (all.isEmpty)
                    const SliverToBoxAdapter(
                      child: _EmptySection(text: 'No more countries'),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
                            final name = country['name'] as String? ?? 'Unknown';
                            final code = country['country_code'] as String?;
                            final visitCount = country['visit_count'] as int? ?? 1;
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
    final hasMemoryImage = memoryAsync.asData?.value != null;
    final titleColor = hasMemoryImage ? Colors.white : AppColors.textDark;
    final subtitleColor =
        hasMemoryImage ? AppColors.textSecondary : AppColors.textDarkSecondary;
    final flagBgColor = hasMemoryImage
        ? AppColors.darkBg.withValues(alpha: 0.6)
        : AppColors.lightCard;
    final arrowBgColor = hasMemoryImage
        ? AppColors.primary.withValues(alpha: 0.2)
        : AppColors.primary.withValues(alpha: 0.12);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: AppColors.cardGradient,
          borderRadius: BorderRadius.circular(14),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              memoryAsync.when(
                data: (memory) {
                  if (memory == null) return const SizedBox.shrink();
                  return Positioned.fill(
                    child: CachedNetworkImage(
                      imageUrl: memory.imageUrl,
                      fit: BoxFit.cover,
                      color: Colors.black.withValues(alpha: 0.58),
                      colorBlendMode: BlendMode.darken,
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: flagBgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(flag, style: const TextStyle(fontSize: 18)),
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
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '$visitCount visit${visitCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: arrowBgColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: AppColors.primary,
                        size: 12,
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
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: AppColors.textSecondary,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
