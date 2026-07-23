import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
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
          // Pushed from the shell's gear button → pop back to whichever tab
          // the user was on; entered via `go` (profile menu) → fall back.
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppConstants.routeProfile);
            }
          },
        ),
      ),
      body: asyncSettings.when(
        loading: () => const Center(child: BrushStrokeSpinner()),
        error: (e, _) =>
            Center(child: Text('Lỗi: $e', style: AppTextStyles.bodyMd)),
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
                _SectionLabel('AI Offline'),
                const _PikafishSection(),
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
                        onTap: () =>
                            context.push(AppConstants.routeBackendTest),
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
                      onTap: () => _showInfoDialog(
                        context,
                        title: 'Chính sách dữ liệu',
                        body:
                            '• CChess tạo một tài khoản ẩn danh (Firebase) để '
                            'lưu hồ sơ, ELO, vật phẩm và lịch sử đấu của bạn '
                            'trên máy chủ.\n\n'
                            '• Dữ liệu chỉ dùng để vận hành trò chơi: ghép '
                            'trận, bảng xếp hạng và đồng bộ giữa các thiết '
                            'bị. Không bán hay chia sẻ cho bên thứ ba.\n\n'
                            '• Liên kết Google là tùy chọn, chỉ nhằm khôi '
                            'phục tài khoản khi đổi máy.\n\n'
                            'Bản chính sách đầy đủ sẽ được công bố trước khi '
                            'phát hành chính thức.',
                      ),
                    ),
                    _Divider(),
                    _RowItem(
                      icon: Icons.gavel_outlined,
                      label: 'Điều khoản sử dụng',
                      onTap: () => _showInfoDialog(
                        context,
                        title: 'Điều khoản sử dụng',
                        body:
                            '• Không gian lận trong các ván xếp hạng (ví dụ '
                            'dùng engine ngoài) và không phá hoại trải '
                            'nghiệm của người chơi khác.\n\n'
                            '• Tên hiển thị không được xúc phạm hoặc mạo '
                            'danh người khác.\n\n'
                            '• Vật phẩm và tiền tệ trong game không có giá '
                            'trị quy đổi bên ngoài trò chơi.\n\n'
                            'Bản điều khoản đầy đủ sẽ được công bố trước khi '
                            'phát hành chính thức.',
                      ),
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

/// Simple titled info dialog for the policy/terms summaries (full legal text
/// ships with the store release).
void _showInfoDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surfaceContainerLow,
      title: Text(
        title,
        style: AppTextStyles.bodyMd.copyWith(
          color: AppColors.accentGold,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          body,
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

/// Attribution required by the Pikafish GPL-3.0 license. The Pikafish binary
/// is bundled unmodified and runs as a SEPARATE child process (not linked
/// into the app); the NNUE network is downloaded separately.
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
          'CChess dùng các engine cờ tướng sau:\n\n'
          '• Engine bot cơ bản: minimax thuần Dart do nhóm CChess tự phát '
          'triển, chạy ngay trên thiết bị.\n\n'
          '• Engine phân tích mạnh (Đại Sư+, gợi ý, phân tích ván): '
          'Pikafish — engine cờ tướng mã nguồn mở theo giấy phép GPL-3.0, '
          'thuộc dự án official-pikafish/Pikafish trên GitHub. Pikafish chạy '
          'trên máy chủ của CChess, và bản chính thức không sửa đổi cũng '
          'được đóng gói kèm ứng dụng cho tính năng AI Offline — chạy như '
          'một tiến trình độc lập, tách biệt với mã của ứng dụng.\n\n'
          '• Mạng NNUE (pikafish.nnue, tải riêng khi bật AI Offline) thuộc '
          'official-pikafish/Networks và có điều khoản riêng về sử dụng '
          'thương mại.\n\n'
          'Mã nguồn Pikafish: github.com/official-pikafish/Pikafish',
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

/// "AI Offline" — install/remove the on-device Pikafish engine.
///
/// The ~50MB NNUE network downloads once; afterwards hints and game analysis
/// keep full engine strength with no server, no quota, and no network.
class _PikafishSection extends ConsumerStatefulWidget {
  const _PikafishSection();

  @override
  ConsumerState<_PikafishSection> createState() => _PikafishSectionState();
}

class _PikafishSectionState extends ConsumerState<_PikafishSection> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await for (final p in ref.read(pikafishInstallerProvider).download()) {
        if (!mounted) return;
        setState(() => _progress = p);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = 'Tải thất bại — kiểm tra mạng rồi thử lại. ($e)',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
        ref.invalidate(pikafishInstallStatusProvider);
      }
    }
  }

  Future<void> _delete() async {
    await ref.read(pikafishInstallerProvider).delete();
    if (mounted) ref.invalidate(pikafishInstallStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final statusAsync = ref.watch(pikafishInstallStatusProvider);
    return _SettingsCard(
      children: [
        statusAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.base),
            child: Center(child: BrushStrokeSpinner(size: 20)),
          ),
          error: (e, _) => _RowItem(
            icon: Icons.error_outline,
            label: 'Không đọc được trạng thái engine',
          ),
          data: (status) => _buildBody(status),
        ),
        if (_error != null) ...[
          _Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.base),
            child: Text(
              _error!,
              style: AppTextStyles.captionSm.copyWith(color: Colors.redAccent),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBody(PikafishInstallStatus status) {
    if (!status.platformSupported || !status.binaryAvailable) {
      return _RowItem(
        icon: Icons.smart_toy_outlined,
        label: 'Pikafish Offline',
        trailing: 'Thiết bị chưa hỗ trợ',
      );
    }

    if (_downloading) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đang tải bộ đánh giá NNUE… ${(_progress * 100).round()}%',
              style: AppTextStyles.bodyMd,
            ),
            AppSpacing.vGapSm,
            LinearProgressIndicator(
              value: _progress,
              color: AppColors.accentGold,
              backgroundColor: AppColors.surfaceContainerHigh,
            ),
          ],
        ),
      );
    }

    if (status.nnueInstalled) {
      final sizeMb = ((status.nnueSizeBytes ?? 0) / (1024 * 1024))
          .toStringAsFixed(0);
      return Column(
        children: [
          _RowItem(
            icon: Icons.smart_toy,
            label: 'Pikafish Offline — đã bật',
            trailing: '$sizeMb MB',
          ),
          _Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.xs,
              AppSpacing.base,
              AppSpacing.sm,
            ),
            child: Text(
              'Gợi ý & phân tích ván dùng engine mạnh ngay trên máy khi '
              'không có mạng hoặc máy chủ bận.',
              style: AppTextStyles.captionSm.copyWith(
                color: AppColors.parchmentTan,
              ),
            ),
          ),
          _Divider(),
          _RowItem(
            icon: Icons.delete_outline,
            label: 'Gỡ bộ đánh giá (giải phóng dung lượng)',
            onTap: _delete,
          ),
        ],
      );
    }

    return Column(
      children: [
        _RowItem(
          icon: Icons.download_outlined,
          label: 'Bật Pikafish Offline (tải ~51 MB)',
          onTap: _download,
        ),
        _Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.base,
            AppSpacing.xs,
            AppSpacing.base,
            AppSpacing.sm,
          ),
          child: Text(
            'Tải một lần bộ đánh giá NNUE để gợi ý và phân tích ván bằng '
            'engine Pikafish ngay trên máy — hoạt động cả khi mất mạng.',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
        ),
      ],
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
              e.code == 'credential-already-in-use' ||
              e.code == 'email-already-in-use';
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
              _RowItem(icon: Icons.cloud_off_outlined, label: 'Chưa đăng nhập'),
            ],
          );
        }
        final isAnon = user.isAnonymous;
        return _SettingsCard(
          children: [
            _RowItem(
              icon: isAnon
                  ? Icons.person_outline
                  : Icons.verified_user_outlined,
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
