import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../economy/economy_controller.dart';
import 'cchess_app_bar.dart';
import 'cchess_bottom_nav.dart';

/// Top-level scaffold containing the persistent AppBar + bottom navigation
/// that wraps the five main tabs.
class AppShell extends ConsumerWidget {
  final Widget child;
  final int currentIndex;
  final String currentLocation;

  const AppShell({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.currentLocation,
  });

  static const tabs = <NavTabInfo>[
    NavTabInfo(
      label: 'Trang Chủ',
      icon: Icons.fort_outlined,
      activeIcon: Icons.fort,
      route: '/',
    ),
    NavTabInfo(
      label: 'Học Tập',
      icon: Icons.menu_book_outlined,
      activeIcon: Icons.menu_book,
      route: '/learning',
    ),
    NavTabInfo(
      label: 'Đối Đầu',
      icon: Icons.sports_esports_outlined,
      activeIcon: Icons.sports_esports,
      route: '/compete',
    ),
    NavTabInfo(
      label: 'Cộng Đồng',
      icon: Icons.groups_outlined,
      activeIcon: Icons.groups,
      route: '/community',
    ),
    NavTabInfo(
      label: 'Hồ Sơ',
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      route: '/profile',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Unread/unclaimed mail drives the bell badge (same count as the Explore
    // hub tile). valueOrNull → 0 while loading/offline.
    final unreadMail = ref.watch(unreadMailCountProvider);
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      appBar: CChessAppBar(
        notificationCount: unreadMail,
        onAvatarTap: () => context.go(AppConstants.routeProfile),
        onNotificationTap: () => context.push(AppConstants.routeMail),
        onSettingsTap: () => context.push(AppConstants.routeSettings),
      ),
      // The tab cross-fade lives in the router's CustomTransitionPage. An
      // AnimatedSwitcher here used to retain the outgoing tab's subtree next
      // to the Navigator's copy, throwing "Duplicate GlobalKey detected"
      // bursts on relaunch/IME changes (KeyedSubtree-[<'/'>] never updating).
      body: child,
      bottomNavigationBar: CChessBottomNav(
        tabs: tabs,
        currentIndex: currentIndex,
        onTap: (index) {
          final target = tabs[index].route;
          if (target != currentLocation) {
            context.go(target);
          }
        },
      ),
    );
  }
}

/// Empty placeholder body shown when a feature isn't yet implemented.
class TodoSection extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;

  const TodoSection({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.construction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.parchmentTan),
            AppSpacing.vGapMd,
            Text(
              title,
              style: AppTextStyles.titleLg,
              textAlign: TextAlign.center,
            ),
            AppSpacing.vGapSm,
            Text(
              description,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
