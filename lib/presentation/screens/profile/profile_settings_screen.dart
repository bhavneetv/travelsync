import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants.dart';
import '../../../services/auth_service.dart';
import '../../../services/location_service.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState
    extends ConsumerState<ProfileSettingsScreen> {
  // Notification toggles
  bool _pushEnabled = true;
  bool _weeklyDigest = true;
  bool _badgeAlerts = true;

  // Privacy toggles
  bool _publicProfile = false;
  bool _showOnLeaderboard = true;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A0A0F),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white70, size: 22),
            onPressed: () => context.pop(),
          ),
          title: const Text(
            'Settings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
        ),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Account ────────────────────────────────────────────
              const _GroupLabel('Account'),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _ActionTile(
                    icon: Icons.edit_rounded,
                    iconColor: const Color(0xFF3E8EF4),
                    title: 'Edit Profile',
                    subtitle: 'Name, username, bio, password',
                    onTap: () => context.push('/profile/edit'),
                  ),
                  _ActionTile(
                    icon: Icons.mail_outline_rounded,
                    iconColor: const Color(0xFF3EF4A8),
                    title: 'Email Address',
                    subtitle: _currentEmail(),
                    onTap: () => _changeEmailSheet(context),
                  ),
                  _ActionTile(
                    icon: Icons.link_rounded,
                    iconColor: const Color(0xFFFFD166),
                    title: 'Connected Accounts',
                    subtitle: 'Google, Apple',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Notifications ──────────────────────────────────────
              const _GroupLabel('Notifications'),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _ToggleTile(
                    icon: Icons.notifications_outlined,
                    iconColor: const Color(0xFFFF9F43),
                    title: 'Push Notifications',
                    subtitle: 'Badges, streaks and activity',
                    value: _pushEnabled,
                    onChanged: (v) => setState(() => _pushEnabled = v),
                  ),
                  _ToggleTile(
                    icon: Icons.summarize_outlined,
                    iconColor: const Color(0xFF3E8EF4),
                    title: 'Weekly Digest',
                    subtitle: 'Your travel summary every Monday',
                    value: _weeklyDigest,
                    onChanged: (v) => setState(() => _weeklyDigest = v),
                  ),
                  _ToggleTile(
                    icon: Icons.emoji_events_outlined,
                    iconColor: const Color(0xFFFFD166),
                    title: 'Badge Alerts',
                    subtitle: 'Notify when you earn a badge',
                    value: _badgeAlerts,
                    onChanged: (v) => setState(() => _badgeAlerts = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Privacy ────────────────────────────────────────────
              const _GroupLabel('Privacy'),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _ToggleTile(
                    icon: Icons.public_rounded,
                    iconColor: const Color(0xFF3EF4A8),
                    title: 'Public Profile',
                    subtitle: 'Anyone can view your travel stats',
                    value: _publicProfile,
                    onChanged: (v) => setState(() => _publicProfile = v),
                  ),
                  _ToggleTile(
                    icon: Icons.leaderboard_outlined,
                    iconColor: const Color(0xFF3E8EF4),
                    title: 'Show on Leaderboard',
                    subtitle: 'Appear in global rankings',
                    value: _showOnLeaderboard,
                    onChanged: (v) =>
                        setState(() => _showOnLeaderboard = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Data ───────────────────────────────────────────────
              const _GroupLabel('Data'),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _ActionTile(
                    icon: Icons.download_outlined,
                    iconColor: const Color(0xFF3EF4A8),
                    title: 'Export My Data',
                    subtitle: 'Download all your travel records',
                    onTap: () => _exportDataSheet(context),
                  ),
                  _ActionTile(
                    icon: Icons.delete_sweep_outlined,
                    iconColor: const Color(0xFFFF9F43),
                    title: 'Wipe Travel Data',
                    subtitle: 'Delete logs, routes & visited places',
                    onTap: () => _wipeTravelDataDialog(context),
                    destructive: true,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── About ──────────────────────────────────────────────
              const _GroupLabel('About'),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _ActionTile(
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFF3E8EF4),
                    title: 'Privacy Policy',
                    onTap: () {},
                  ),
                  _ActionTile(
                    icon: Icons.description_outlined,
                    iconColor: Colors.white54,
                    title: 'Terms of Service',
                    onTap: () {},
                  ),
                  _ActionTile(
                    icon: Icons.info_outline_rounded,
                    iconColor: Colors.white54,
                    title: 'App Version',
                    subtitle: 'v1.0.0',
                    onTap: null,
                    trailing: const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── Danger Zone ───────────────────────────────────────
              const _GroupLabel('Danger Zone'),
              const SizedBox(height: 10),
              _SettingsGroup(
                children: [
                  _ActionTile(
                    icon: Icons.logout_rounded,
                    iconColor: const Color(0xFFFF6B6B),
                    title: 'Sign Out',
                    onTap: () => _signOutDialog(context),
                    destructive: true,
                  ),
                  _ActionTile(
                    icon: Icons.person_remove_outlined,
                    iconColor: const Color(0xFFFF6B6B),
                    title: 'Delete Account',
                    subtitle: 'Permanently remove your account',
                    onTap: () => _deleteAccountDialog(context),
                    destructive: true,
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _currentEmail() =>
      AppConstants.supabase.auth.currentUser?.email ?? 'Not set';

  void _changeEmailSheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SimpleInputSheet(
        title: 'Change Email',
        hint: 'New email address',
        controller: ctrl,
        keyboardType: TextInputType.emailAddress,
        onConfirm: () async {
          try {
            await AppConstants.supabase.auth
                .updateUser(UserAttributes(email: ctrl.text.trim()));
            if (context.mounted) {
              Navigator.pop(context);
              _toast(context, 'Confirmation sent to ${ctrl.text}',
                  success: true);
            }
          } catch (e) {
            if (context.mounted) _toast(context, e.toString());
          }
        },
      ),
    );
  }

  void _exportDataSheet(BuildContext context) {
    _toast(context, 'Export feature coming soon', success: true);
  }

  void _wipeTravelDataDialog(BuildContext context) {
    _dangerDialog(
      context,
      title: 'Wipe Travel Data?',
      body:
          'This will permanently delete all your logs, routes, and visited places. Your account will remain active.',
      confirmLabel: 'Wipe Data',
      onConfirm: () => _wipeTravelData(context),
    );
  }

  Future<void> _wipeTravelData(BuildContext context) async {
    final uid = AppConstants.supabase.auth.currentUser?.id;
    if (uid == null) {
      if (context.mounted) {
        _toast(context, 'No signed in user found');
      }
      return;
    }

    try {
      // Prevent background tracking from writing new rows during wipe.
      await ref.read(locationServiceProvider).stopTracking();

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

      Future<void> deleteByUserId(String table) async {
        try {
          await AppConstants.supabase.from(table).delete().eq('user_id', uid);

          final remaining = await AppConstants.supabase
              .from(table)
              .select('id')
              .eq('user_id', uid)
              .limit(1);

          if ((remaining as List).isNotEmpty) {
            failedTables.add('$table (rows still present)');
          }
        } catch (e) {
          failedTables.add('$table (${_compactError(e)})');
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
          await AppConstants.supabase.storage
              .from('memories')
              .remove(memoryPaths);
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

        final user = await AppConstants.supabase
            .from('users')
            .select(
              'total_distance_km, countries_visited, cities_visited, villages_visited, total_xp, travel_level',
            )
            .eq('id', uid)
            .single();

        final countersAreZero =
            (user['total_distance_km'] as num?) == 0 &&
            (user['countries_visited'] as int?) == 0 &&
            (user['cities_visited'] as int?) == 0 &&
            (user['villages_visited'] as int?) == 0 &&
            (user['total_xp'] as int?) == 0 &&
            (user['travel_level'] as int?) == 1;

        if (!countersAreZero) {
          failedTables.add('users (counters not reset)');
        }
      } catch (e) {
        failedTables.add('users (counters: ${_compactError(e)})');
      }

      ref.invalidate(currentUserProvider);

      if (context.mounted) {
        if (failedTables.isEmpty) {
          _toast(context, 'Travel data wiped', success: true);
        } else {
          final brief = failedTables.take(3).join(', ');
          final hasMore = failedTables.length > 3;
          _toast(
            context,
            hasMore
                ? 'Wipe incomplete: $brief (+${failedTables.length - 3} more)'
                : 'Wipe incomplete: $brief',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        _toast(context, 'Failed to wipe travel data: $e');
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

  void _signOutDialog(BuildContext context) {
    _dangerDialog(
      context,
      title: 'Sign Out?',
      body: 'You will be returned to the login screen.',
      confirmLabel: 'Sign Out',
      onConfirm: () async {
        await AppConstants.supabase.auth.signOut();
        if (context.mounted) context.go('/login');
      },
    );
  }

  void _deleteAccountDialog(BuildContext context) {
    _dangerDialog(
      context,
      title: 'Delete Account?',
      body:
          'This action is irreversible. All your data, badges, and travel history will be permanently deleted.',
      confirmLabel: 'Delete Account',
      onConfirm: () async {
        try {
          final uid = AppConstants.supabase.auth.currentUser?.id;
          if (uid == null) return;
          // Delete user data then auth account
          await AppConstants.supabase
              .from('users')
              .delete()
              .eq('id', uid);
          await AppConstants.supabase.auth.signOut();
          if (context.mounted) context.go('/login');
        } catch (e) {
          if (context.mounted) _toast(context, e.toString());
        }
      },
    );
  }

  void _dangerDialog(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (_) => _DangerDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        onConfirm: onConfirm,
      ),
    );
  }

  void _toast(BuildContext ctx, String msg, {bool success = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg,
            style: const TextStyle(color: Colors.white, fontSize: 13)),
        backgroundColor: success
            ? const Color(0xFF3EF4A8).withOpacity(0.15)
            : const Color(0xFFFF6B6B).withOpacity(0.15),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      );
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131318),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
            width: 1,
          ),
        ),
        child: Column(
          children: children
              .expand((w) sync* {
                yield w;
                if (w != children.last) {
                  yield Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withOpacity(0.05),
                    indent: 56,
                    endIndent: 16,
                  );
                }
              })
              .toList(),
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.destructive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withOpacity(0.03),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(destructive ? 0.1 : 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    color: destructive
                        ? const Color(0xFFFF6B6B)
                        : iconColor,
                    size: 17),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: destructive
                            ? const Color(0xFFFF6B6B)
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.35),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  (onTap != null
                      ? Icon(Icons.chevron_right_rounded,
                          color: Colors.white.withOpacity(0.2), size: 18)
                      : const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: iconColor, size: 17),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          _MiniSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Compact switch styled to match the dark theme
class _MiniSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _MiniSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        width: 44,
        height: 26,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value
              ? const Color(0xFF3EF4A8).withOpacity(0.85)
              : Colors.white.withOpacity(0.1),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment:
                  value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(3),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? const Color(0xFF0A0A0F) : Colors.white54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Danger Dialog ────────────────────────────────────────────────────────────

class _DangerDialog extends StatefulWidget {
  final String title, body, confirmLabel;
  final Future<void> Function() onConfirm;

  const _DangerDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.onConfirm,
  });

  @override
  State<_DangerDialog> createState() => _DangerDialogState();
}

class _DangerDialogState extends State<_DangerDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1A22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFFF6B6B), size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.body,
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 13,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _loading
                        ? null
                        : () async {
                            setState(() => _loading = true);
                            try {
                              await widget.onConfirm();
                            } finally {
                              if (mounted) {
                                setState(() => _loading = false);
                                Navigator.pop(context);
                              }
                            }
                          },
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B6B).withOpacity(0.9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                widget.confirmLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Simple Input Sheet ───────────────────────────────────────────────────────

class _SimpleInputSheet extends StatelessWidget {
  final String title, hint;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final VoidCallback onConfirm;

  const _SimpleInputSheet({
    required this.title,
    required this.hint,
    required this.controller,
    required this.keyboardType,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF131318),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.3), fontSize: 14),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD166),
                foregroundColor: const Color(0xFF0A0A0F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}