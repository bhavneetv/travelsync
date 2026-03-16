import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/xp_service.dart';
import '../../../data/models/visited_place.dart';

// ─── Palette (matches StatsScreen, no purple) ────────────────────────────────
// Primary accent : #FFD166  (gold/amber)
// Secondary accent: #3EF4A8  (mint green)
// Blue accent    : #3E8EF4
// Background     : #0A0A0F
// Card           : #131318
// Border         : rgba(255,255,255,0.06)

final achievementsProvider =
    FutureProvider.autoDispose<List<Achievement>>((ref) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];
  final data = await AppConstants.supabase
      .from('achievements')
      .select()
      .eq('user_id', userId)
      .order('earned_at', ascending: false);
  return (data as List).map((a) => Achievement.fromJson(a)).toList();
});

// ─── Badge catalogue (order matches icon row) ────────────────────────────────
const _catalogKeys = [
  'early_bird',
  'night_owl',
  'continent_collector',
  'speed_demon',
  'team_player',
  'storyteller',
  'streak_master',
];

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final achievementsAsync = ref.watch(achievementsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: userAsync.when(
          data: (user) {
            if (user == null) {
              return const Center(
                child: Text('Not logged in',
                    style: TextStyle(color: Colors.white54)),
              );
            }

            final level = user.travelLevel;
            final progress = XPService.levelProgress(user.totalXp);
            final displayName = user.fullName ?? user.username;

            return CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // ── App Bar ──────────────────────────────────────────────
                SliverAppBar(
                  expandedHeight: 0,
                  floating: true,
                  backgroundColor: const Color(0xFF0A0A0F),
                  elevation: 0,
                  title: const Text(
                    'Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  actions: [
                    // Edit button
                    IconButton(
                      icon: const Icon(Icons.edit_rounded,
                          color: Colors.white70, size: 20),
                      onPressed: () => context.push('/profile/edit'),
                      tooltip: 'Edit profile',
                    ),
                    // Settings button
                    IconButton(
                      icon: const Icon(Icons.settings_rounded,
                          color: Colors.white70, size: 20),
                      onPressed: () => context.push('/profile/settings'),
                      tooltip: 'Settings',
                    ),
                    const SizedBox(width: 4),
                  ],
                ),

                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Hero card ──────────────────────────────────────
                      _HeroCard(
                        displayName: displayName,
                        username: user.username,
                        bio: user.bio,
                        avatarUrl: user.avatarUrl,
                        level: level,
                        totalXp: user.totalXp,
                        progress: progress,
                      ),
                      const SizedBox(height: 16),

                      // ── Quick stats ────────────────────────────────────
                      _QuickStats(
                        countries: user.countriesVisited,
                        cities: user.citiesVisited,
                        villages: user.villagesVisited,
                        km: user.totalDistanceKm,
                        onTap: () => context.push('/memories'),
                      ),
                      const SizedBox(height: 28),

                      // ── Earned badges ──────────────────────────────────
                      const _SectionLabel('Earned Badges'),
                      const SizedBox(height: 12),
                      achievementsAsync.when(
                        data: (list) => list.isEmpty
                            ? _EmptyBadges()
                            : _EarnedBadgeGrid(achievements: list),
                        loading: () => const _InlineLoader(),
                        error: (_, __) => const _InlineError(),
                      ),
                      const SizedBox(height: 28),

                      // ── All badges ─────────────────────────────────────
                      const _SectionLabel('All Badges'),
                      const SizedBox(height: 12),
                      ..._catalogKeys.map((key) {
                        final info = XPService.getBadgeInfo(key);
                        final earned =
                            achievementsAsync.value?.any((a) => a.badgeKey == key) ??
                                false;
                        return _BadgeCatalogTile(
                            badgeKey: key, info: info, earned: earned);
                      }),

                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(Color(0xFFFFD166)),
              strokeWidth: 2.5,
            ),
          ),
          error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white54)),
          ),
        ),
      ),
    );
  }
}

// ─── Hero Card ────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String displayName, username;
  final String? bio, avatarUrl;
  final int level, totalXp;
  final double progress;

  const _HeroCard({
    required this.displayName,
    required this.username,
    required this.bio,
    required this.avatarUrl,
    required this.level,
    required this.totalXp,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF131318),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Avatar row
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Stack(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFD166), Color(0xFFFF9F43)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD166).withOpacity(0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: avatarUrl != null
                        ? ClipOval(
                            child: Image.network(
                              avatarUrl!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Center(
                            child: Text(
                              displayName[0].toUpperCase(),
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0A0A0F),
                              ),
                            ),
                          ),
                  ),
                  // Level badge
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD166),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFFD166).withOpacity(0.25),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Text(
                        'L$level',
                        style: const TextStyle(
                          color: Color(0xFF0A0A0F),
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 18),

              // Name + username + level name
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@$username',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD166).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFFD166).withOpacity(0.25),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        XPService.getLevelName(level),
                        style: const TextStyle(
                          color: Color(0xFFFFD166),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Bio
          if (bio != null && bio!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                bio!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // XP bar
          Row(
            children: [
              Text(
                '$totalXp XP',
                style: const TextStyle(
                  color: Color(0xFFFFD166),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% to next level',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFFFD166)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick Stats ──────────────────────────────────────────────────────────────

class _QuickStats extends StatelessWidget {
  final int countries, cities, villages;
  final double km;
  final VoidCallback onTap;

  const _QuickStats({
    required this.countries,
    required this.cities,
    required this.villages,
    required this.km,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatPill(
          icon: Icons.public_rounded,
          value: '$countries',
          label: 'Countries',
          color: const Color(0xFF3E8EF4),
          onTap: onTap,
        ),
        const SizedBox(width: 8),
        _StatPill(
          icon: Icons.location_city_rounded,
          value: '$cities',
          label: 'Cities',
          color: const Color(0xFF3EF4A8),
          onTap: onTap,
        ),
        const SizedBox(width: 8),
        _StatPill(
          icon: Icons.holiday_village_rounded,
          value: '$villages',
          label: 'Villages',
          color: const Color(0xFFFF9F43),
          onTap: onTap,
        ),
        const SizedBox(width: 8),
        _StatPill(
          icon: Icons.straighten_rounded,
          value: km.toStringAsFixed(0),
          label: 'KM',
          color: const Color(0xFFFFD166),
        ),
      ],
    );
  }
}

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;
  final VoidCallback? onTap;

  const _StatPill({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF131318),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Earned Badge Grid ────────────────────────────────────────────────────────

class _EarnedBadgeGrid extends StatelessWidget {
  final List<Achievement> achievements;
  const _EarnedBadgeGrid({required this.achievements});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: achievements.map((a) {
        final info = XPService.getBadgeInfo(a.badgeKey);
        return Container(
          width: (MediaQuery.of(context).size.width - 42) / 2,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131318),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFD166).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Text(
                info['icon'] as String,
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info['name'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '+${info['xp']} XP',
                      style: const TextStyle(
                        color: Color(0xFFFFD166),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─── Empty badges ─────────────────────────────────────────────────────────────

class _EmptyBadges extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: const Color(0xFF131318),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_rounded,
            size: 40,
            color: Colors.white.withOpacity(0.15),
          ),
          const SizedBox(height: 10),
          Text(
            'No badges yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Keep exploring to earn your first badge!',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Badge Catalog Tile ───────────────────────────────────────────────────────

class _BadgeCatalogTile extends StatelessWidget {
  final String badgeKey;
  final Map<String, dynamic> info;
  final bool earned;

  const _BadgeCatalogTile({
    required this.badgeKey,
    required this.info,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131318),
        borderRadius: BorderRadius.circular(18),
        border: earned
            ? Border.all(
                color: const Color(0xFFFFD166).withOpacity(0.25), width: 1)
            : Border.all(
                color: Colors.white.withOpacity(0.05), width: 1),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: earned ? 1.0 : 0.3,
            child: Text(
              info['icon'] as String,
              style: const TextStyle(fontSize: 26),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info['name'] as String,
                  style: TextStyle(
                    color: earned ? Colors.white : Colors.white54,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  info['description'] as String,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          earned
              ? Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3EF4A8).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFF3EF4A8), size: 16),
                )
              : Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white.withOpacity(0.2),
                    size: 14,
                  ),
                ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
  }
}

class _InlineLoader extends StatelessWidget {
  const _InlineLoader();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2));
}

class _InlineError extends StatelessWidget {
  const _InlineError();
  @override
  Widget build(BuildContext context) => Text(
        'Could not load badges',
        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
      );
}