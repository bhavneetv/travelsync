import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/memory_service.dart';
import '../../../services/haptic_service.dart';

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
              widget.countryName,
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

          // ── Search bar ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: GoogleFonts.inter(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search state or region...',
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

          statesAsync.when(
            data: (states) {
              final query = _searchQuery.trim().toLowerCase();
              final filtered = states.where((state) {
                if (query.isEmpty) return true;
                final name = (state['name'] as String? ?? '').toLowerCase();
                return name.contains(query);
              }).toList();

              final recent =
                  filtered.where((s) => _isRecent(s)).toList();
              final all = List<Map<String, dynamic>>.from(filtered);

              if (states.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(
                    icon: Icons.map_outlined,
                    title: 'No states visited',
                    subtitle:
                        'No states recorded in ${widget.countryName} yet',
                  ),
                );
              }

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No results',
                    subtitle: 'No states match your search',
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
                          text: 'No recent states in last 24h'),
                    )
                  else
                    SliverPadding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
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
                            final name =
                                state['name'] as String? ?? 'Unknown';
                            final visitCount =
                                state['visit_count'] as int? ?? 1;
                            return _StateCard(
                              name: name,
                              countryCode: widget.countryCode,
                              countryName: widget.countryName,
                              visitCount: visitCount,
                              onTap: () {
                                HapticService.selection();
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
                      child: _SectionTitle(
                          title: 'All States', count: all.length),
                    ),
                  ),
                  if (all.isEmpty)
                    const SliverToBoxAdapter(
                      child: _EmptySection(text: 'No more states'),
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
                          childAspectRatio: 2.35,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final state = all[index];
                            final name =
                                state['name'] as String? ?? 'Unknown';
                            final visitCount =
                                state['visit_count'] as int? ?? 1;
                            return _StateCard(
                              name: name,
                              countryCode: widget.countryCode,
                              countryName: widget.countryName,
                              visitCount: visitCount,
                              onTap: () {
                                HapticService.selection();
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
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                  strokeWidth: 2.5,
                ),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text(
                  'Error: $e',
                  style: GoogleFonts.inter(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── State Card ───────────────────────────────────────────────────────────────

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
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
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
                      child: Icon(
                        Icons.location_on_rounded,
                        color: hasImage
                            ? Colors.white70
                            : AppColors.primary,
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
                            style: GoogleFonts.manrope(
                              color: hasImage
                                  ? Colors.white
                                  : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
                    Icon(
                      Icons.chevron_right_rounded,
                      color: hasImage
                          ? Colors.white54
                          : AppColors.textMuted,
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
