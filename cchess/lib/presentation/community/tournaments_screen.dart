import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/community_models.dart';
import '../../data/repositories/community_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'community_widgets.dart';

class TournamentsScreen extends ConsumerWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final future = ref
        .watch(communityRepositoryProvider)
        .loadTournaments(limit: 20);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        AppSpacing.base,
        AppSpacing.base,
        96,
      ),
      children: [
        const CommunityPageHeader(
          title: 'Giải Đấu',
          subtitle: 'Lịch thi đấu định kỳ, bracket và đăng ký nhanh',
          icon: Icons.emoji_events_outlined,
          showBack: true,
        ),
        AppSpacing.vGapLg,
        FutureBuilder<List<CommunityTournament>>(
          future: future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: BrushStrokeSpinner());
            }
            final tournaments = snapshot.data!;
            if (tournaments.isEmpty) {
              return const CommunityEmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'Chưa có giải đấu',
                message: 'Các giải định kỳ của hệ thống sẽ xuất hiện tại đây.',
              );
            }
            return Column(
              children: [
                for (final tournament in tournaments) ...[
                  _TournamentCard(tournament: tournament),
                  if (tournament != tournaments.last) AppSpacing.vGapMd,
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TournamentCard extends StatelessWidget {
  const _TournamentCard({required this.tournament});

  final CommunityTournament tournament;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM HH:mm').format(tournament.startsAt);
    return CChessCard(
      borderColor: AppColors.accentGold.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.emoji_events,
                  color: AppColors.accentGold,
                  size: 30,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tournament.name, style: AppTextStyles.headingMd),
                    AppSpacing.vGapXs,
                    Text(
                      '$date • ${tournament.mode}',
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              _InfoPill(
                icon: Icons.how_to_reg,
                label: '${tournament.registeredPlayers}/${tournament.capacity}',
              ),
              AppSpacing.hGapSm,
              _InfoPill(
                icon: Icons.flag_outlined,
                label: tournament.statusLabel,
              ),
            ],
          ),
          AppSpacing.vGapMd,
          CChessProgressBar(value: tournament.fillRatio),
          AppSpacing.vGapXs,
          Text(
            'Giải thưởng: ${tournament.prize}',
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
            ),
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: CChessButton(
                  label: 'Đăng ký',
                  icon: Icons.app_registration,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã ghi nhận đăng ký giải đấu.'),
                    ),
                  ),
                ),
              ),
              AppSpacing.hGapSm,
              CChessButton(
                label: 'Bracket',
                icon: Icons.account_tree_outlined,
                variant: CChessButtonVariant.outline,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bracket sẽ mở khi giải bắt đầu.'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.accentGold, size: 14),
          AppSpacing.hGapXs,
          Text(
            label,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
