import 'package:flutter/material.dart';

import '../../core/constants/elo_constants.dart';
import '../../theme/app_colors.dart';

/// Circular avatar with an optional rank-colored ring.
class CChessAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? initials;
  final double size;
  final int? elo;
  final Color? ringColor;
  final double ringWidth;
  final IconData fallbackIcon;

  const CChessAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.size = 48,
    this.elo,
    this.ringColor,
    this.ringWidth = 2,
    this.fallbackIcon = Icons.person,
  });

  @override
  Widget build(BuildContext context) {
    final Color border = ringColor ??
        (elo != null
            ? EloConstants.rankForElo(elo!).color
            : AppColors.accentGold);

    Widget inner;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      inner = ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallback(size),
        ),
      );
    } else if (initials != null && initials!.isNotEmpty) {
      inner = Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.woodLight,
          shape: BoxShape.circle,
        ),
        child: Text(
          initials!.substring(0, initials!.length > 2 ? 2 : initials!.length)
              .toUpperCase(),
          style: TextStyle(
            color: AppColors.woodDark,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.4,
          ),
        ),
      );
    } else {
      inner = _fallback(size);
    }

    return Container(
      width: size + ringWidth * 2,
      height: size + ringWidth * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: border, width: ringWidth),
      ),
      padding: EdgeInsets.all(ringWidth),
      child: inner,
    );
  }

  Widget _fallback(double s) => Container(
        width: s,
        height: s,
        decoration: const BoxDecoration(
          color: AppColors.woodLight,
          shape: BoxShape.circle,
        ),
        child: Icon(
          fallbackIcon,
          color: AppColors.woodDark,
          size: s * 0.55,
        ),
      );
}
