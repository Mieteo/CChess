import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../data/datasources/remote/tournaments_api_source.dart';
import '../../data/models/community_models.dart';
import '../../data/repositories/tournament_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/common.dart';
import 'community_widgets.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  ConsumerState<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends ConsumerState<TournamentDetailScreen> {
  late Future<_TournamentDetail> _future;
  bool _busy = false;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_TournamentDetail> _load() async {
    final source = ref.read(tournamentsApiSourceProvider);
    final tournament = await source.getTournament(widget.tournamentId);
    if (tournament == null) return const _TournamentDetail(tournament: null, participants: [], matches: []);
    final participants = await source.listParticipants(widget.tournamentId);
    final matches = await source.listMatches(widget.tournamentId);
    return _TournamentDetail(tournament: tournament, participants: participants, matches: matches);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  bool _iRegistered(List<TournamentParticipant> participants) {
    final uid = _myUid;
    return uid != null && participants.any((p) => p.uid == uid);
  }

  Future<void> _toggleRegistration(CommunityTournament t, bool registered) async {
    setState(() => _busy = true);
    try {
      if (registered) {
        await ref.read(tournamentRepositoryProvider).unregister(t.id);
        _showSnack('Đã hủy đăng ký');
      } else {
        await ref.read(tournamentRepositoryProvider).register(t.id);
        _showSnack('Đã đăng ký ${t.name}');
      }
      _reload();
    } on TournamentApiException catch (e) {
      _showSnack(_messageFor(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(TournamentApiException e) {
    switch (e.code) {
      case 'registration-closed':
        return 'Giải đấu đã đóng đăng ký';
      case 'tournament-full':
        return 'Giải đấu đã đủ người';
      case 'already-registered':
        return 'Bạn đã đăng ký giải này';
      case 'elo-too-low':
      case 'elo-too-high':
        return 'ELO của bạn không nằm trong khoảng cho phép';
      case 'missing-token':
        return 'Cần đăng nhập để đăng ký giải đấu';
      default:
        return e.isNetworkError ? 'Không có kết nối mạng' : e.message;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _playMatch(TournamentMatch match) {
    context.push(
      '${AppConstants.routeOnlineLobby}?tournamentId=${widget.tournamentId}&matchId=${match.id}',
    );
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
        FutureBuilder<_TournamentDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: BrushStrokeSpinner());
            }
            final detail = snapshot.data!;
            final t = detail.tournament;
            if (t == null) {
              return const CommunityEmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'Không tìm thấy giải đấu',
                message: 'Giải đấu này có thể đã bị xóa.',
              );
            }
            final registered = _iRegistered(detail.participants);
            final myMatch = detail.matches
                .where(
                  (m) =>
                      m.isPlayer(_myUid) &&
                      (m.status == TournamentMatchStatus.ready || m.status == TournamentMatchStatus.inProgress),
                )
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.name, style: AppTextStyles.titleLg),
                AppSpacing.vGapXs,
                Text(
                  '${DateFormat('dd/MM HH:mm').format(t.startsAt)} • ${t.mode}',
                  style: AppTextStyles.captionSm.copyWith(color: AppColors.parchmentTan),
                ),
                AppSpacing.vGapMd,
                Row(
                  children: [
                    Expanded(
                      child: CommunityMetricChip(
                        icon: Icons.how_to_reg,
                        label: 'Đăng ký',
                        value: '${t.registeredPlayers}/${t.capacity}',
                        color: AppColors.tertiary,
                      ),
                    ),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: CommunityMetricChip(
                        icon: Icons.flag_outlined,
                        label: 'Trạng thái',
                        value: t.statusLabel,
                      ),
                    ),
                  ],
                ),
                AppSpacing.vGapXs,
                Text(
                  'Giải thưởng: ${t.prize.isEmpty ? '—' : t.prize}',
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
                AppSpacing.vGapLg,
                if (t.status == TournamentStatus.registering)
                  CChessButton(
                    label: registered ? 'Hủy đăng ký' : 'Đăng ký',
                    icon: registered ? Icons.close : Icons.app_registration,
                    variant: registered ? CChessButtonVariant.outline : CChessButtonVariant.primary,
                    fullWidth: true,
                    onPressed: _busy ? null : () => _toggleRegistration(t, registered),
                  ),
                if (myMatch != null) ...[
                  AppSpacing.vGapMd,
                  CChessButton(
                    label: 'Vào trận',
                    icon: Icons.sports_esports_outlined,
                    variant: CChessButtonVariant.danger,
                    fullWidth: true,
                    onPressed: () => _playMatch(myMatch),
                  ),
                ],
                AppSpacing.vGapLg,
                Text('Bracket', style: AppTextStyles.headingMd),
                AppSpacing.vGapMd,
                if (detail.matches.isEmpty)
                  Text(
                    'Bracket sẽ mở khi giải bắt đầu.',
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                  )
                else
                  _BracketView(matches: detail.matches, myUid: _myUid),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TournamentDetail {
  const _TournamentDetail({required this.tournament, required this.participants, required this.matches});
  final CommunityTournament? tournament;
  final List<TournamentParticipant> participants;
  final List<TournamentMatch> matches;
}

class _BracketView extends StatelessWidget {
  const _BracketView({required this.matches, required this.myUid});

  final List<TournamentMatch> matches;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final rounds = matches.map((m) => m.round).toSet().toList()..sort();
    final totalRounds = rounds.isEmpty ? 0 : rounds.last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final round in rounds) ...[
          Text(
            round == totalRounds ? 'Chung kết' : 'Vòng $round',
            style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700, color: AppColors.accentGold),
          ),
          AppSpacing.vGapSm,
          for (final match in matches.where((m) => m.round == round).toList()..sort((a, b) => a.slotIndex - b.slotIndex)) ...[
            _MatchRow(match: match, isMine: match.isPlayer(myUid)),
            AppSpacing.vGapSm,
          ],
          AppSpacing.vGapMd,
        ],
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.isMine});

  final TournamentMatch match;
  final bool isMine;

  String _label(String? uid) => uid ?? 'TBD';

  @override
  Widget build(BuildContext context) {
    final winner = match.winnerUid;
    return CChessCard(
      borderColor: isMine ? AppColors.accentGold.withValues(alpha: 0.5) : AppColors.outlineVariant,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_label(match.player1Id)}  vs  ${_label(match.player2Id)}',
              style: AppTextStyles.bodyMd.copyWith(
                fontWeight: winner != null ? FontWeight.w700 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          AppSpacing.hGapSm,
          if (winner != null)
            Icon(Icons.emoji_events, color: AppColors.accentGold, size: 16)
          else if (match.status == TournamentMatchStatus.pending)
            Text('Chờ', style: AppTextStyles.captionSm.copyWith(color: AppColors.onSurfaceVariant))
          else
            Text('Sẵn sàng', style: AppTextStyles.captionSm.copyWith(color: AppColors.tealSuccess)),
        ],
      ),
    );
  }
}
