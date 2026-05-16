import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'profile_controller.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  String? _region;
  String? _error;
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _maybeInit(UserProfile profile) {
    if (_initialized) return;
    _nameCtrl.text = profile.displayName;
    _region = profile.region;
    _initialized = true;
  }

  String? _validate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Tên không được để trống.';
    if (trimmed.length < 2) return 'Tên ít nhất 2 ký tự.';
    if (trimmed.length > 24) return 'Tên tối đa 24 ký tự.';
    return null;
  }

  Future<void> _save() async {
    final err = _validate(_nameCtrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() => _error = null);
    final controller = ref.read(profileControllerProvider.notifier);
    await controller.update((p) => p.copyWith(
          displayName: _nameCtrl.text.trim(),
          region: _region ?? p.region,
        ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã lưu hồ sơ.')),
    );
    context.go(AppConstants.routeProfile);
  }

  @override
  Widget build(BuildContext context) {
    final asyncProfile = ref.watch(profileControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: const Text('Chỉnh sửa hồ sơ'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeProfile),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Lưu',
              style: AppTextStyles.buttonText.copyWith(
                color: AppColors.accentGold,
              ),
            ),
          ),
        ],
      ),
      body: asyncProfile.when(
        loading: () => const Center(child: BrushStrokeSpinner()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (profile) {
          _maybeInit(profile);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.base),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CChessAvatar(
                      initials: profile.displayName.isEmpty
                          ? '?'
                          : profile.displayName[0],
                      size: 84,
                      elo: profile.eloChess,
                    ),
                  ),
                  AppSpacing.vGapSm,
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đổi avatar sẽ có trong Sprint Shop.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Đổi avatar'),
                    ),
                  ),
                  AppSpacing.vGapLg,
                  _FieldLabel('Tên hiển thị'),
                  TextField(
                    controller: _nameCtrl,
                    maxLength: 24,
                    decoration: InputDecoration(
                      hintText: 'Nhập tên kỳ thủ',
                      errorText: _error,
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    onChanged: (v) {
                      if (_error != null) {
                        setState(() => _error = _validate(v));
                      }
                    },
                  ),
                  AppSpacing.vGapMd,
                  _FieldLabel('Khu vực'),
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
                          value: _region ?? profile.region,
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
                          onChanged: (v) => setState(() => _region = v),
                        ),
                      ),
                    ),
                  ),
                  AppSpacing.vGapLg,
                  _FieldLabel('Thông tin tài khoản'),
                  CChessCard(
                    child: Column(
                      children: [
                        _InfoRow(label: 'ID', value: profile.shortId),
                        const Divider(
                          height: 1,
                          color: AppColors.outlineVariant,
                        ),
                        _InfoRow(
                          label: 'Ngày tham gia',
                          value:
                              '${profile.createdAt.day}/${profile.createdAt.month}/${profile.createdAt.year}',
                        ),
                        const Divider(
                          height: 1,
                          color: AppColors.outlineVariant,
                        ),
                        _InfoRow(
                          label: 'Tổng ván đã chơi',
                          value: '${profile.totalGames}',
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.vGapXl,
                  CChessButton(
                    label: 'Lưu thay đổi',
                    icon: Icons.save_outlined,
                    fullWidth: true,
                    onPressed: _save,
                  ),
                  AppSpacing.vGapLg,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs, left: AppSpacing.xs),
      child: Text(
        label,
        style: AppTextStyles.captionSm.copyWith(
          color: AppColors.parchmentTan,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
