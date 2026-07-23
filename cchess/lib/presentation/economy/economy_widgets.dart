import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/remote/economy_api_source.dart';
import '../../data/models/economy_models.dart';
import '../../data/models/shop_item.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../shop/shop_controller.dart';

/// Shared visual pieces of the S16 economy screens (mail / events / welfare /
/// crafting): reward chips, claim snackbars and the standard empty/error body.

/// Crafting materials never appear in the shop catalog, so they carry their
/// own display names. Unknown ids fall back to the raw id.
const kMaterialNamesVi = <String, String>{
  'manh-ngoc': 'Mảnh Ngọc',
  'giot-muc': 'Giọt Mực',
};

/// Pretty display names for item ids: shop catalog first (backend → Hive
/// cache, offline-safe — same source Balo uses), then material names.
final itemDisplayNamesProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final catalog =
      ref.watch(shopCatalogProvider).valueOrNull ?? const <ShopItem>[];
  return {
    for (final s in catalog)
      if (s.nameVi.isNotEmpty) s.id: s.nameVi,
    ...kMaterialNamesVi,
  };
});

/// Inline chips summarizing a [RewardBundle] (coins, gems, item grants).
class RewardChips extends ConsumerWidget {
  final RewardBundle reward;
  final bool large;

  const RewardChips({super.key, required this.reward, this.large = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reward payloads only carry ids ("hint_pack_5") — show catalog names.
    final names = ref.watch(itemDisplayNamesProvider);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (reward.coins > 0)
          CChessCurrencyDisplay(amount: reward.coins, large: large),
        if (reward.gems > 0)
          CChessCurrencyDisplay(
            amount: reward.gems,
            currency: CChessCurrency.gem,
            large: large,
          ),
        for (final item in reward.items)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.tertiary.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              '${item.qty}× ${names[item.itemId] ?? item.itemId}',
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.tertiary,
              ),
            ),
          ),
      ],
    );
  }
}

/// Snackbar for a successful claim: "Đã nhận: +88 xu, +2 ngọc…". ("xu" is the
/// coin label everywhere — the shop, wallet and check-in all say xu.)
void showRewardSnack(BuildContext context, RewardBundle reward) {
  final parts = <String>[
    if (reward.coins > 0) '+${reward.coins} xu',
    if (reward.gems > 0) '+${reward.gems} ngọc',
    for (final item in reward.items) '+${item.qty} vật phẩm',
  ];
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        parts.isEmpty ? 'Đã nhận quà!' : 'Đã nhận: ${parts.join(', ')}',
      ),
      backgroundColor: AppColors.tealSuccess,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Snackbar for a failed economy call, mapping the common backend codes to
/// friendly Vietnamese.
void showEconomyError(BuildContext context, Object error) {
  String message = 'Có lỗi xảy ra, thử lại sau.';
  if (error is EconomyApiException) {
    message = switch (error.code) {
      'already-claimed' => 'Bạn đã nhận phần quà này rồi.',
      'already-checked-in' => 'Hôm nay bạn đã điểm danh rồi.',
      'not-available' => 'Phần quà này chưa mở.',
      'insufficient-funds' => 'Không đủ xu để thực hiện.',
      'missing-ingredients' => 'Chưa đủ nguyên liệu.',
      'already-owned' => 'Bạn đã sở hữu vật phẩm này.',
      'missing-token' => 'Cần đăng nhập để dùng tính năng này.',
      'offline' => 'Không thể thực hiện khi ngoại tuyến.',
      _ => error.isNetworkError ? 'Mất kết nối máy chủ.' : error.message,
    };
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppColors.vermilionRed,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Standard centered message body (empty state / load error) matching the
/// shop screens.
class EconomyMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onRetry;

  const EconomyMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.onSurfaceVariant),
            AppSpacing.vGapMd,
            Text(title, style: AppTextStyles.headingMd),
            AppSpacing.vGapXs,
            Text(
              detail,
              textAlign: TextAlign.center,
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            if (onRetry != null) ...[
              AppSpacing.vGapMd,
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
