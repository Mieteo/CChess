import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/datasources/remote/clubs_api_source.dart';
import '../../data/models/community_models.dart';
import '../../data/repositories/club_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'community_widgets.dart';

class ClubDetailScreen extends ConsumerStatefulWidget {
  const ClubDetailScreen({super.key, required this.clubId});

  final String clubId;

  @override
  ConsumerState<ClubDetailScreen> createState() => _ClubDetailScreenState();
}

class _ClubDetailScreenState extends ConsumerState<ClubDetailScreen> {
  late Future<_ClubDetail> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ClubDetail> _load() async {
    final source = ref.read(clubsApiSourceProvider);
    final club = await source.getClub(widget.clubId);
    if (club == null) return const _ClubDetail(club: null, members: []);
    final members = await source.listMembers(widget.clubId);
    List<MyClubEntry> mine = const [];
    try {
      mine = await source.listMine();
    } on ClubApiException {
      // not signed in / offline — membership state just stays unresolved
    }
    final isMember = mine.any((m) => m.clubId == widget.clubId);
    return _ClubDetail(club: club.copyWith(isMember: isMember), members: members);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _toggleMembership(CommunityClub club) async {
    setState(() => _busy = true);
    try {
      if (club.isMember) {
        await ref.read(clubRepositoryProvider).leave(club.id);
        _showSnack('Đã rời ${club.name}');
      } else {
        await ref.read(clubRepositoryProvider).join(club.id);
        _showSnack('Đã tham gia ${club.name}');
      }
      _reload();
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
      case 'owner-cannot-leave':
        return 'Người sáng lập không thể rời khi Kỳ Xã còn thành viên khác';
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
        Row(
          children: [
            IconButton(
              tooltip: 'Quay lại',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back, color: AppColors.accentGold),
            ),
          ],
        ),
        AppSpacing.vGapMd,
        FutureBuilder<_ClubDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: BrushStrokeSpinner());
            }
            final detail = snapshot.data!;
            final club = detail.club;
            if (club == null) {
              return const CommunityEmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'Không tìm thấy Kỳ Xã',
                message: 'Kỳ Xã này có thể đã bị xóa.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(club.name, style: AppTextStyles.titleLg),
                AppSpacing.vGapXs,
                Text(
                  club.region,
                  style: AppTextStyles.captionSm.copyWith(color: AppColors.parchmentTan),
                ),
                AppSpacing.vGapMd,
                Text(
                  club.description.isEmpty ? 'Chưa có mô tả.' : club.description,
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                AppSpacing.vGapLg,
                Row(
                  children: [
                    Expanded(
                      child: CommunityMetricChip(
                        icon: Icons.people_outline,
                        label: 'Thành viên',
                        value: '${club.memberCount}',
                        color: AppColors.tertiary,
                      ),
                    ),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: CommunityMetricChip(
                        icon: Icons.stacked_line_chart,
                        label: 'Điểm tuần (Bảng điểm CLB)',
                        value: '${club.weeklyScore}',
                      ),
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                CChessButton(
                  label: club.isMember ? 'Rời Kỳ Xã' : 'Tham gia Kỳ Xã',
                  icon: club.isMember ? Icons.logout : Icons.group_add_outlined,
                  variant: club.isMember ? CChessButtonVariant.outline : CChessButtonVariant.primary,
                  fullWidth: true,
                  onPressed: _busy ? null : () => _toggleMembership(club),
                ),
                AppSpacing.vGapLg,
                Text('Thành viên', style: AppTextStyles.headingMd),
                AppSpacing.vGapMd,
                for (final member in detail.members) ...[
                  _MemberRow(member: member),
                  AppSpacing.vGapSm,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ClubDetail {
  const _ClubDetail({required this.club, required this.members});
  final CommunityClub? club;
  final List<ClubMember> members;
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final ClubMember member;

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CChessAvatar(
            initials: member.displayName.isEmpty ? '?' : member.displayName.substring(0, 1).toUpperCase(),
            size: 40,
            elo: member.eloChess,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.displayName, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  'ELO ${member.eloChess}',
                  style: AppTextStyles.captionSm.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (member.role == ClubRole.owner)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                member.role.label,
                style: AppTextStyles.captionSm.copyWith(color: AppColors.accentGold, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
