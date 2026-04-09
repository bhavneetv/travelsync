import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme.dart';
import '../../../services/app_settings_service.dart';

class AppShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final index = _currentIndex(context);
    final hapticsEnabled = ref.watch(hapticsEnabledProvider);

    return Scaffold(
      body: child,
      bottomNavigationBar: _StitchBottomNav(
        currentIndex: index,
        onTap: (i) {
          if (hapticsEnabled) {
            HapticFeedback.selectionClick();
          }
          switch (i) {
            case 0:
              context.go('/');
            case 1:
              context.go('/stats');
            case 2:
              context.go('/memories');
            case 3:
              context.go('/groups');
            case 4:
              context.go('/profile');
          }
        },
      ),
    );
  }
}

/// Stitch-design bottom navigation bar:
/// - Solid white background
/// - Thin top border (#E2E8F0)
/// - Active: blue icon + blue label
/// - Inactive: muted slate icons
class _StitchBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _StitchBottomNav({
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavDef(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home'),
    _NavDef(icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart_rounded, label: 'Stats'),
    _NavDef(icon: Icons.explore_outlined, activeIcon: Icons.explore_rounded, label: 'Travel'),
    _NavDef(icon: Icons.group_outlined, activeIcon: Icons.group_rounded, label: 'Groups'),
    _NavDef(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.lightSurface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = i == currentIndex;
              return Expanded(
                child: InkWell(
                  onTap: i == currentIndex ? null : () => onTap(i),
                  splashColor: AppColors.primaryLight.withValues(alpha: 0.3),
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isActive ? item.activeIcon : item.icon,
                        size: 22,
                        color: isActive ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive ? AppColors.primary : AppColors.textMuted,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavDef {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavDef({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}
