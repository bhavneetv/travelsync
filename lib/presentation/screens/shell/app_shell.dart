import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';

class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location == '/') return 0;
    if (location == '/stats') return 1;
    if (location == '/memories') return 2;
    if (location == '/groups') return 3;
    if (location == '/profile') return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final index = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        color: AppColors.lightBg,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.lightSurface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _NavItem(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isActive: index == 0,
                    onTap: index == 0 ? null : () => context.go('/'),
                  ),
                  _NavItem(
                    icon: Icons.map_rounded,
                    label: 'Stats',
                    isActive: index == 1,
                    onTap: index == 1 ? null : () => context.go('/stats'),
                  ),
                  _NavItem(
                    icon: Icons.explore_rounded,
                    label: 'Travel',
                    isActive: index == 2,
                    onTap: index == 2 ? null : () => context.go('/memories'),
                  ),
                  _NavItem(
                    icon: Icons.groups_rounded,
                    label: 'Groups',
                    isActive: index == 3,
                    onTap: index == 3 ? null : () => context.go('/groups'),
                  ),
                  _NavItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    isActive: index == 4,
                    onTap: index == 4 ? null : () => context.go('/profile'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? AppColors.textDark : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isActive
                      ? AppColors.lightSurface
                      : AppColors.textDarkSecondary,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: isActive
                        ? AppColors.lightSurface
                        : AppColors.textDarkSecondary,
                    fontSize: 11,
                    letterSpacing: 0.8,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
