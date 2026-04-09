import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/app_settings_service.dart';
import '../../../services/background_location_service.dart';
import '../../../services/location_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isPublic = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() async {
    final user = await ref.read(authServiceProvider).getProfile();
    if (user != null && mounted) {
      setState(() {
        _isPublic = user.isPublic;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTracking = ref.watch(alwaysOnTrackingProvider);
    final intervalSeconds = ref.watch(trackingIntervalProvider);
    final hapticsEnabled = ref.watch(hapticsEnabledProvider);

    return Scaffold(
      backgroundColor: AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: AppColors.lightSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Settings',
          style: GoogleFonts.manrope(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          color: AppColors.textSecondary,
          onPressed: () {
            if (hapticsEnabled) {
              HapticFeedback.selectionClick();
            }
            context.pop();
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppColors.border, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Location Tracking ──────────────────────────────────────
            _SectionLabel(title: 'Location Tracking'),
            const SizedBox(height: 8),
            _SettingsGroup(children: [
              _SettingsTile(
                icon: Icons.my_location_rounded,
                title: 'Background Tracking',
                subtitle: isTracking
                    ? 'Active (${_intervalLabel(intervalSeconds)})'
                    : 'Paused',
                trailing: Switch(
                  value: isTracking,
                  activeThumbColor: AppColors.lightSurface,
                  activeTrackColor: AppColors.primary,
                  inactiveThumbColor: AppColors.lightSurface,
                  inactiveTrackColor: AppColors.border,
                  onChanged: (v) =>
                      _toggleBackgroundTracking(v, intervalSeconds),
                ),
              ),
              _SettingsTile(
                icon: Icons.timer_rounded,
                title: 'Tracking Interval',
                subtitle: _intervalLabel(intervalSeconds),
                onTap: () => _showIntervalPicker(),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Privacy ─────────────────────────────────────────────────
            _SectionLabel(title: 'Privacy & Community'),
            const SizedBox(height: 8),
            _SettingsGroup(children: [
              _SettingsTile(
                icon: Icons.visibility_outlined,
                title: 'Public Profile',
                subtitle: _isPublic ? 'Visible to everyone' : 'Only you',
                trailing: Switch(
                  value: _isPublic,
                  activeThumbColor: AppColors.lightSurface,
                  activeTrackColor: AppColors.primary,
                  inactiveThumbColor: AppColors.lightSurface,
                  inactiveTrackColor: AppColors.border,
                  onChanged: (v) async {
                    setState(() => _isPublic = v);
                    final user =
                        await ref.read(authServiceProvider).getProfile();
                    if (user != null) {
                      await ref
                          .read(authServiceProvider)
                          .updateProfile(user.copyWith(isPublic: v));
                    }
                  },
                ),
              ),
              _SettingsTile(
                icon: Icons.delete_sweep_outlined,
                title: 'Wipe Location Data',
                subtitle: 'Delete all travel logs',
                iconColor: AppColors.error,
                onTap: () => _showWipeConfirmation(),
              ),
            ]),
            const SizedBox(height: 24),

            // ── App Experience ───────────────────────────────────────────
            _SectionLabel(title: 'App Experience'),
            const SizedBox(height: 8),
            _SettingsGroup(children: [
              _SettingsTile(
                icon: Icons.vibration_rounded,
                title: 'Haptic Feedback',
                subtitle: hapticsEnabled ? 'On' : 'Off',
                trailing: Switch(
                  value: hapticsEnabled,
                  activeThumbColor: AppColors.lightSurface,
                  activeTrackColor: AppColors.primary,
                  inactiveThumbColor: AppColors.lightSurface,
                  inactiveTrackColor: AppColors.border,
                  onChanged: (v) async {
                    if (hapticsEnabled) {
                      HapticFeedback.selectionClick();
                    }
                    await ref.read(hapticsEnabledProvider.notifier).set(v);
                    if (v) {
                      HapticFeedback.lightImpact();
                    }
                  },
                ),
              ),
            ]),
            const SizedBox(height: 24),

            // ── Account ──────────────────────────────────────────────────
            _SectionLabel(title: 'Account'),
            const SizedBox(height: 8),
            _SettingsGroup(children: [
              _SettingsTile(
                icon: Icons.download_outlined,
                title: 'Export Data (GDPR)',
                subtitle: 'Download your data as JSON',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Export feature coming soon')),
                  );
                },
              ),
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: 'Sign Out',
                subtitle: 'Log out of your account',
                onTap: () async {
                  if (hapticsEnabled) {
                    HapticFeedback.selectionClick();
                  }
                  await ref.read(authServiceProvider).signOut();
                  if (!context.mounted) return;
                  context.go('/login');
                },
              ),
              _SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Delete Account',
                subtitle: 'Permanently remove all data',
                iconColor: AppColors.error,
                onTap: () => _showDeleteConfirmation(),
              ),
            ]),
            const SizedBox(height: 32),

            // ── App Info ─────────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.flight_takeoff_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'TrailSync v1.0.0',
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Every kilometre tells a story',
                    style: GoogleFonts.inter(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showIntervalPicker() {
    final selectedSeconds = ref.read(trackingIntervalProvider);
    final hapticsEnabled = ref.read(hapticsEnabledProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Tracking Interval',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ...kTrackingIntervals.map(
              (interval) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: selectedSeconds == interval.seconds
                        ? AppColors.primaryLight
                        : AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: selectedSeconds == interval.seconds
                        ? AppColors.primary
                        : AppColors.textMuted,
                  ),
                ),
                title: Text(interval.label,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    )),
                subtitle: Text(
                  interval.seconds == 0
                      ? 'Highest accuracy, more battery use'
                      : 'Lower battery use',
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: selectedSeconds == interval.seconds
                    ? const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary)
                    : null,
                onTap: () async {
                  if (hapticsEnabled) {
                    HapticFeedback.selectionClick();
                  }
                  await ref
                      .read(trackingIntervalProvider.notifier)
                      .set(interval.seconds);
                  BackgroundLocationService.updateInterval(interval.seconds);
                  navigator.pop();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Tracking interval set to ${_intervalLabel(interval.seconds)}.',
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleBackgroundTracking(
      bool enable, int intervalSeconds) async {
    final messenger = ScaffoldMessenger.of(context);

    if (!enable) {
      await ref.read(alwaysOnTrackingProvider.notifier).set(false);
      await BackgroundLocationService.stop();
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Background tracking disabled.')),
      );
      return;
    }

    final ready = await _ensureBackgroundLocationReady();
    if (!ready) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Enable location services and allow background location to keep tracking active.',
          ),
        ),
      );
      return;
    }

    await ref.read(alwaysOnTrackingProvider.notifier).set(true);
    final started = await BackgroundLocationService.start();
    if (!started) {
      await ref.read(alwaysOnTrackingProvider.notifier).set(false);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Notification permission is required for background tracking.'),
        ),
      );
      return;
    }
    BackgroundLocationService.updateInterval(intervalSeconds);

    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Background tracking enabled. A system notification indicates location is being used to store routes.',
        ),
      ),
    );
  }

  Future<bool> _ensureBackgroundLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always) {
        return false;
      }
    }

    await Permission.notification.request();
    return true;
  }

  String _intervalLabel(int seconds) {
    if (seconds <= 0) return 'Continuous';
    final minutes = (seconds / 60).round();
    return 'Every $minutes min';
  }

  void _showWipeConfirmation() {
    final hapticsEnabled = ref.read(hapticsEnabledProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightSurface,
        title: Text(
          'Wipe Location Data?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete all your logs, routes, visited places, memories and stats. Your account will remain active.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (hapticsEnabled) {
                HapticFeedback.selectionClick();
              }
              Navigator.pop(ctx);
            },
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              if (hapticsEnabled) {
                HapticFeedback.mediumImpact();
              }
              Navigator.pop(ctx);
              await _wipeTravelData();
            },
            child: Text('Wipe',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _wipeTravelData() async {
    final uid = AppConstants.supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No signed in user found')),
        );
      }
      return;
    }

    try {
      // Stop tracking services first so wipe is not raced by new writes.
      await ref.read(locationServiceProvider).stopTracking(
            completeRoute: false,
            markDestination: false,
          );
      await ref.read(alwaysOnTrackingProvider.notifier).set(false);
      await BackgroundLocationService.stop();

      final memories = await AppConstants.supabase
          .from('travel_memories')
          .select('image_url')
          .eq('user_id', uid);

      final memoryPaths = (memories as List)
          .map((row) => _storagePathFromPublicUrl(
                row['image_url'] as String?,
                'memories',
              ))
          .whereType<String>()
          .toList();

      final failedTables = <String>[];

      Future<void> deleteByUserId(String table, {int maxAttempts = 3}) async {
        Object? lastError;
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            await AppConstants.supabase.from(table).delete().eq('user_id', uid);

            final remaining = await AppConstants.supabase
                .from(table)
                .select('id')
                .eq('user_id', uid)
                .limit(1);

            if ((remaining as List).isEmpty) {
              return;
            }
          } catch (e) {
            lastError = e;
          }
        }

        if (lastError != null) {
          failedTables.add('$table (${_compactError(lastError)})');
        } else {
          failedTables.add('$table (rows still present)');
        }
      }

      await deleteByUserId('travel_logs');
      await deleteByUserId('routes');
      await deleteByUserId('visited_cities');
      await deleteByUserId('visited_countries');
      await deleteByUserId('visited_villages');
      await deleteByUserId('visited_states');
      await deleteByUserId('travel_memories');
      await deleteByUserId('achievements');
      await deleteByUserId('xp_history');

      if (memoryPaths.isNotEmpty) {
        try {
          await AppConstants.supabase.storage.from('memories').remove(memoryPaths);
        } catch (e) {
          failedTables.add('memories (storage: ${_compactError(e)})');
        }
      }

      try {
        await AppConstants.supabase.from('users').update({
          'total_distance_km': 0,
          'countries_visited': 0,
          'cities_visited': 0,
          'villages_visited': 0,
          'total_xp': 0,
          'travel_level': 1,
        }).eq('id', uid);
      } catch (e) {
        failedTables.add('users (counters: ${_compactError(e)})');
      }

      ref.invalidate(currentUserProvider);

      if (!mounted) return;

      if (failedTables.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All travel data wiped successfully')),
        );
      } else {
        final brief = failedTables.take(3).join(', ');
        final hasMore = failedTables.length > 3;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasMore
                  ? 'Wipe incomplete: $brief (+${failedTables.length - 3} more)'
                  : 'Wipe incomplete: $brief',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to wipe travel data: $e')),
        );
      }
    }
  }

  String? _storagePathFromPublicUrl(String? publicUrl, String bucket) {
    if (publicUrl == null || publicUrl.isEmpty) return null;

    final uri = Uri.tryParse(publicUrl);
    if (uri == null) return null;

    final bucketIndex = uri.pathSegments.indexOf(bucket);
    if (bucketIndex < 0 || bucketIndex + 1 >= uri.pathSegments.length) {
      return null;
    }

    return uri.pathSegments.sublist(bucketIndex + 1).join('/');
  }

  String _compactError(Object error) {
    final text = error.toString().replaceAll('\n', ' ').trim();
    if (text.length <= 80) return text;
    return '${text.substring(0, 80)}...';
  }

  void _showDeleteConfirmation() {
    final hapticsEnabled = ref.read(hapticsEnabledProvider);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.lightSurface,
        title: Text(
          'Delete Account?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This will permanently delete your account and all associated data. This cannot be undone.',
          style: GoogleFonts.inter(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (hapticsEnabled) {
                HapticFeedback.selectionClick();
              }
              Navigator.pop(ctx);
            },
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              if (hapticsEnabled) {
                HapticFeedback.mediumImpact();
              }
              Navigator.pop(ctx);
              await ref.read(authServiceProvider).deleteAccount();
              if (mounted) context.go('/login');
            },
            child: Text('Delete',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ─── Settings Group (card wrapper) ───────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;

  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        children: List.generate(children.length, (i) {
          return Column(
            children: [
              children[i],
              if (i < children.length - 1)
                Padding(
                  padding: const EdgeInsets.only(left: 72),
                  child: Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.border,
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }
}

// ─── Settings Tile ────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: iconColor != null ? 0.1 : 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
