import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Custom top app bar: avatar (left), calligraphy title (center), settings (right).
class CChessAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final int notificationCount;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onSettingsTap;

  const CChessAppBar({
    super.key,
    this.title,
    this.notificationCount = 0,
    this.onAvatarTap,
    this.onNotificationTap,
    this.onSettingsTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.appBarGradient,
        border: Border(
          bottom: BorderSide(color: AppColors.outlineVariant, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowBrown,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Row(
              children: [
                _CircleIconButton(
                  icon: Icons.person_outline,
                  background: AppColors.woodLight,
                  iconColor: AppColors.woodDark,
                  borderColor: AppColors.accentGold,
                  onTap: onAvatarTap,
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: Text(
                    title ?? AppConstants.appNameVi,
                    style: AppTextStyles.displayCalligraphy.copyWith(
                      fontSize: 22,
                      height: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                AppSpacing.hGapMd,
                _NotificationButton(
                  count: notificationCount,
                  onTap: onNotificationTap,
                ),
                AppSpacing.hGapSm,
                _CircleIconButton(
                  icon: Icons.settings_outlined,
                  background: AppColors.surfaceContainerHigh,
                  iconColor: AppColors.primary,
                  borderColor: AppColors.outlineVariant,
                  onTap: onSettingsTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color iconColor;
  final Color borderColor;
  final VoidCallback? onTap;
  final double size;

  const _CircleIconButton({
    required this.icon,
    required this.background,
    required this.iconColor,
    required this.borderColor,
    this.onTap,
    // ignore: unused_element_parameter
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: background,
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;

  const _NotificationButton({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _CircleIconButton(
          icon: Icons.notifications_outlined,
          background: AppColors.surfaceContainerHigh,
          iconColor: AppColors.primary,
          borderColor: AppColors.outlineVariant,
          onTap: onTap,
        ),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.vermilionRed,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.woodDark, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
