import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../data/datasources/remote/clubs_api_source.dart';
import '../../data/models/community_models.dart';
import '../../data/repositories/club_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'community_widgets.dart';

class ClubsScreen extends ConsumerStatefulWidget {
  const ClubsScreen({super.key});

  @override
  ConsumerState<ClubsScreen> createState() => _ClubsScreenState();
}

class _ClubsScreenState extends ConsumerState<ClubsScreen> {
  late Future<List<CommunityClub>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(clubRepositoryProvider).listClubs();
  }

  void _reload() {
    setState(() => _future = ref.read(clubRepositoryProvider).listClubs());
  }

  Future<void> _createClub() async {
    final nameCtrl = TextEditingController();
    final regionCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => CChessDialog(
        title: 'Tạo Kỳ Xã mới',
        leadingIcon: Icons.workspace_premium_outlined,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              maxLength: 60,
              decoration: const InputDecoration(labelText: 'Tên Kỳ Xã'),
            ),
            TextField(
              controller: regionCtrl,
              decoration: const InputDecoration(labelText: 'Khu vực'),
            ),
            TextField(
              controller: descCtrl,
              maxLength: 280,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Mô tả (không bắt buộc)'),
            ),
          ],
        ),
        actions: [
          CChessButton(
            label: 'Hủy',
            variant: CChessButtonVariant.outline,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppSpacing.hGapMd,
          CChessButton(label: 'Tạo', onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    );
    if (created != true || !mounted) return;
    final name = nameCtrl.text.trim();
    final region = regionCtrl.text.trim();
    if (name.isEmpty || region.isEmpty) {
      _showSnack('Vui lòng nhập tên và khu vực');
      return;
    }
    await _run(() async {
      final club = await ref
          .read(clubRepositoryProvider)
          .create(name: name, region: region, description: descCtrl.text.trim());
      _reload();
      if (mounted) context.push('${AppConstants.routeCommunityClubs}/${club.id}');
    });
  }

  Future<void> _join(CommunityClub club) async {
    await _run(() async {
      await ref.read(clubRepositoryProvider).join(club.id);
      _reload();
      _showSnack('Đã tham gia ${club.name}');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ClubApiException catch (e) {
      _showSnack(_messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(ClubApiException e) {
    switch (e.code) {
      case 'club-limit-reached':
        return 'Bạn đã tham gia tối đa 3 Kỳ Xã';
      case 'already-member':
        return 'Bạn đã là thành viên của Kỳ Xã này';
      case 'missing-token':
        return 'Cần đăng nhập để dùng tính năng Kỳ Xã';
      default:
        return e.isNetworkError ? 'Không có kết nối mạng' : e.message;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.base, AppSpacing.base, AppSpacing.base, 96),
      children: [
        CommunityPageHeader(
          title: 'Kỳ Xã',
          subtitle: 'Câu lạc bộ theo địa phương, nhóm bạn và lối chơi',
          icon: Icons.workspace_premium_outlined,
          showBack: true,
          trailing: IconButton(
            tooltip: 'Tạo Kỳ Xã',
            onPressed: _busy ? null : _createClub,
            icon: const Icon(Icons.add_circle_outline, color: AppColors.accentGold),
          ),
        ),
        AppSpacing.vGapLg,
        FutureBuilder<List<CommunityClub>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: BrushStrokeSpinner());
            }
            final clubs = snapshot.data!;
            if (clubs.isEmpty) {
              return const CommunityEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'Chưa có Kỳ Xã',
                message: 'Hãy là người đầu tiên tạo một Kỳ Xã!',
              );
            }
            return Column(
              children: [
                for (final club in clubs) ...[
                  _ClubCard(
                    club: club,
                    busy: _busy,
                    onJoin: () => _join(club),
                    onTap: () => context.push('${AppConstants.routeCommunityClubs}/${club.id}'),
                  ),
                  if (club != clubs.last) AppSpacing.vGapMd,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ClubCard extends StatelessWidget {
  const _ClubCard({required this.club, required this.busy, required this.onJoin, required this.onTap});

  final CommunityClub club;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      onTap: onTap,
      borderColor: club.isMember
          ? AppColors.accentGold.withValues(alpha: 0.5)
          : AppColors.outlineVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.workspace_premium_outlined,
                  color: AppColors.accentGold,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(club.name, style: AppTextStyles.headingMd),
                    AppSpacing.vGapXs,
                    Text(
                      club.region,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.parchmentTan,
                      ),
                    ),
                  ],
                ),
              ),
              if (club.isMember)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Đã vào',
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          AppSpacing.vGapMd,
          Text(
            club.description,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: _InlineMetric(
                  icon: Icons.people_outline,
                  label: 'thành viên',
                  value: '${club.memberCount}',
                  color: AppColors.tertiary,
                ),
              ),
              AppSpacing.hGapSm,
              Expanded(
                child: _InlineMetric(
                  icon: Icons.stacked_line_chart,
                  label: 'điểm tuần',
                  value: '${club.weeklyScore}',
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: CChessButton(
                  label: club.isMember ? 'Xem Kỳ Xã' : 'Tham gia',
                  icon: club.isMember
                      ? Icons.meeting_room_outlined
                      : Icons.group_add_outlined,
                  onPressed: busy ? null : (club.isMember ? onTap : onJoin),
                ),
              ),
              AppSpacing.hGapSm,
              CChessButton(
                label: 'Bảng điểm',
                icon: Icons.leaderboard_outlined,
                variant: CChessButtonVariant.outline,
                onPressed: onTap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.headingMd.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
