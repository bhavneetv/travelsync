import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants.dart';

final xpServiceProvider = Provider<XPService>((ref) => XPService());

class XPService {
  final _supabase = AppConstants.supabase;

  /// Calculate level from XP
  static int calculateLevel(int xp) {
    int level = 1;
    for (final entry in AppConstants.levelThresholds.entries) {
      if (xp >= entry.value) {
        level = entry.key;
      }
    }
    return level;
  }

  /// Get level name
  static String getLevelName(int level) {
    return AppConstants.levelNames[level] ?? 'Traveler';
  }

  /// Get XP needed for next level
  static int xpForNextLevel(int currentXp) {
    final currentLevel = calculateLevel(currentXp);
    final nextLevel = currentLevel + 1;
    if (AppConstants.levelThresholds.containsKey(nextLevel)) {
      return AppConstants.levelThresholds[nextLevel]!;
    }
    return AppConstants.levelThresholds[6]!; // Max level
  }

  /// Get progress percentage to next level (0.0 - 1.0)
  static double levelProgress(int currentXp) {
    final currentLevel = calculateLevel(currentXp);
    final currentThreshold = AppConstants.levelThresholds[currentLevel] ?? 0;
    final nextThreshold = AppConstants.levelThresholds[currentLevel + 1];

    if (nextThreshold == null) return 1.0; // Max level

    final progress = (currentXp - currentThreshold) /
        (nextThreshold - currentThreshold);
    return progress.clamp(0.0, 1.0);
  }

  /// Award XP to user
  Future<void> awardXP({
    required String userId,
    required int delta,
    required String reason,
    int? refId,
  }) async {
    // Insert XP history
    await _supabase.from('xp_history').insert({
      'user_id': userId,
      'delta': delta,
      'reason': reason,
      'ref_id': refId,
    });

    // Update user total XP
    final userData = await _supabase
        .from('users')
        .select('total_xp')
        .eq('id', userId)
        .single();

    final currentXp = userData['total_xp'] as int? ?? 0;
    final newXp = currentXp + delta;
    final newLevel = calculateLevel(newXp);

    await _supabase.from('users').update({
      'total_xp': newXp,
      'travel_level': newLevel,
    }).eq('id', userId);
  }

  /// Check and award badge
  Future<bool> checkAndAwardBadge({
    required String userId,
    required String badgeKey,
  }) async {
    // Check if already earned
    final existing = await _supabase
        .from('achievements')
        .select()
        .eq('user_id', userId)
        .eq('badge_key', badgeKey)
        .maybeSingle();

    if (existing != null) return false;

    // Award badge
    await _supabase.from('achievements').insert({
      'user_id': userId,
      'badge_key': badgeKey,
    });

    return true;
  }

  /// Get badge info
  static Map<String, dynamic> getBadgeInfo(String badgeKey) {
    const badges = {
      'early_bird': {
        'name': 'Early Bird',
        'description': 'Travel before 6 AM (5 trips)',
        'icon': '🌅',
        'xp': 25,
      },
      'night_owl': {
        'name': 'Night Owl',
        'description': 'Travel after 10 PM (5 trips)',
        'icon': '🦉',
        'xp': 25,
      },
      'continent_collector': {
        'name': 'Continent Collector',
        'description': 'Visit 3+ continents',
        'icon': '🌍',
        'xp': 150,
      },
      'speed_demon': {
        'name': 'Speed Demon',
        'description': 'Avg speed >120 km/h on highway trip',
        'icon': '🏎️',
        'xp': 30,
      },
      'team_player': {
        'name': 'Team Player',
        'description': 'Complete 3 group trips',
        'icon': '🤝',
        'xp': 50,
      },
      'storyteller': {
        'name': 'Storyteller',
        'description': 'Add photos to 10 trips',
        'icon': '📸',
        'xp': 40,
      },
      'streak_master': {
        'name': 'Streak Master',
        'description': '30-day travel streak',
        'icon': '🔥',
        'xp': 100,
      },
    };
    return badges[badgeKey] ?? {
      'name': badgeKey,
      'description': '',
      'icon': '🏅',
      'xp': 0,
    };
  }
}
