import 'package:flutter/material.dart';

import '../../../core/chess_engine/chess_engine.dart';
import '../../../core/matchmaking/bot_matchmaker.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/common/common.dart';

/// Modal full-screen result panel shown when the game ends.
class GameResultOverlay extends StatelessWidget {
  final GameStatus status;
  final EndReason? reason;
  final PieceColor? humanColor;
  final int eloDelta;
  final Duration duration;

  /// Matchmade bot's ELO, revealed here (hidden during the game). Null for
  /// local / Cờ Úp / legacy games, which show no reveal row.
  final int? botElo;

  /// Where the bot sat relative to the player — drives the reveal caption.
  final EloBracket? bracket;

  final VoidCallback onPlayAgain;
  final VoidCallback onClose;

  const GameResultOverlay({
    super.key,
    required this.status,
    required this.reason,
    this.humanColor,
    this.eloDelta = 0,
    this.duration = Duration.zero,
    this.botElo,
    this.bracket,
    required this.onPlayAgain,
    required this.onClose,
  });

  /// One-line reveal: bot ELO + how it sat relative to the player.
  String? get _botRevealText {
    if (botElo == null) return null;
    final relation = switch (bracket) {
      EloBracket.higher => ' • mạnh hơn bạn (+$kBracketSpread)',
      EloBracket.lower => ' • yếu hơn bạn (−$kBracketSpread)',
      EloBracket.equal => ' • ngang sức',
      null => '',
    };
    return 'Đối thủ: Bot ELO $botElo$relation';
  }

  String get _title {
    if (status == GameStatus.draw) return 'Hòa cờ';
    if (humanColor == null) {
      return status == GameStatus.redWin ? 'Đỏ Thắng!' : 'Đen Thắng!';
    }
    final won =
        (status == GameStatus.redWin && humanColor == PieceColor.red) ||
        (status == GameStatus.blackWin && humanColor == PieceColor.black);
    return won ? 'Bạn Thắng!' : 'Bạn Thua...';
  }

  IconData get _icon {
    if (status == GameStatus.draw) return Icons.handshake_outlined;
    if (humanColor == null) return Icons.emoji_events;
    final won =
        (status == GameStatus.redWin && humanColor == PieceColor.red) ||
        (status == GameStatus.blackWin && humanColor == PieceColor.black);
    return won ? Icons.emoji_events : Icons.sentiment_dissatisfied;
  }

  Color get _iconColor {
    if (status == GameStatus.draw) return AppColors.accentGold;
    if (humanColor == null) return AppColors.accentGold;
    final won =
        (status == GameStatus.redWin && humanColor == PieceColor.red) ||
        (status == GameStatus.blackWin && humanColor == PieceColor.black);
    return won ? AppColors.accentGold : AppColors.parchmentTan;
  }

  String get _reasonText {
    switch (reason) {
      case EndReason.checkmate:
        return 'Chiếu hết — không còn nước thoát.';
      case EndReason.stalemate:
        return 'Hết nước đi — bị bí.';
      case EndReason.resignation:
        return 'Đầu hàng.';
      case EndReason.timeout:
        return 'Hết giờ.';
      case EndReason.drawAgreed:
        return 'Hai bên đồng ý hòa.';
      case EndReason.repetition:
        return 'Lặp lại nước đi quá nhiều lần.';
      case null:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.surfaceContainer, AppColors.charcoalDark],
              ),
              borderRadius: AppRadius.dialog,
              border: Border.all(color: AppColors.accentGold),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowBrown,
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _iconColor.withValues(alpha: 0.18),
                    border: Border.all(color: _iconColor, width: 2),
                  ),
                  child: Icon(_icon, color: _iconColor, size: 48),
                ),
                AppSpacing.vGapMd,
                Text(
                  _title,
                  style: AppTextStyles.displayCalligraphy.copyWith(
                    fontSize: 28,
                  ),
                ),
                AppSpacing.vGapXs,
                if (_reasonText.isNotEmpty)
                  Text(
                    _reasonText,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                if (_botRevealText != null) ...[
                  AppSpacing.vGapSm,
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.12),
                      borderRadius: AppRadius.chip,
                      border: Border.all(
                        color: AppColors.accentGold.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      _botRevealText!,
                      style: AppTextStyles.captionSm.copyWith(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                AppSpacing.vGapLg,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatTile(
                      label: 'Thời gian',
                      value: _formatDuration(duration),
                    ),
                    _StatTile(
                      label: 'ELO',
                      value: eloDelta == 0
                          ? '—'
                          : (eloDelta > 0 ? '+$eloDelta' : '$eloDelta'),
                      valueColor: eloDelta > 0
                          ? AppColors.tealSuccess
                          : eloDelta < 0
                          ? AppColors.error
                          : null,
                    ),
                  ],
                ),
                AppSpacing.vGapLg,
                // Stacked full-width buttons — side-by-side they ellipsized
                // ("Về tran…" / "Chơi…") on phone widths.
                CChessButton(
                  label: 'Chơi lại',
                  icon: Icons.replay,
                  fullWidth: true,
                  onPressed: onPlayAgain,
                ),
                AppSpacing.vGapSm,
                CChessButton(
                  label: 'Về trang chủ',
                  variant: CChessButtonVariant.outline,
                  fullWidth: true,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return '—';
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}p ${s}s';
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatTile({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.titleLg.copyWith(
            color: valueColor ?? AppColors.onSurface,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.captionSm.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
