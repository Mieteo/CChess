import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import 'cchess_button.dart';

/// Modal styled like a scroll/parchment panel. Use for confirmations,
/// game-result overlays, etc.
class CChessDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  final IconData? leadingIcon;
  final Color? leadingIconColor;

  const CChessDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions = const [],
    this.leadingIcon,
    this.leadingIconColor,
  });

  /// Convenience: show a yes/no confirmation. Returns true if confirmed.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Đồng ý',
    String cancelLabel = 'Hủy',
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => CChessDialog(
        title: title,
        leadingIcon: icon,
        content: Text(message, style: AppTextStyles.bodyMd),
        actions: [
          CChessButton(
            label: cancelLabel,
            variant: CChessButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppSpacing.hGapMd,
          CChessButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: AppRadius.dialog,
          border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.4)),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadowBrown,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(
                    leadingIcon,
                    color: leadingIconColor ?? AppColors.accentGold,
                    size: 28,
                  ),
                  AppSpacing.hGapMd,
                ],
                Expanded(
                  child: Text(title, style: AppTextStyles.titleLg),
                ),
              ],
            ),
            AppSpacing.vGapMd,
            content,
            if (actions.isNotEmpty) ...[
              AppSpacing.vGapLg,
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
