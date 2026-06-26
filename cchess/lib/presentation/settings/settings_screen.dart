import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/google_auth_service.dart';
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
                _SectionLabel('Tài khoản'),
                const _AccountSection(),
                if (kDebugMode) ...[
                  AppSpacing.vGapLg,
                  _SectionLabel('Cloud (Debug)'),
                  _SettingsCard(
                    children: [
                      _RowItem(
                        icon: Icons.cloud_outlined,
                        label: 'Kiểm tra kết nối Firebase',
                        onTap: () => context.push(AppConstants.routeCloudTest),
                      ),
                      _Divider(),
                      _RowItem(
                        icon: Icons.cable,
                        label: 'Backend WebSocket test',
                        onTap: () => context.push(AppConstants.routeBackendTest),
                      ),
                    ],
                  ),
                ],
                if (AppConstants.calibrationEnabled) ...[
                  AppSpacing.vGapLg,
                  _SectionLabel('Bot Calibration'),
                  _SettingsCard(
                    children: [
                      _RowItem(
                        icon: Icons.tune,
                        label: 'ELO Calibration (Zone A)',
                        onTap: () =>
                            context.push(AppConstants.routeCalibration),
                      ),
                    ],
                  ),
                ],
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
                    _Divider(),
                    _RowItem(
                      icon: Icons.memory_outlined,
                      label: 'Engine cờ & giấy phép',
                      onTap: () => _showEngineAttribution(context),
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

/// Attribution required by the Pikafish GPL-3.0 license (engine runs
/// server-side only — it is never bundled into this app binary).
void _showEngineAttribution(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text(
        'Engine cờ & giấy phép',
        style: AppTextStyles.bodyMd.copyWith(
          color: AppColors.accentGold,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          'CChess dùng hai engine cờ tướng:\n\n'
          '• Engine offline (chơi bot, gợi ý khi mất mạng): minimax thuần '
          'Dart do nhóm CChess tự phát triển, chạy ngay trên thiết bị.\n\n'
          '• Engine phân tích mạnh (Đại Sư+, gợi ý, phân tích ván): '
          'Pikafish — engine cờ tướng mã nguồn mở theo giấy phép GPL-3.0, '
          'thuộc dự án official-pikafish/Pikafish trên GitHub. Pikafish chạy '
          'trên máy chủ của CChess, KHÔNG được đóng gói trong ứng dụng này.\n\n'
          '• Mạng NNUE (pikafish.nnue) thuộc official-pikafish/Networks và '
          'có điều khoản riêng về sử dụng thương mại.\n\n'
          'Nguồn: github.com/official-pikafish/Pikafish',
          style: AppTextStyles.captionSm.copyWith(
            color: AppColors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Đóng',
            style: AppTextStyles.bodyMd.copyWith(color: AppColors.accentGold),
          ),
        ),
      ],
    ),
  );
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

class _AccountSection extends ConsumerStatefulWidget {
  const _AccountSection();

  @override
  ConsumerState<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<_AccountSection> {
  bool _busy = false;
  String? _error;
  bool _credentialInUse = false;

  String _humanReadableAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'credential-already-in-use':
      case 'email-already-in-use':
        return 'Tài khoản Google này đã thuộc về người dùng khác. '
            'Đăng xuất rồi đăng nhập lại nếu muốn dùng tài khoản đó '
            '(dữ liệu ẩn danh hiện tại sẽ bị bỏ).';
      case 'no-id-token':
        return 'Không lấy được ID token từ Google. Thử lại.';
      case 'network-request-failed':
        return 'Mất kết nối mạng.';
      default:
        return '${e.code}: ${e.message ?? "lỗi không rõ"}';
    }
  }

  Future<void> _linkGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
      _credentialInUse = false;
    });
    try {
      await ref.read(googleAuthServiceProvider).linkAnonymousWithGoogle();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _error = _humanReadableAuthError(e);
          _credentialInUse =
              e.code == 'credential-already-in-use' || e.code == 'email-already-in-use';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forceSignInGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(googleAuthServiceProvider).signInWithGoogle();
      setState(() => _credentialInUse = false);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(googleAuthServiceProvider).signOutGoogle();
      await FirebaseAuth.instance.signOut();
      if (mounted) context.go(AppConstants.routeSplash);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          return _SettingsCard(
            children: [
              _RowItem(
                icon: Icons.cloud_off_outlined,
                label: 'Chưa đăng nhập',
              ),
            ],
          );
        }
        final isAnon = user.isAnonymous;
        return _SettingsCard(
          children: [
            _RowItem(
              icon: isAnon ? Icons.person_outline : Icons.verified_user_outlined,
              label: isAnon
                  ? 'Đăng nhập ẩn danh'
                  : (user.displayName ?? user.email ?? 'Tài khoản Google'),
              trailing: isAnon ? null : user.email,
            ),
            _Divider(),
            if (isAnon)
              _RowItem(
                icon: Icons.link,
                label: _busy ? 'Đang liên kết...' : 'Liên kết với Google',
                onTap: _busy ? null : _linkGoogle,
              )
            else
              _RowItem(
                icon: Icons.logout,
                label: _busy ? 'Đang đăng xuất...' : 'Đăng xuất',
                onTap: _busy ? null : _signOut,
              ),
            if (_credentialInUse) ...[
              _Divider(),
              _RowItem(
                icon: Icons.swap_horiz,
                label: 'Đăng nhập Google (bỏ data ẩn danh)',
                onTap: _busy ? null : _forceSignInGoogle,
              ),
            ],
            if (_error != null) ...[
              _Divider(),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.base),
                child: Text(
                  _error!,
                  style: AppTextStyles.captionSm.copyWith(
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
