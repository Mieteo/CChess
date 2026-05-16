import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../core/constants/app_constants.dart';
import '../../data/models/opening.dart';
import '../../data/repositories/opening_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/chess/chess_board.dart';
import '../../widgets/common/common.dart';

/// View one opening — board reconstructed up to [currentPly] moves, with
/// transport controls and a sidebar of key ideas.
class OpeningDetailScreen extends ConsumerStatefulWidget {
  final String openingId;
  const OpeningDetailScreen({super.key, required this.openingId});

  @override
  ConsumerState<OpeningDetailScreen> createState() =>
      _OpeningDetailScreenState();
}

class _OpeningDetailScreenState
    extends ConsumerState<OpeningDetailScreen> {
  int _currentPly = 0;

  Board _rebuild(Opening opening) {
    final game = XiangqiGame.initial();
    for (int i = 0; i < _currentPly; i++) {
      final coords = Move.parseUciCoords(opening.mainLine[i]);
      if (coords == null) break;
      if (!game.isValidMove(coords.$1, coords.$2)) break;
      game.makeMove(coords.$1, coords.$2);
    }
    return game.board.copy();
  }

  Move? _lastMove(Opening opening) {
    if (_currentPly == 0) return null;
    final coords =
        Move.parseUciCoords(opening.mainLine[_currentPly - 1]);
    if (coords == null) return null;
    // Reconstruct prior position for piece/captured info.
    final game = XiangqiGame.initial();
    for (int i = 0; i < _currentPly - 1; i++) {
      final c = Move.parseUciCoords(opening.mainLine[i])!;
      game.makeMove(c.$1, c.$2);
    }
    final piece = game.board.at(coords.$1);
    if (piece == null) return null;
    return Move(
      from: coords.$1,
      to: coords.$2,
      moved: piece,
      captured: game.board.at(coords.$2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(openingRepositoryProvider);
    final opening = repo.byId(widget.openingId);
    if (opening == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Không tìm thấy')),
        body: Center(
          child: Text(
            'Không tìm thấy khai cuộc "${widget.openingId}"',
            style: AppTextStyles.bodyMd,
          ),
        ),
      );
    }

    final board = _rebuild(opening);
    final lastMove = _lastMove(opening);
    final atStart = _currentPly == 0;
    final atEnd = _currentPly >= opening.moveCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.woodDark,
        title: Text(opening.nameVi, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppConstants.routeOpenings),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            children: [
              _Header(opening: opening),
              AppSpacing.vGapSm,
              Expanded(
                child: AspectRatio(
                  aspectRatio: 9 / 10,
                  child: ChessBoard(
                    board: board,
                    lastMove: lastMove,
                  ),
                ),
              ),
              AppSpacing.vGapSm,
              _Transport(
                currentPly: _currentPly,
                totalPly: opening.moveCount,
                atStart: atStart,
                atEnd: atEnd,
                onStart: () => setState(() => _currentPly = 0),
                onPrev: atStart
                    ? null
                    : () => setState(() => _currentPly--),
                onNext: atEnd
                    ? null
                    : () => setState(() => _currentPly++),
                onEnd: () => setState(() => _currentPly = opening.moveCount),
                onSeek: (v) => setState(() => _currentPly = v),
              ),
              AppSpacing.vGapSm,
              SizedBox(
                height: 64,
                child: _MoveStrip(
                  opening: opening,
                  currentPly: _currentPly,
                  onTap: (i) => setState(() => _currentPly = i + 1),
                ),
              ),
              AppSpacing.vGapSm,
              if (atEnd || _currentPly == 0) _KeyIdeas(opening: opening),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Opening opening;
  const _Header({required this.opening});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                opening.nameHan,
                style: AppTextStyles.titleLg.copyWith(
                  color: AppColors.accentGold,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const Spacer(),
              for (int i = 1; i <= opening.popularity; i++)
                const Icon(
                  Icons.local_fire_department,
                  size: 14,
                  color: AppColors.vermilionRed,
                ),
            ],
          ),
          AppSpacing.vGapXs,
          Text(
            opening.tagline,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.parchmentTan,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _Transport extends StatelessWidget {
  final int currentPly;
  final int totalPly;
  final bool atStart;
  final bool atEnd;
  final VoidCallback onStart;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onEnd;
  final ValueChanged<int> onSeek;

  const _Transport({
    required this.currentPly,
    required this.totalPly,
    required this.atStart,
    required this.atEnd,
    required this.onStart,
    required this.onPrev,
    required this.onNext,
    required this.onEnd,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: atStart ? null : onStart,
                icon: const Icon(Icons.first_page),
                color: AppColors.primary,
              ),
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left),
                color: AppColors.primary,
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentGold.withValues(alpha: 0.16),
                  borderRadius: AppRadius.chip,
                  border: Border.all(color: AppColors.accentGold),
                ),
                child: Text(
                  '$currentPly / $totalPly',
                  style: AppTextStyles.monoTimer.copyWith(
                    fontSize: 14,
                    color: AppColors.accentGold,
                  ),
                ),
              ),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
                color: AppColors.primary,
              ),
              IconButton(
                onPressed: atEnd ? null : onEnd,
                icon: const Icon(Icons.last_page),
                color: AppColors.primary,
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppColors.accentGold,
              inactiveTrackColor: AppColors.surfaceContainerHigh,
              thumbColor: AppColors.accentGold,
              overlayColor: AppColors.accentGold.withValues(alpha: 0.16),
            ),
            child: Slider(
              value: currentPly.toDouble(),
              min: 0,
              max: totalPly.toDouble().clamp(1, double.infinity),
              divisions: totalPly == 0 ? 1 : totalPly,
              onChanged: (v) => onSeek(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoveStrip extends StatelessWidget {
  final Opening opening;
  final int currentPly;
  final void Function(int moveIndex) onTap;

  const _MoveStrip({
    required this.opening,
    required this.currentPly,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: opening.moveCount,
      separatorBuilder: (_, _) => AppSpacing.hGapXs,
      itemBuilder: (_, i) {
        final selected = currentPly == i + 1;
        final isRed = i.isEven;
        return GestureDetector(
          onTap: () => onTap(i),
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.accentGold.withValues(alpha: 0.18)
                  : AppColors.surfaceContainerHigh,
              borderRadius: AppRadius.card,
              border: Border.all(
                color: selected
                    ? AppColors.accentGold
                    : AppColors.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${(i ~/ 2) + 1}${isRed ? '.' : '...'}',
                  style: AppTextStyles.captionSm.copyWith(
                    color: AppColors.parchmentTan,
                    fontSize: 10,
                  ),
                ),
                Text(
                  opening.mainLine[i],
                  style: AppTextStyles.bodyMd.copyWith(
                    color: isRed
                        ? AppColors.vermilionRed
                        : AppColors.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _KeyIdeas extends StatelessWidget {
  final Opening opening;
  const _KeyIdeas({required this.opening});

  @override
  Widget build(BuildContext context) {
    return CChessCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline,
                  color: AppColors.accentGold, size: 18),
              AppSpacing.hGapSm,
              Text('Ý đồ chiến lược', style: AppTextStyles.headingMd),
            ],
          ),
          AppSpacing.vGapSm,
          Text(
            opening.descriptionVi,
            style: AppTextStyles.captionSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          AppSpacing.vGapSm,
          for (final idea in opening.keyIdeasVi) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Icon(
                    Icons.circle,
                    size: 6,
                    color: AppColors.accentGold,
                  ),
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    idea,
                    style: AppTextStyles.captionSm.copyWith(
                      color: AppColors.onSurface,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            AppSpacing.vGapXs,
          ],
        ],
      ),
    );
  }
}
