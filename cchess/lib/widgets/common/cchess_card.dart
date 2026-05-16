import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Standard CChess card surface — wood-toned container with optional outline,
/// border-radius xl and subtle drop shadow.
class CChessCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final double borderWidth;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final List<BoxShadow>? boxShadow;
  final Gradient? gradient;

  const CChessCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.paddingCard,
    this.color,
    this.borderColor,
    this.borderWidth = 1,
    this.onTap,
    this.borderRadius = AppRadius.card,
    this.boxShadow,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final shape = BoxDecoration(
      color: gradient == null ? (color ?? AppColors.surfaceContainer) : null,
      gradient: gradient,
      borderRadius: borderRadius,
      border: Border.all(
        color: borderColor ?? AppColors.outlineVariant,
        width: borderWidth,
      ),
      boxShadow: boxShadow ??
          const [
            BoxShadow(
              color: AppColors.shadowBrown,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
    );

    final content = Padding(padding: padding, child: child);

    if (onTap == null) {
      return DecoratedBox(decoration: shape, child: content);
    }
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: Ink(
        decoration: shape,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          splashColor: AppColors.accentGold.withValues(alpha: 0.15),
          highlightColor: AppColors.accentGold.withValues(alpha: 0.05),
          child: content,
        ),
      ),
    );
  }
}
