import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import '../profile/profile_controller.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameCtrl = TextEditingController();
  String _region = 'Hà Nội';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final t = value.trim();
    if (t.isEmpty) return 'Vui lòng nhập tên kỳ thủ.';
    if (t.length < 2) return 'Tên ít nhất 2 ký tự.';
    if (t.length > 24) return 'Tên tối đa 24 ký tự.';
    return null;
  }

  Future<void> _finish() async {
    final err = _validate(_nameCtrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final controller = ref.read(profileControllerProvider.notifier);
    await controller.completeOnboarding(
      displayName: _nameCtrl.text.trim(),
      region: _region,
    );
    if (!mounted) return;
    context.go(AppConstants.routeHome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSpacing.vGapXl,
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.goldButtonGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentGold.withValues(alpha: 0.3),
                        blurRadius: 24,
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '楚',
                    style: AppTextStyles.pieceText(AppColors.inkBlack, 56),
                  ),
                ),
              ),
              AppSpacing.vGapLg,
              Text(
                'Chào mừng đến CChess',
                style: AppTextStyles.titleLg,
                textAlign: TextAlign.center,
              ),
              AppSpacing.vGapXs,
              Text(
                'Cờ tướng Việt Nam — học, luyện, thi đấu.\n'
                'Hãy thiết lập hồ sơ để bắt đầu.',
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              AppSpacing.vGapXl,
              CChessCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tên hiển thị',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.vGapXs,
                    TextField(
                      controller: _nameCtrl,
                      maxLength: 24,
                      decoration: InputDecoration(
                        hintText: 'Ví dụ: Kỳ Vương Việt',
                        prefixIcon: const Icon(Icons.person_outline),
                        errorText: _error,
                      ),
                      onChanged: (v) {
                        if (_error != null) {
                          setState(() => _error = _validate(v));
                        }
                      },
                      onSubmitted: (_) => _finish(),
                    ),
                    AppSpacing.vGapMd,
                    Text(
                      'Khu vực',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.vGapXs,
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerHigh,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: AppColors.outlineVariant),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          canvasColor: AppColors.surfaceContainerHigh,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _region,
                            isExpanded: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.base,
                              vertical: AppSpacing.xs,
                            ),
                            icon: const Icon(Icons.expand_more,
                                color: AppColors.parchmentTan),
                            style: AppTextStyles.bodyMd,
                            items: [
                              for (final r in kVietnamRegions)
                                DropdownMenuItem(value: r, child: Text(r)),
                            ],
                            onChanged: (v) =>
                                setState(() => _region = v ?? 'Hà Nội'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              CChessButton(
                label: _saving ? 'Đang lưu…' : 'Bắt đầu',
                icon: Icons.arrow_forward,
                fullWidth: true,
                onPressed: _saving ? null : _finish,
              ),
              AppSpacing.vGapSm,
              Center(
                child: Text(
                  'Bạn có thể đổi tên / khu vực sau trong Hồ Sơ.',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                  ),
                ),
              ),
              AppSpacing.vGapSm,
            ],
          ),
        ),
      ),
    );
  }
}
