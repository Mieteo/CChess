import 'package:flutter/material.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../theme/app_colors.dart';
import 'board_painter.dart';
import 'chess_piece_widget.dart';

/// Composable chess-board widget.
///
/// Renders the static board via [BoardPainter] and overlays pieces / valid
/// move dots / last-move indicators as positioned children. Forwards taps
/// to [onTap] as (row, col) once they snap to an intersection.
class ChessBoard extends StatelessWidget {
  final Board board;
  final Position? selected;
  final List<Position> validTargets;
  final Move? lastMove;
  final Position? checkedKing;
  final bool flipped;
  final void Function(int row, int col)? onTap;

  const ChessBoard({
    super.key,
    required this.board,
    this.selected,
    this.validTargets = const [],
    this.lastMove,
    this.checkedKing,
    this.flipped = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pieceSize = BoardPainter.pieceDiameter(size);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            if (onTap == null) return;
            final pos = _maybeFlip(details.localPosition, size);
            final cell = BoardPainter.offsetToCell(size, pos);
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
                child: CustomPaint(painter: BoardPainter()),
              ),
              if (lastMove != null) ...[
                _intersectionMarker(
                  size,
                  _displayPos(lastMove!.from),
                  AppColors.accentGold.withValues(alpha: 0.25),
                  pieceSize,
                ),
                _intersectionMarker(
                  size,
                  _displayPos(lastMove!.to),
                  AppColors.accentGold.withValues(alpha: 0.45),
                  pieceSize,
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
                ),
              for (final (pos, piece) in board.occupied())
                _placeAt(
                  size,
                  _displayPos(pos),
                  ChessPieceWidget(
                    piece: piece,
                    diameter: pieceSize,
                    selected: selected == pos,
                    inCheck: checkedKing == pos,
                    lastMoveHighlight:
                        lastMove != null && lastMove!.to == pos,
                  ),
                  animateMove: lastMove != null && lastMove!.to == pos,
                ),
            ],
          ),
        );
      },
    );
  }

  Offset _maybeFlip(Offset local, Size size) {
    if (!flipped) return local;
    return Offset(size.width - local.dx, size.height - local.dy);
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
  }) {
    final center = BoardPainter.cellToOffset(size, displayPos.row, displayPos.col);
    final pieceSize = BoardPainter.pieceDiameter(size);
    final half = pieceSize / 2;
    // For Stack children that hold non-piece widgets (ValidMoveDot) the dot
    // is smaller than pieceSize — but Positioned still centers via the
    // piece-box around the intersection.
    if (animateMove) {
      return AnimatedPositioned(
        key: ValueKey('animated-${displayPos.row}-${displayPos.col}'),
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
    double pieceSize,
  ) {
    final center = BoardPainter.cellToOffset(size, displayPos.row, displayPos.col);
    final markerSize = pieceSize * 0.92;
    return Positioned(
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
              color: AppColors.accentGold.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
