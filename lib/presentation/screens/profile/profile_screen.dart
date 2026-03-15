import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/xp_service.dart';
import '../../../data/models/visited_place.dart';

final achievementsProvider = FutureProvider.autoDispose<List<Achievement>>((ref) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return [];
  final data = await AppConstants.supabase
      .from('achievements')
      .select()
      .eq('user_id', userId)
      .order('earned_at', ascending: false);
  return (data as List).map((a) => Achievement.fromJson(a)).toList();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);
    final achievementsAsync = ref.watch(achievementsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: userAsync.when(
        data: (user) {
          if (user == null) return const Center(child: Text('Not logged in'));

          final level = user.travelLevel;
          final progress = XPService.levelProgress(user.totalXp);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: AppColors.cardGradient,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Avatar
                      Stack(
                        children: [
                          Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.primaryGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                ),
                              ],
                            ),
                            child: user.avatarUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      user.avatarUrl!,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Center(
                                    child: Text(
                                      (user.fullName ?? user.username)[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
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
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gold.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Text(
                                'Lv.$level',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        user.fullName ?? user.username,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '@${user.username}',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      if (user.bio != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          user.bio!,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 20),

                      // XP bar
                      Row(
                        children: [
                          Text(
                            '${user.totalXp} XP',
                            style: TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            XPService.getLevelName(level),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Quick stats row — tappable with drill-down
                Row(
                  children: [
                    _ProfileStat(
                      value: '${user.countriesVisited}',
                      label: 'Countries',
                      icon: Icons.public_rounded,
                      onTap: () => context.push('/memories'),
                    ),
                    const SizedBox(width: 8),
                    _ProfileStat(
                      value: '${user.citiesVisited}',
                      label: 'Cities',
                      icon: Icons.location_city_rounded,
                      onTap: () => context.push('/memories'),
                    ),
                    const SizedBox(width: 8),
                    _ProfileStat(
                      value: '${user.villagesVisited}',
                      label: 'Villages',
                      icon: Icons.holiday_village_rounded,
                      onTap: () => context.push('/memories'),
                    ),
                    const SizedBox(width: 8),
                    _ProfileStat(
                      value: user.totalDistanceKm.toStringAsFixed(0),
                      label: 'KM',
                      icon: Icons.straighten_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Badges section
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Badges',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(height: 12),

                achievementsAsync.when(
                  data: (achievements) {
                    if (achievements.isEmpty) {
                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.darkCard,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.emoji_events_rounded,
                              size: 48,
                              color: AppColors.textSecondary.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No badges yet',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                            Text(
                              'Keep traveling to earn badges!',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: achievements.map((a) {
                        final info = XPService.getBadgeInfo(a.badgeKey);
                        return Container(
                          width: (MediaQuery.of(context).size.width - 44) / 2,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.darkCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                info['icon'] as String,
                                style: const TextStyle(fontSize: 32),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                info['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                '+${info['xp']} XP',
                                style: TextStyle(
                                  color: AppColors.gold,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (_, __) => const Text('Error loading badges'),
                ),

                // All badges catalog
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'All Badges',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(height: 12),

                ...['early_bird', 'night_owl', 'continent_collector', 'speed_demon', 'team_player', 'storyteller', 'streak_master'].map((key) {
                  final info = XPService.getBadgeInfo(key);
                  final earned = achievementsAsync.value?.any((a) => a.badgeKey == key) ?? false;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.darkCard,
                      borderRadius: BorderRadius.circular(16),
                      border: earned
                          ? Border.all(color: AppColors.gold.withValues(alpha: 0.3))
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(
                          info['icon'] as String,
                          style: TextStyle(
                            fontSize: 28,
                            color: earned ? null : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                info['name'] as String,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: earned ? null : AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                info['description'] as String,
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (earned)
                          Icon(Icons.check_circle_rounded, color: AppColors.success)
                        else
                          Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const _ProfileStat({
    required this.value,
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
