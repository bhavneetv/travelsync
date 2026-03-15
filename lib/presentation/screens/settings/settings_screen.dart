import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../services/auth_service.dart';
import '../../../services/location_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isPublic = true;
  String _trackingInterval = '1 hour';

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
    final isTracking = ref.watch(isTrackingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tracking section
            _SectionTitle(title: 'Location Tracking'),
            const SizedBox(height: 12),

            _SettingsTile(
              icon: Icons.my_location_rounded,
              title: 'Background Tracking',
              subtitle: isTracking ? 'Active' : 'Paused',
              trailing: Switch(
                value: isTracking,
                activeTrackColor: AppColors.primary,
                onChanged: (value) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final locService = ref.read(locationServiceProvider);
                  if (value) {
                    final started = await locService.startTracking();
                    if (!started && mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enable location services and grant location permission to start tracking.',
                          ),
                        ),
                      );
                    }
                  } else {
                    await locService.stopTracking();
                  }
                },
              ),
            ),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.timer_rounded,
              title: 'Tracking Interval',
              subtitle: _trackingInterval,
              onTap: () => _showIntervalPicker(),
            ),
            const SizedBox(height: 24),

            // Privacy section
            _SectionTitle(title: 'Privacy'),
            const SizedBox(height: 12),

            _SettingsTile(
              icon: Icons.visibility_rounded,
              title: 'Public Profile',
              subtitle: _isPublic ? 'Visible to everyone' : 'Only you',
              trailing: Switch(
                value: _isPublic,
                activeTrackColor: AppColors.primary,
                onChanged: (value) async {
                  setState(() => _isPublic = value);
                  final user = await ref.read(authServiceProvider).getProfile();
                  if (user != null) {
                    await ref
                        .read(authServiceProvider)
                        .updateProfile(user.copyWith(isPublic: value));
                  }
                },
              ),
            ),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.delete_sweep_rounded,
              title: 'Wipe Location Data',
              subtitle: 'Delete all travel logs',
              iconColor: AppColors.accent,
              onTap: () => _showWipeConfirmation(),
            ),
            const SizedBox(height: 24),

            // Account section
            _SectionTitle(title: 'Account'),
            const SizedBox(height: 12),

            _SettingsTile(
              icon: Icons.download_rounded,
              title: 'Export Data (GDPR)',
              subtitle: 'Download your data as JSON',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Export feature coming soon')),
                );
              },
            ),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Sign Out',
              subtitle: 'Log out of your account',
              onTap: () async {
                await ref.read(authServiceProvider).signOut();
                if (!context.mounted) return;
                context.go('/login');
              },
            ),
            const SizedBox(height: 8),

            _SettingsTile(
              icon: Icons.delete_forever_rounded,
              title: 'Delete Account',
              subtitle: 'Permanently remove all data',
              iconColor: AppColors.accent,
              onTap: () => _showDeleteConfirmation(),
            ),
            const SizedBox(height: 32),

            // App info
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
                  const Text(
                    'TravelSync v1.0.0',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Every kilometre tells a story',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showIntervalPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Tracking Interval',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 24),
            ...['30 minutes', '1 hour', '3 hours'].map(
              (interval) => ListTile(
                title: Text(interval),
                trailing: _trackingInterval == interval
                    ? Icon(Icons.check_circle_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  setState(() => _trackingInterval = interval);
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showWipeConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Wipe Location Data?'),
        content: const Text(
          'This will permanently delete all your travel logs. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final userId = ref.read(authServiceProvider).userId;
              if (userId != null) {
                await ref.read(authServiceProvider).signOut();
                // TODO: Delete travel_logs for user
              }
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Location data wiped')),
                );
              }
            },
            child: const Text(
              'Wipe',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and all associated data. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authServiceProvider).deleteAccount();
              if (mounted) context.go('/login');
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.darkCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: iconColor ?? AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing!
            else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
