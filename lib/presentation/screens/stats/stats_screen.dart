import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/xp_service.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final travelStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final userId = AppConstants.supabase.auth.currentUser?.id;
  if (userId == null) return {};

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
        .limit(365),
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
    AppConstants.supabase
        .from('visited_villages')
        .select('id')
        .eq('user_id', userId)
        .limit(3000),
  ]);

  final user = results[0] as Map<String, dynamic>;
  final logs = results[1] as List;
  final routes = results[2] as List;
  final cities = results[3] as List;
  final countries = results[4] as List;
  final villages = results[5] as List;

  // Monthly activity (count of logs per month)
  final monthlyData = <int, double>{};
  // Daily activity for last 30 days
  final dailyData = <String, double>{};

  for (final log in logs) {
    final date = DateTime.parse(log['recorded_at'] as String);
    final month = date.month;
    monthlyData[month] = (monthlyData[month] ?? 0) + 1;

    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff < 30) {
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      dailyData[key] = (dailyData[key] ?? 0) + 1;
    }
  }

  final totalDistance =
      (user['total_distance_km'] as num?)?.toDouble() ?? 0;

  return {
    'user': user,
    'totalDistance': totalDistance,
    'totalXp': user['total_xp'] ?? 0,
    'travelLevel': user['travel_level'] ?? 1,
    'citiesVisited': cities.length,
    'villagesVisited': villages.length,
    'countriesVisited': countries.length,
    'totalLogs': logs.length,
    'totalRoutes': routes.length,
    'monthlyData': monthlyData,
    'dailyData': dailyData,
    'countries': countries,
  };
});

// ─── Main Screen ─────────────────────────────────────────────────────────────

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _graphTab;

  @override
  void initState() {
    super.initState();
    _graphTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _graphTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(travelStatsProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: statsAsync.when(
          data: (stats) => _buildBody(context, stats),
          loading: () => const _LoadingView(),
          error: (e, _) => _ErrorView(error: e.toString()),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, dynamic> stats) {
    final totalXp = stats['totalXp'] as int? ?? 0;
    final level = stats['travelLevel'] as int? ?? 1;
    final progress = XPService.levelProgress(totalXp);
    final nextLevelXp = XPService.xpForNextLevel(totalXp);
    final monthlyData = stats['monthlyData'] as Map<int, double>? ?? {};
    final dailyData = stats['dailyData'] as Map<String, double>? ?? {};
    final countries = stats['countries'] as List? ?? [];

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── App Bar ──
        SliverAppBar(
          expandedHeight: 0,
          floating: true,
          backgroundColor: const Color(0xFF0A0A0F),
          elevation: 0,
          title: const Text(
            'Your Journey',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () => ref.invalidate(travelStatsProvider),
            ),
          ],
        ),

        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // ── XP Hero Card ──
              _XpHeroCard(
                level: level,
                totalXp: totalXp,
                progress: progress,
                nextLevelXp: nextLevelXp,
              ),
              const SizedBox(height: 20),

              // ── Stats Grid ──
              _StatsGrid(stats: stats),
              const SizedBox(height: 28),

              // ── Activity Graph ──
              _SectionHeader(title: 'Activity'),
              const SizedBox(height: 12),
              _ActivityCard(
                tabController: _graphTab,
                monthlyData: monthlyData,
                dailyData: dailyData,
              ),
              const SizedBox(height: 28),

              // ── Countries ──
              _SectionHeader(title: 'Countries'),
              const SizedBox(height: 12),
              _CountriesSection(
                countries: countries,
                visitedCount: stats['countriesVisited'] as int? ?? 0,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─── XP Hero Card ────────────────────────────────────────────────────────────

class _XpHeroCard extends StatelessWidget {
  final int level, totalXp, nextLevelXp;
  final double progress;

  const _XpHeroCard({
    required this.level,
    required this.totalXp,
    required this.progress,
    required this.nextLevelXp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1040), Color(0xFF0D2060)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C3EF4).withOpacity(0.25),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Level badge
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6C3EF4), Color(0xFF3E8EF4)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Center(
                  child: Text(
                    _getLevelEmoji(level),
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'LEVEL $level',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      XPService.getLevelName(level),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$totalXp',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                  const Text(
                    'total XP',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD166)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _xpChip('${(progress * 100).toStringAsFixed(0)}% complete'),
              _xpChip('$nextLevelXp XP to next level'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _xpChip(String text) => Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );

  String _getLevelEmoji(int level) {
    const emojis = {
      1: '🚶',
      2: '🧭',
      3: '⛰️',
      4: '🏎️',
      5: '🌍',
      6: '👑',
    };
    return emojis[level] ?? '🚶';
  }
}

// ─── Stats Grid ──────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final items = [
      _GridItem(Icons.straighten_rounded, 'Distance',
          '${(stats['totalDistance'] as num? ?? 0).toStringAsFixed(1)} km',
          const Color(0xFF6C3EF4)),
      _GridItem(Icons.location_city_rounded, 'Cities',
          '${stats['citiesVisited'] ?? 0}', const Color(0xFF3E8EF4)),
      _GridItem(Icons.public_rounded, 'Countries',
          '${stats['countriesVisited'] ?? 0}', const Color(0xFF3EF4A8)),
      _GridItem(Icons.route_rounded, 'Routes',
          '${stats['totalRoutes'] ?? 0}', const Color(0xFFFFD166)),
      _GridItem(Icons.holiday_village_rounded, 'Villages',
          '${stats['villagesVisited'] ?? 0}', const Color(0xFFFF6B6B)),
      _GridItem(Icons.pin_drop_rounded, 'Logs',
          '${stats['totalLogs'] ?? 0}', const Color(0xFFFF9F43)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (_, i) => _StatCell(item: items[i]),
    );
  }
}

class _GridItem {
  final IconData icon;
  final String label, value;
  final Color color;
  const _GridItem(this.icon, this.label, this.value, this.color);
}

class _StatCell extends StatelessWidget {
  final _GridItem item;
  const _StatCell({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF131318),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    );
  }
}

// ─── Activity Card (tabbed graph) ─────────────────────────────────────────────

class _ActivityCard extends StatefulWidget {
  final TabController tabController;
  final Map<int, double> monthlyData;
  final Map<String, double> dailyData;

  const _ActivityCard({
    required this.tabController,
    required this.monthlyData,
    required this.dailyData,
  });

  @override
  State<_ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends State<_ActivityCard> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131318),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: widget.tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF6C3EF4),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                onTap: (_) => setState(() {}),
                tabs: const [
                  Tab(text: 'Monthly'),
                  Tab(text: 'Daily (30d)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: TabBarView(
              controller: widget.tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                  child: _MonthlyBarChart(data: widget.monthlyData),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                  child: _DailyLineChart(data: widget.dailyData),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Monthly Bar Chart ────────────────────────────────────────────────────────

class _MonthlyBarChart extends StatelessWidget {
  final Map<int, double> data;
  const _MonthlyBarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxY = data.values.fold(0.0, (a, b) => a > b ? a : b);

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY > 0 ? maxY + 2 : 10,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1E1E2E),
            getTooltipItem: (group, _, rod, __) => BarTooltipItem(
              '${rod.toY.toInt()} logs',
              const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                const months = [
                  'J','F','M','A','M','J','J','A','S','O','N','D'
                ];
                final i = v.toInt();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    i >= 0 && i < 12 ? months[i] : '',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? (maxY / 3).ceilToDouble() : 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withOpacity(0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(12, (i) {
          final val = data[i + 1] ?? 0;
          final isEmpty = val == 0;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: isEmpty ? 0.5 : val,
                gradient: isEmpty
                    ? LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.06),
                          Colors.white.withOpacity(0.04),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF6C3EF4), Color(0xFF3E8EF4)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                width: 14,
                borderRadius: BorderRadius.circular(6),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─── Daily Line Chart ─────────────────────────────────────────────────────────

class _DailyLineChart extends StatelessWidget {
  final Map<String, double> data;
  const _DailyLineChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final spots = <FlSpot>[];

    for (int i = 29; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      spots.add(FlSpot((29 - i).toDouble(), data[key] ?? 0));
    }

    final maxY = spots.map((s) => s.y).fold(0.0, (a, b) => a > b ? a : b);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 29,
        minY: 0,
        maxY: maxY > 0 ? maxY + 1 : 5,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF1E1E2E),
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toInt()} logs',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ))
                .toList(),
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 7,
              getTitlesWidget: (v, _) {
                final date = now.subtract(Duration(days: 29 - v.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${date.day}/${date.month}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withOpacity(0.05),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            color: const Color(0xFF6C3EF4),
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) => spot.y > 0,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5,
                color: const Color(0xFF6C3EF4),
                strokeWidth: 2,
                strokeColor: const Color(0xFF0A0A0F),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF6C3EF4).withOpacity(0.25),
                  const Color(0xFF6C3EF4).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Countries Section ────────────────────────────────────────────────────────

class _CountriesSection extends StatefulWidget {
  final List countries;
  final int visitedCount;

  const _CountriesSection({
    required this.countries,
    required this.visitedCount,
  });

  @override
  State<_CountriesSection> createState() => _CountriesSectionState();
}

class _CountriesSectionState extends State<_CountriesSection> {
  // All world countries for "Show All" mode
  static const _allCountries = [
    {'name': 'Afghanistan', 'code': 'AF'},
    {'name': 'Albania', 'code': 'AL'},
    {'name': 'Algeria', 'code': 'DZ'},
    {'name': 'Argentina', 'code': 'AR'},
    {'name': 'Australia', 'code': 'AU'},
    {'name': 'Austria', 'code': 'AT'},
    {'name': 'Bangladesh', 'code': 'BD'},
    {'name': 'Belgium', 'code': 'BE'},
    {'name': 'Brazil', 'code': 'BR'},
    {'name': 'Canada', 'code': 'CA'},
    {'name': 'Chile', 'code': 'CL'},
    {'name': 'China', 'code': 'CN'},
    {'name': 'Colombia', 'code': 'CO'},
    {'name': 'Croatia', 'code': 'HR'},
    {'name': 'Czech Republic', 'code': 'CZ'},
    {'name': 'Denmark', 'code': 'DK'},
    {'name': 'Egypt', 'code': 'EG'},
    {'name': 'Ethiopia', 'code': 'ET'},
    {'name': 'Finland', 'code': 'FI'},
    {'name': 'France', 'code': 'FR'},
    {'name': 'Germany', 'code': 'DE'},
    {'name': 'Ghana', 'code': 'GH'},
    {'name': 'Greece', 'code': 'GR'},
    {'name': 'Hungary', 'code': 'HU'},
    {'name': 'India', 'code': 'IN'},
    {'name': 'Indonesia', 'code': 'ID'},
    {'name': 'Iran', 'code': 'IR'},
    {'name': 'Iraq', 'code': 'IQ'},
    {'name': 'Ireland', 'code': 'IE'},
    {'name': 'Israel', 'code': 'IL'},
    {'name': 'Italy', 'code': 'IT'},
    {'name': 'Japan', 'code': 'JP'},
    {'name': 'Jordan', 'code': 'JO'},
    {'name': 'Kenya', 'code': 'KE'},
    {'name': 'Malaysia', 'code': 'MY'},
    {'name': 'Mexico', 'code': 'MX'},
    {'name': 'Morocco', 'code': 'MA'},
    {'name': 'Nepal', 'code': 'NP'},
    {'name': 'Netherlands', 'code': 'NL'},
    {'name': 'New Zealand', 'code': 'NZ'},
    {'name': 'Nigeria', 'code': 'NG'},
    {'name': 'Norway', 'code': 'NO'},
    {'name': 'Pakistan', 'code': 'PK'},
    {'name': 'Peru', 'code': 'PE'},
    {'name': 'Philippines', 'code': 'PH'},
    {'name': 'Poland', 'code': 'PL'},
    {'name': 'Portugal', 'code': 'PT'},
    {'name': 'Romania', 'code': 'RO'},
    {'name': 'Russia', 'code': 'RU'},
    {'name': 'Saudi Arabia', 'code': 'SA'},
    {'name': 'Singapore', 'code': 'SG'},
    {'name': 'South Africa', 'code': 'ZA'},
    {'name': 'South Korea', 'code': 'KR'},
    {'name': 'Spain', 'code': 'ES'},
    {'name': 'Sri Lanka', 'code': 'LK'},
    {'name': 'Sweden', 'code': 'SE'},
    {'name': 'Switzerland', 'code': 'CH'},
    {'name': 'Thailand', 'code': 'TH'},
    {'name': 'Turkey', 'code': 'TR'},
    {'name': 'Ukraine', 'code': 'UA'},
    {'name': 'United Arab Emirates', 'code': 'AE'},
    {'name': 'United Kingdom', 'code': 'GB'},
    {'name': 'United States', 'code': 'US'},
    {'name': 'Vietnam', 'code': 'VN'},
    {'name': 'Zimbabwe', 'code': 'ZW'},
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CountryModeButton(
            icon: Icons.public_rounded,
            label: 'Show All',
            subtitle: '${_allCountries.length} countries',
            color: const Color(0xFF3E8EF4),
            onTap: () => _openCountriesModal(context, showAll: true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CountryModeButton(
            icon: Icons.done_all_rounded,
            label: 'Visited',
            subtitle: '${widget.visitedCount} visited',
            color: const Color(0xFF3EF4A8),
            onTap: () => _openCountriesModal(context, showAll: false),
          ),
        ),
      ],
    );
  }

  void _openCountriesModal(BuildContext context, {required bool showAll}) {
    final visitedCodes = widget.countries
        .map((c) => (c['country_code'] as String? ?? '').toUpperCase())
        .toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountriesModal(
        allCountries: _allCountries,
        visitedCountries: widget.countries,
        visitedCodes: visitedCodes,
        showAll: showAll,
      ),
    );
  }
}

class _CountryModeButton extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;

  const _CountryModeButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF131318),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Countries Modal ──────────────────────────────────────────────────────────

class _CountriesModal extends StatefulWidget {
  final List<Map<String, String>> allCountries;
  final List visitedCountries;
  final Set<String> visitedCodes;
  final bool showAll;

  const _CountriesModal({
    required this.allCountries,
    required this.visitedCountries,
    required this.visitedCodes,
    required this.showAll,
  });

  @override
  State<_CountriesModal> createState() => _CountriesModalState();
}

class _CountriesModalState extends State<_CountriesModal> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List _filteredList() {
    final q = _query.trim().toLowerCase();
    if (widget.showAll) {
      return widget.allCountries
          .where((c) => q.isEmpty || c['name']!.toLowerCase().contains(q))
          .toList();
    } else {
      return widget.visitedCountries
          .where((c) =>
              q.isEmpty ||
              (c['name'] as String? ?? '').toLowerCase().contains(q))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredList();
    final h = MediaQuery.of(context).size.height * 0.88;

    return Container(
      height: h,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F16),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.showAll ? 'All Countries' : 'Visited Countries',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        widget.showAll
                            ? '${widget.visitedCodes.length} of ${widget.allCountries.length} visited'
                            : '${widget.visitedCountries.length} countries explored',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search countries…',
                  hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.35), fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: Colors.white.withOpacity(0.4), size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded,
                              color: Colors.white.withOpacity(0.4), size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // List
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      'No countries found',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 15,
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      final bool isVisited = widget.showAll
                          ? widget.visitedCodes.contains(
                              (c['code'] as String? ?? '').toUpperCase())
                          : true;

                      final String name = widget.showAll
                          ? (c['name'] as String? ?? '')
                          : (c['name'] as String? ?? '');
                      final String code = widget.showAll
                          ? (c['code'] as String? ?? '')
                          : (c['country_code'] as String? ?? '');
                      final int visitCount = widget.showAll
                          ? 0
                          : (c['visit_count'] as int? ?? 1);

                      return _CountryTile(
                        name: name,
                        code: code,
                        visitCount: visitCount,
                        isVisited: isVisited,
                        showAll: widget.showAll,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  final String name, code;
  final int visitCount;
  final bool isVisited, showAll;

  const _CountryTile({
    required this.name,
    required this.code,
    required this.visitCount,
    required this.isVisited,
    required this.showAll,
  });

  String _flagEmoji(String c) {
    if (c.length != 2) return '🏳️';
    return String.fromCharCodes([
      c.toUpperCase().codeUnitAt(0) - 0x41 + 0x1F1E6,
      c.toUpperCase().codeUnitAt(1) - 0x41 + 0x1F1E6,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final blurred = showAll && !isVisited;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: blurred ? 0.35 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isVisited
                ? const Color(0xFF3EF4A8).withOpacity(0.06)
                : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isVisited
                  ? const Color(0xFF3EF4A8).withOpacity(0.2)
                  : Colors.white.withOpacity(0.05),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Text(_flagEmoji(code), style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: blurred
                            ? Colors.white.withOpacity(0.6)
                            : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!showAll || isVisited) ...[
                      const SizedBox(height: 2),
                      Text(
                        showAll
                            ? 'Visited'
                            : 'Visited $visitCount time${visitCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF3EF4A8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isVisited)
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3EF4A8).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Color(0xFF3EF4A8),
                    size: 16,
                  ),
                )
              else
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    color: Colors.white.withOpacity(0.2),
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Loading & Error ──────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C3EF4)),
        strokeWidth: 2.5,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Color(0xFFFF6B6B), size: 48),
            const SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}