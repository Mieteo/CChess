import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Vintage-style progress bar: dark wood track, gold gradient fill, optional
/// shine overlay. Use for daily quest progress, XP bars, hint counters, etc.
class CChessProgressBar extends StatelessWidget {
  /// Fill value in 0..1.
  final double value;
  final double height;
  final Gradient? fillGradient;
  final Color? trackColor;
  final BorderRadius? borderRadius;

  const CChessProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.fillGradient,
    this.trackColor,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    final radius = borderRadius ?? BorderRadius.circular(height);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        height: height,
        color: trackColor ?? AppColors.surfaceContainerHighest,
        child: Align(
          alignment: Alignment.centerLeft,
          child: LayoutBuilder(
            builder: (context, c) => Container(
              width: c.maxWidth * clamped,
              decoration: BoxDecoration(
                gradient: fillGradient ?? AppColors.goldButtonGradient,
                borderRadius: radius,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: radius,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
