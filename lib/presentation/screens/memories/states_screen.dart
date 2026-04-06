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

class StatesScreen extends ConsumerStatefulWidget {
  final String countryName;
  final String countryCode;

  const StatesScreen({
    super.key,
    required this.countryName,
    required this.countryCode,
  });

  @override
  ConsumerState<StatesScreen> createState() => _StatesScreenState();
}

class _StatesScreenState extends ConsumerState<StatesScreen> {
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statesAsync = ref.watch(visitedStatesProvider(widget.countryCode));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
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
                widget.countryName,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 18),
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1F72E6), Color(0xFF0E458F)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      bottom: -8,
                      child: Icon(
                        Icons.map_rounded,
                        size: 120,
                        color: Colors.white.withValues(alpha: 0.07),
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
                  hintText: 'Search state or region',
                  hintStyle:
                      TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.8)),
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

          statesAsync.when(
            data: (states) {
              final query = _searchQuery.trim().toLowerCase();
              final filtered = states.where((state) {
                if (query.isEmpty) return true;
                final name = (state['name'] as String? ?? '').toLowerCase();
                return name.contains(query);
              }).toList();

              final recent = filtered.where((state) => _isRecent(state)).toList();
              final all = List<Map<String, dynamic>>.from(filtered);

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
                          'No states visited in ${widget.countryName}',
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

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'No states match your search',
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
                      child: _EmptySection(text: 'No recent states in last 24h'),
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
                          childAspectRatio: 2.35,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final state = recent[index];
                            final name = state['name'] as String? ?? 'Unknown';
                            final visitCount = state['visit_count'] as int? ?? 1;
                            return _StateCard(
                              name: name,
                              countryCode: widget.countryCode,
                              countryName: widget.countryName,
                              visitCount: visitCount,
                              onTap: () {
                                context.push(
                                  '/memories/cities?state=$name&country=${widget.countryName}&code=${widget.countryCode}',
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
                      child: _SectionTitle(title: 'All States', count: all.length),
                    ),
                  ),
                  if (all.isEmpty)
                    const SliverToBoxAdapter(
                      child: _EmptySection(text: 'No more states'),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.35,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final state = all[index];
                            final name = state['name'] as String? ?? 'Unknown';
                            final visitCount = state['visit_count'] as int? ?? 1;
                            return _StateCard(
                              name: name,
                              countryCode: widget.countryCode,
                              countryName: widget.countryName,
                              visitCount: visitCount,
                              onTap: () {
                                context.push(
                                  '/memories/cities?state=$name&country=${widget.countryName}&code=${widget.countryCode}',
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
  final VoidCallback onTap;

  const _StateCard({
    required this.name,
    required this.countryCode,
    required this.countryName,
    required this.visitCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memoryAsync = ref.watch(latestMemoryProvider(
      MemoryQuery(placeType: 'state', placeName: name),
    ));
    final hasMemoryImage = memoryAsync.asData?.value != null;
    final titleColor = hasMemoryImage ? Colors.white : AppColors.textDark;
    final subtitleColor =
        hasMemoryImage ? AppColors.textSecondary : AppColors.textDarkSecondary;
    final chevronColor =
        hasMemoryImage ? AppColors.textSecondary : AppColors.textDarkSecondary;

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
                      color: Colors.black.withValues(alpha: 0.6),
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
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: AppColors.primaryLight,
                        size: 18,
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
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    Icon(
                      Icons.chevron_right_rounded,
                      color: chevronColor,
                      size: 18,
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
