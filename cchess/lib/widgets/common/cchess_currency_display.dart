import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Currency type — affects icon and color.
enum CChessCurrency { coin, gem, vipPoint }

/// Display like "🪙 2278" or "💎 1000" with consistent styling.
class CChessCurrencyDisplay extends StatelessWidget {
  final int amount;
  final CChessCurrency currency;
  final bool large;

  const CChessCurrencyDisplay({
    super.key,
    required this.amount,
    this.currency = CChessCurrency.coin,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = large ? 22.0 : 16.0;
    final textSize = large ? 16.0 : 13.0;
    final (icon, color) = switch (currency) {
      CChessCurrency.coin => (Icons.savings_outlined, AppColors.accentGold),
      CChessCurrency.gem => (Icons.diamond_outlined, AppColors.tertiary),
      CChessCurrency.vipPoint => (Icons.workspace_premium, AppColors.primary),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: large ? AppSpacing.xs : 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: AppRadius.chip,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: iconSize),
          AppSpacing.hGapXs,
          Text(
            _formatAmount(amount),
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: textSize,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAmount(int n) {
    if (n < 1000) return n.toString();
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "")}K';
    return '${(n / 1000000).toStringAsFixed(1).replaceAll(RegExp(r"\.0$"), "")}M';
  }
}
