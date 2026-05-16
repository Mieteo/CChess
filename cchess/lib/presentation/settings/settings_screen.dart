import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Cài Đặt'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeProfile),
        ),
      ),
      body: asyncSettings.when(
        loading: () => const Center(child: BrushStrokeSpinner()),
        error: (e, _) => Center(
          child: Text('Lỗi: $e', style: AppTextStyles.bodyMd),
        ),
        data: (settings) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.base),
              children: [
                _SectionLabel('Âm thanh & Rung'),
                _SettingsCard(
                  children: [
                    _ToggleRow(
                      icon: Icons.volume_up,
                      label: 'Âm hiệu trong ván',
                      value: settings.soundEnabled,
                      onChanged: controller.setSound,
                    ),
                    _Divider(),
                    _ToggleRow(
                      icon: Icons.music_note,
                      label: 'Nhạc nền',
                      value: settings.musicEnabled,
                      onChanged: controller.setMusic,
                    ),
                    _Divider(),
                    _ToggleRow(
                      icon: Icons.vibration,
                      label: 'Rung khi đi quân',
                      value: settings.vibrationEnabled,
                      onChanged: controller.setVibration,
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                _SectionLabel('Hiển thị ván cờ'),
                _SettingsCard(
                  children: [
                    _ToggleRow(
                      icon: Icons.adjust,
                      label: 'Hiện chấm gợi ý nước đi',
                      value: settings.showLegalMoveDots,
                      onChanged: controller.setShowDots,
                    ),
                    _Divider(),
                    _ToggleRow(
                      icon: Icons.flip_camera_android,
                      label: 'Xoay bàn mặc định (đen ở dưới)',
                      value: settings.defaultBoardFlipped,
                      onChanged: controller.setFlipDefault,
                    ),
                    _Divider(),
                    _ToggleRow(
                      icon: Icons.dark_mode_outlined,
                      label: 'Chế độ tối',
                      value: settings.darkMode,
                      onChanged: controller.setDarkMode,
                      disabled: true,
                      disabledHint: 'Bắt buộc — light mode đang hoàn thiện',
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                _SectionLabel('Luyện tập'),
                _SettingsCard(
                  children: [
                    _SliderRow(
                      icon: Icons.lightbulb_outline,
                      label: 'Số lần gợi ý mỗi ngày',
                      value: settings.dailyHintsLimit.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      suffix: '${settings.dailyHintsLimit}',
                      onChanged: (v) => controller.setHintLimit(v.round()),
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                _SectionLabel('Sức khoẻ'),
                _SettingsCard(
                  children: [
                    _SliderRow(
                      icon: Icons.health_and_safety_outlined,
                      label: 'Giới hạn thời gian chơi / ngày',
                      value: settings.healthyGamingMinutes.toDouble(),
                      min: 0,
                      max: 240,
                      divisions: 12,
                      suffix: settings.healthyGamingMinutes == 0
                          ? 'không giới hạn'
                          : '${settings.healthyGamingMinutes} phút',
                      onChanged: (v) => controller.setHealthyMinutes(v.round()),
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                _SectionLabel('Giới thiệu'),
                _SettingsCard(
                  children: [
                    _RowItem(
                      icon: Icons.info_outline,
                      label: 'Phiên bản',
                      trailing: AppConstants.appVersion,
                    ),
                    _Divider(),
                    _RowItem(
                      icon: Icons.privacy_tip_outlined,
                      label: 'Chính sách dữ liệu',
                      onTap: () {},
                    ),
                    _Divider(),
                    _RowItem(
                      icon: Icons.gavel_outlined,
                      label: 'Điều khoản sử dụng',
                      onTap: () {},
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                Center(
                  child: Text(
                    '${AppConstants.appNameVi} ${AppConstants.appVersion}',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.parchmentTan,
                    ),
                  ),
                ),
                AppSpacing.vGapLg,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xs,
        bottom: AppSpacing.sm,
        top: AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.captionSm.copyWith(
          color: AppColors.accentGold,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, color: AppColors.outlineVariant);
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool disabled;
  final String? disabledHint;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.disabled = false,
    this.disabledHint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: disabled ? AppColors.parchmentTan : AppColors.primary,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: disabled
                        ? AppColors.onSurfaceVariant
                        : AppColors.onSurface,
                  ),
                ),
                if (disabled && disabledHint != null)
                  Text(
                    disabledHint!,
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.parchmentTan,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: disabled ? null : onChanged,
            activeThumbColor: AppColors.accentGold,
            activeTrackColor: AppColors.accentGold.withValues(alpha: 0.4),
            inactiveThumbColor: AppColors.parchmentTan,
            inactiveTrackColor: AppColors.surfaceContainerHigh,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.sm,
        AppSpacing.base,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary),
              AppSpacing.hGapMd,
              Expanded(child: Text(label, style: AppTextStyles.bodyMd)),
              Text(
                suffix,
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.accentGold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.accentGold,
              inactiveTrackColor: AppColors.surfaceContainerHigh,
              thumbColor: AppColors.accentGold,
              overlayColor: AppColors.accentGold.withValues(alpha: 0.15),
              valueIndicatorColor: AppColors.surfaceContainerHigh,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;

  const _RowItem({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            AppSpacing.hGapMd,
            Expanded(child: Text(label, style: AppTextStyles.bodyMd)),
            if (trailing != null)
              Text(
                trailing!,
                style: AppTextStyles.captionSm.copyWith(
                  color: AppColors.parchmentTan,
                ),
              ),
            if (onTap != null) ...[
              AppSpacing.hGapSm,
              const Icon(
                Icons.chevron_right,
                color: AppColors.parchmentTan,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
