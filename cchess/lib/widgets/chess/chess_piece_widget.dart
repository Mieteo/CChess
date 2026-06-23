import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/chess_engine/piece.dart';
import '../../core/constants/piece_constants.dart';
import '../../theme/app_colors.dart';

/// Visual for a single Xiangqi piece — circular face with a wood gradient,
/// colored ring (red for Red, deep navy for Black), and a Han character.
///
/// Pure-presentational. Selection / tap handling lives on the parent board.
class ChessPieceWidget extends StatelessWidget {
  final Piece piece;
  final double diameter;
  final bool selected;
  final bool inCheck;
  final bool lastMoveHighlight;
  final bool faceDown;

  const ChessPieceWidget({
    super.key,
    required this.piece,
    required this.diameter,
    this.selected = false,
    this.inCheck = false,
    this.lastMoveHighlight = false,
    this.faceDown = false,
  });

  Color get _ringColor => piece.color == PieceColor.red
      ? AppColors.vermilionRed
      : AppColors.deepNavyBlack;

  Color get _hanColor => piece.color == PieceColor.red
      ? AppColors.vermilionRed
      : AppColors.inkBlack;

  @override
  Widget build(BuildContext context) {
    final glowBoxes = <BoxShadow>[
      const BoxShadow(
        color: AppColors.shadowBrown,
        blurRadius: 4,
        offset: Offset(0, 2),
      ),
      if (selected)
        BoxShadow(
          color: AppColors.accentGold.withValues(alpha: 0.85),
          blurRadius: 14,
          spreadRadius: 1.5,
        ),
      if (inCheck)
        BoxShadow(
          color: AppColors.vermilionRed.withValues(alpha: 0.7),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      if (lastMoveHighlight && !selected)
        BoxShadow(
          color: AppColors.accentGold.withValues(alpha: 0.5),
          blurRadius: 6,
          spreadRadius: 0.5,
        ),
    ];

    final scale = selected ? 1.08 : 1.0;
    final innerSize = diameter - 6;

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: faceDown
              ? const RadialGradient(
                  center: Alignment(-0.25, -0.3),
                  radius: 0.95,
                  colors: [
                    Color(0xFF7A4F2E),
                    AppColors.woodDark,
                    Color(0xFF2A1A10),
                  ],
                  stops: [0.0, 0.58, 1.0],
                )
              : const RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  radius: 0.95,
                  colors: [
                    Color(0xFFF1D7A6),
                    AppColors.woodLight,
                    Color(0xFFA07850),
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
          border: Border.all(color: _ringColor, width: 2),
          boxShadow: glowBoxes,
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: faceDown
              ? Container(
                  key: const ValueKey('face-down'),
                  width: innerSize,
                  height: innerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.charcoalDark.withValues(alpha: 0.32),
                    border: Border.all(
                      color: AppColors.accentGold.withValues(alpha: 0.45),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.visibility_off_outlined,
                    color: AppColors.accentGold.withValues(alpha: 0.82),
                    size: diameter * 0.36,
                  ),
                )
              : Container(
                  key: const ValueKey('face-up'),
                  width: innerSize,
                  height: innerSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _ringColor.withValues(alpha: 0.55),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    piece.type.hanChar(piece.color),
                    style: GoogleFonts.notoSerifSc(
                      fontWeight: FontWeight.w900,
                      fontSize: diameter * 0.55,
                      color: _hanColor,
                      height: 1.0,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Small gold-translucent dot rendered on intersections where the currently
/// selected piece may legally move.
class ValidMoveDot extends StatelessWidget {
  final double cellSize;
  final bool isCaptureTarget;

  const ValidMoveDot({
    super.key,
    required this.cellSize,
    this.isCaptureTarget = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCaptureTarget) {
      // Ring instead of solid dot to indicate "ăn quân".
      return SizedBox(
        width: cellSize * 0.84,
        height: cellSize * 0.84,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.vermilionRed.withValues(alpha: 0.65),
              width: 3,
            ),
          ),
        ),
      );
    }
    return Container(
      width: cellSize * 0.26,
      height: cellSize * 0.26,
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGold.withValues(alpha: 0.4),
            blurRadius: 4,
          ),
        ],
      ),
    );
  }
}
