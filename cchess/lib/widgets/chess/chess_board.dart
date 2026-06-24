import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../presentation/shop/shop_controller.dart';
import '../../theme/app_colors.dart';
import 'board_painter.dart';
import 'chess_piece_widget.dart';

/// Composable chess-board widget.
///
/// Renders the static board via [BoardPainter] and overlays pieces / valid
/// move dots / last-move indicators as positioned children. Forwards taps
/// to [onTap] as (row, col) once they snap to an intersection.
///
/// A [ConsumerWidget] so it can watch the equipped board theme (S16) and
/// re-skin the surface when a board cosmetic is equipped.
class ChessBoard extends ConsumerWidget {
  final Board board;
  final Position? selected;
  final List<Position> validTargets;
  final Move? lastMove;
  final Move? hintMove;
  final Position? checkedKing;
  final Set<Position> hiddenPositions;
  final bool flipped;
  final void Function(int row, int col)? onTap;

  const ChessBoard({
    super.key,
    required this.board,
    this.selected,
    this.validTargets = const [],
    this.lastMove,
    this.hintMove,
    this.checkedKing,
    this.hiddenPositions = const {},
    this.flipped = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(equippedBoardThemeProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pieceSize = BoardPainter.pieceDiameter(size);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (onTap == null) return;
            // Get the visual painter cell directly. When the board is flipped
            // we convert that DISPLAY cell back to its BOARD coordinate.
            // (Previously also `_maybeFlip`-ed the pixel — that double-flip
            // returned the wrong board position when flipped.)
            final cell = BoardPainter.offsetToCell(size, details.localPosition);
            if (cell == null) return;
            var (row, col) = cell;
            if (flipped) {
              row = 9 - row;
              col = 8 - col;
            }
            onTap!(row, col);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: BoardPainter(
                    background: theme.background,
                    grid: theme.grid,
                    riverText: theme.riverText,
                    markerInk: theme.markerInk,
                    woodGradient: theme.woodGradient,
                  ),
                ),
              ),
              if (lastMove != null) ...[
                _intersectionMarker(
                  size,
                  _displayPos(lastMove!.from),
                  AppColors.accentGold.withValues(alpha: 0.25),
                  pieceSize,
                  key: const ValueKey('last-from'),
                ),
                _intersectionMarker(
                  size,
                  _displayPos(lastMove!.to),
                  AppColors.accentGold.withValues(alpha: 0.45),
                  pieceSize,
                  key: const ValueKey('last-to'),
                ),
              ],
              if (hintMove != null) ...[
                _intersectionMarker(
                  size,
                  _displayPos(hintMove!.from),
                  AppColors.tealSuccess.withValues(alpha: 0.30),
                  pieceSize,
                  borderColor: AppColors.tealSuccess,
                  key: const ValueKey('hint-from'),
                ),
                _intersectionMarker(
                  size,
                  _displayPos(hintMove!.to),
                  AppColors.tealSuccess.withValues(alpha: 0.50),
                  pieceSize,
                  borderColor: AppColors.tealSuccess,
                  key: const ValueKey('hint-to'),
                ),
              ],
              for (final target in validTargets)
                _placeAt(
                  size,
                  _displayPos(target),
                  ValidMoveDot(
                    cellSize: pieceSize,
                    isCaptureTarget: board.at(target) != null,
                  ),
                  // Key by BOARD square so adding/removing dots never shifts
                  // the reconciliation of the piece widgets below.
                  key: ValueKey('dot-${target.row}-${target.col}'),
                ),
              // Pieces are keyed by their BOARD square so that selecting a
              // piece (which inserts the dots above) does not re-create every
              // piece element — that re-creation was replaying each piece's
              // entry animation, making the whole board flicker on every tap.
              for (final (pos, piece) in board.occupied())
                _placeAt(
                  size,
                  _displayPos(pos),
                  ChessPieceWidget(
                    piece: piece,
                    diameter: pieceSize,
                    selected: selected == pos,
                    inCheck: checkedKing == pos,
                    lastMoveHighlight: lastMove != null && lastMove!.to == pos,
                    faceDown: hiddenPositions.contains(pos),
                  ),
                  animateMove: lastMove != null && lastMove!.to == pos,
                  key: ValueKey('piece-${pos.row}-${pos.col}'),
                ),
            ],
          ),
        );
      },
    );
  }

  Position _displayPos(Position p) {
    if (!flipped) return p;
    return Position(9 - p.row, 8 - p.col);
  }

  Widget _placeAt(
    Size size,
    Position displayPos,
    Widget child, {
    bool animateMove = false,
    Key? key,
  }) {
    final center = BoardPainter.cellToOffset(
      size,
      displayPos.row,
      displayPos.col,
    );
    final pieceSize = BoardPainter.pieceDiameter(size);
    final half = pieceSize / 2;
    // For Stack children that hold non-piece widgets (ValidMoveDot) the dot
    // is smaller than pieceSize — but Positioned still centers via the
    // piece-box around the intersection.
    if (animateMove) {
      return AnimatedPositioned(
        key: key ?? ValueKey('animated-${displayPos.row}-${displayPos.col}'),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        left: center.dx - half,
        top: center.dy - half,
        width: pieceSize,
        height: pieceSize,
        child: Center(child: child),
      );
    }
    return Positioned(
      key: key,
      left: center.dx - half,
      top: center.dy - half,
      width: pieceSize,
      height: pieceSize,
      child: Center(child: child),
    );
  }

  Widget _intersectionMarker(
    Size size,
    Position displayPos,
    Color color,
    double pieceSize, {
    Color? borderColor,
    Key? key,
  }) {
    final center = BoardPainter.cellToOffset(
      size,
      displayPos.row,
      displayPos.col,
    );
    final markerSize = pieceSize * 0.92;
    return Positioned(
      key: key,
      left: center.dx - markerSize / 2,
      top: center.dy - markerSize / 2,
      width: markerSize,
      height: markerSize,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor ?? AppColors.accentGold.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
