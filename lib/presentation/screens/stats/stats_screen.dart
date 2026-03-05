import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/xp_service.dart';

// Stats data providers
final travelStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return {};

  // Keep payloads small so tab switches stay responsive on low-memory devices.
  final results = await Future.wait([
    AppConstants.supabase
        .from('users')
        .select('total_distance_km, total_xp, travel_level')
        .eq('id', userId)
        .single(),
    AppConstants.supabase
        .from('travel_logs')
        .select('recorded_at')
        .eq('user_id', userId)
        .order('recorded_at', ascending: false)
        .limit(180),
    AppConstants.supabase
        .from('routes')
        .select('id')
        .eq('user_id', userId)
        .limit(1000),
    AppConstants.supabase
        .from('visited_cities')
        .select('id')
        .eq('user_id', userId)
        .limit(2000),
    AppConstants.supabase
        .from('visited_countries')
        .select('name, country_code, visit_count')
        .eq('user_id', userId)
        .limit(100),
  ]);

  final user = results[0] as Map<String, dynamic>;
  final logs = results[1] as List;
  final routes = results[2] as List;
  final cities = results[3] as List;
  final countries = results[4] as List;

  // Monthly distance calculation
  final monthlyData = <int, double>{};
  for (final log in logs) {
    final date = DateTime.parse(log['recorded_at'] as String);
    final month = date.month;
    monthlyData[month] = (monthlyData[month] ?? 0) + 1; // Log count per month
  }

  final totalDistance = (user['total_distance_km'] as num?)?.toDouble() ?? 0;

  return {
    'user': user,
    'totalDistance': totalDistance,
    'totalXp': user['total_xp'] ?? 0,
    'travelLevel': user['travel_level'] ?? 1,
    'citiesVisited': cities.length,
    'countriesVisited': countries.length,
    'totalLogs': logs.length,
    'totalRoutes': routes.length,
    'totalDuration': 0,
    'monthlyData': monthlyData,
    'cities': cities,
    'countries': countries,
  };
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(travelStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Stats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(travelStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        data: (stats) => _buildStats(context, stats),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  Widget _buildStats(BuildContext context, Map<String, dynamic> stats) {
    final totalXp = stats['totalXp'] as int? ?? 0;
    final level = stats['travelLevel'] as int? ?? 1;
    final progress = XPService.levelProgress(totalXp);
    final nextLevelXp = XPService.xpForNextLevel(totalXp);
    final monthlyData = stats['monthlyData'] as Map<int, double>? ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // XP & Level card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 25,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Level $level',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          XPService.getLevelName(level),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          _getLevelEmoji(level),
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // XP progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$totalXp XP',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$nextLevelXp XP to next',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Quick stats grid
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.straighten_rounded,
                  label: 'Distance',
                  value: '${(stats['totalDistance'] as num? ?? 0).toStringAsFixed(1)} km',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.location_city_rounded,
                  label: 'Cities',
                  value: '${stats['citiesVisited'] ?? 0}',
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.public_rounded,
                  label: 'Countries',
                  value: '${stats['countriesVisited'] ?? 0}',
                  color: AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.route_rounded,
                  label: 'Routes',
                  value: '${stats['totalRoutes'] ?? 0}',
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Monthly chart
          Text(
            'Monthly Activity',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 16),
          Container(
            height: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.darkCard,
              borderRadius: BorderRadius.circular(20),
            ),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (monthlyData.values.fold(0.0, (a, b) => a > b ? a : b)) + 5,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const months = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
                        final idx = value.toInt();
                        if (idx >= 0 && idx < 12) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              months[idx],
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(12, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: monthlyData[i + 1] ?? 0,
                        gradient: AppColors.xpGradient,
                        width: 16,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Visited countries list
          if ((stats['countries'] as List?)?.isNotEmpty ?? false) ...[
            Text(
              'Countries Visited',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            ...((stats['countries'] as List).map((c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.darkCard,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _countryCodeToEmoji(c['country_code'] ?? ''),
                        style: const TextStyle(fontSize: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c['name'] as String? ?? 'Unknown',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              'Visit count: ${c['visit_count'] ?? 1}',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle_rounded, color: AppColors.success),
                    ],
                  ),
                ))),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _getLevelEmoji(int level) {
    const emojis = {1: '🚶', 2: '🧭', 3: '⛰️', 4: '🏎️', 5: '🌍', 6: '👑'};
    return emojis[level] ?? '🚶';
  }

  String _countryCodeToEmoji(String code) {
    if (code.length != 2) return '🏳️';
    final int firstLetter = code.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int secondLetter = code.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([firstLetter, secondLetter]);
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
