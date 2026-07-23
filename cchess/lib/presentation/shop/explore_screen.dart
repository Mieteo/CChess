import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../economy/economy_controller.dart';
import 'shop_controller.dart';

/// Khám Phá (S16) — the discovery hub. A route (not a 6th tab) reached from
/// Trang Chủ + Hồ Sơ; surfaces the Shop (Thương Thành), Inventory (Balo) and
/// the economy extension: Sự Kiện, Phúc Lợi, Hộp Thư, Đúc Bàn Cờ.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletProvider);
    final wallet = walletAsync.valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Khám Phá'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                CChessCurrencyDisplay(amount: wallet?.coins ?? 0),
                AppSpacing.hGapXs,
                CChessCurrencyDisplay(
                  amount: wallet?.gems ?? 0,
                  currency: CChessCurrency.gem,
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.base,
            AppSpacing.base,
            96,
          ),
          children: [
            _Banner(
              coins: wallet?.coins ?? 0,
              gems: wallet?.gems ?? 0,
              loading: walletAsync.isLoading && wallet == null,
            ),
            AppSpacing.vGapLg,
            const SectionHeader(title: 'Cửa Hàng & Trang Bị'),
            AppSpacing.vGapSm,
            _FeatureTile(
              title: 'Thương Thành',
              subtitle: 'Mua bàn cờ, quân cờ, khung avatar…',
              icon: Icons.storefront,
              color: AppColors.accentGold,
              onTap: () => context.push(AppConstants.routeShop),
            ),
            _FeatureTile(
              title: 'Balo Vật Phẩm',
              subtitle: 'Xem và trang bị đồ đã sở hữu',
              icon: Icons.backpack_outlined,
              color: AppColors.tertiary,
              onTap: () => context.push(AppConstants.routeInventory),
            ),
            _FeatureTile(
              title: 'Đúc Bàn Cờ',
              subtitle: 'Ghép nguyên liệu thành bàn cờ độc bản',
              icon: Icons.auto_awesome_outlined,
              color: AppColors.accentGold,
              onTap: () => context.push(AppConstants.routeCrafting),
            ),
            AppSpacing.vGapLg,
            const SectionHeader(title: 'Quà & Sự Kiện'),
            AppSpacing.vGapSm,
            _FeatureTile(
              title: 'Sự Kiện',
              subtitle: 'Sự kiện theo mùa: Tết, 30/4, 2/9…',
              icon: Icons.celebration_outlined,
              color: AppColors.vermilionRed,
              onTap: () => context.push(AppConstants.routeEvents),
            ),
            _FeatureTile(
              title: 'Phúc Lợi',
              subtitle: 'Điểm danh hàng ngày, quà tân thủ',
              icon: Icons.card_giftcard_outlined,
              color: AppColors.tealSuccess,
              onTap: () => context.push(AppConstants.routeWelfare),
            ),
            _FeatureTile(
              title: 'Hộp Thư',
              subtitle: 'Nhận quà & thông báo từ hệ thống',
              icon: Icons.mail_outline,
              color: AppColors.parchmentTan,
              badgeCount: ref.watch(unreadMailCountProvider),
              onTap: () => context.push(AppConstants.routeMail),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final int coins;
  final int gems;
  final bool loading;
  const _Banner({required this.coins, required this.gems, required this.loading});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.inkBlack, AppColors.woodDark],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ví của bạn', style: AppTextStyles.captionSm
              .copyWith(color: AppColors.parchmentTan)),
          AppSpacing.vGapSm,
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text('Đang tải số dư…'),
            )
          else
            Row(
              children: [
                CChessCurrencyDisplay(amount: coins, large: true),
                AppSpacing.hGapSm,
                CChessCurrencyDisplay(
                  amount: gems,
                  currency: CChessCurrency.gem,
                  large: true,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  /// Optional badge (e.g. unread mail count); hidden when 0.
  final int badgeCount;

  const _FeatureTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final comingSoon = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: CChessCard(
        onTap: onTap,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.vermilionRed,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badgeCount',
                        style: AppTextStyles.captionSm.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: AppTextStyles.headingMd),
                      if (comingSoon) ...[
                        AppSpacing.hGapSm,
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.outlineVariant.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'SẮP CÓ',
                            style: AppTextStyles.captionSm.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    subtitle,
                    style: AppTextStyles.captionSm
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!comingSoon)
              const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
