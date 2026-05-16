import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

enum CChessButtonVariant {
  /// Filled gold gradient — main CTA.
  primary,

  /// Vermilion red — destructive / hot CTA (e.g. "Thử Ngay").
  danger,

  /// Outlined wood — secondary action.
  outline,

  /// Plain text button — tertiary action.
  ghost,
}

class CChessButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final CChessButtonVariant variant;
  final IconData? icon;
  final bool fullWidth;
  final double? height;
  final EdgeInsetsGeometry? padding;

  const CChessButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = CChessButtonVariant.primary,
    this.icon,
    this.fullWidth = false,
    this.height,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    Gradient? gradient;
    Color? bg;
    Color fg = AppColors.onPrimary;
    BoxBorder? border;

    switch (variant) {
      case CChessButtonVariant.primary:
        gradient = AppColors.goldButtonGradient;
        fg = AppColors.onPrimary;
        break;
      case CChessButtonVariant.danger:
        gradient = AppColors.redButtonGradient;
        fg = Colors.white;
        break;
      case CChessButtonVariant.outline:
        bg = Colors.transparent;
        fg = AppColors.primary;
        border = Border.all(color: AppColors.outline, width: 1);
        break;
      case CChessButtonVariant.ghost:
        bg = Colors.transparent;
        fg = AppColors.accentGold;
        break;
    }

    final child = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, color: fg, size: 18),
          AppSpacing.hGapSm,
        ],
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.buttonText.copyWith(color: fg),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    final decoration = BoxDecoration(
      color: enabled ? bg : AppColors.surfaceContainerHigh,
      gradient: enabled ? gradient : null,
      borderRadius: AppRadius.button,
      border: border,
      boxShadow: enabled && gradient != null
          ? const [
              BoxShadow(
                color: AppColors.shadowBrown,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ]
          : null,
    );

    final inner = Material(
      color: Colors.transparent,
      borderRadius: AppRadius.button,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          borderRadius: AppRadius.button,
          onTap: enabled ? onPressed : null,
          splashColor: AppColors.accentGold.withValues(alpha: 0.2),
          child: Container(
            constraints: BoxConstraints(minHeight: height ?? 44),
            padding: padding ??
                const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
            alignment: Alignment.center,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 120),
              style: AppTextStyles.buttonText.copyWith(
                color: enabled ? fg : AppColors.onSurfaceVariant,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: inner);
    }
    return inner;
  }
}
