import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/chess_engine/piece.dart';
import '../../core/constants/piece_constants.dart';
import '../../theme/app_colors.dart';

/// Visual for a single Xiangqi piece.
///
/// The body is painted as a shallow lacquered wooden cylinder viewed at a
/// slight angle. The top face remains dominant while a thin lower side wall
/// makes its real thickness visible. A single lacquered rim defines the face;
/// depth comes from material planes, never from a drop shadow or blurred glow.
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
    // Keep the selection response tactile while the complete cylinder remains
    // inside its board-cell envelope on small screens.
    final scale = selected ? 1.045 : 1.0;

    return RepaintBoundary(
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: SizedBox.square(
          dimension: diameter,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _TiltedCylinderPiecePainter(
                  lacquerColor: _ringColor,
                  faceDown: faceDown,
                  selected: selected,
                  inCheck: inCheck,
                  lastMoveHighlight: lastMoveHighlight,
                ),
              ),
              // Preserve the reveal transition for Cờ Úp while the painted
              // face itself changes into its sealed back design.
              // Perspective moves the top face's optical centre a touch
              // upward, so the character follows it rather than the full box.
              Align(
                alignment: const Alignment(0, -0.27),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: faceDown
                      ? const SizedBox(key: ValueKey('face-down'))
                      : Text(
                          key: const ValueKey('face-up'),
                          piece.type.hanChar(piece.color),
                          style: GoogleFonts.notoSerifSc(
                            fontWeight: FontWeight.w900,
                            fontSize: diameter * 0.48,
                            color: _hanColor,
                            height: 1.0,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints a shallow, lacquered Xiangqi cylinder without using a shadow effect.
///
/// The side wall is a continuation of the same circular token, not a separate
/// plinth or foot. Geometry is deliberately contained within a square of
/// [diameter] because board pieces are positioned in equally sized cells.
class _TiltedCylinderPiecePainter extends CustomPainter {
  final Color lacquerColor;
  final bool faceDown;
  final bool selected;
  final bool inCheck;
  final bool lastMoveHighlight;

  const _TiltedCylinderPiecePainter({
    required this.lacquerColor,
    required this.faceDown,
    required this.selected,
    required this.inCheck,
    required this.lastMoveHighlight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = math.min(size.width, size.height);
    if (diameter <= 0) return;

    // Centre the artwork if a non-square constraint is ever supplied.
    final dx = (size.width - diameter) / 2;
    final dy = (size.height - diameter) / 2;
    canvas.save();
    canvas.translate(dx, dy);

    // The face is only slightly compressed vertically: it reads as a round
    // token seen from above, rather than a separate circular base.
    final topFace = Rect.fromLTWH(
      diameter * 0.070,
      diameter * 0.035,
      diameter * 0.860,
      diameter * 0.765,
    );
    _paintStateMarks(canvas, diameter, topFace);
    _paintDrumBody(canvas, diameter, topFace);
    _paintTopFace(canvas, diameter, topFace);

    canvas.restore();
  }

  void _paintStateMarks(Canvas canvas, double d, Rect topFace) {
    // These are crisp painted indicators rather than glows. They remain
    // visible over both the light and dark board themes.
    if (lastMoveHighlight && !selected) {
      final paint = Paint()
        ..color = AppColors.accentGold.withValues(alpha: 0.80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = d * 0.021;
      canvas.drawOval(topFace.inflate(d * 0.022), paint);
    }

    if (selected) {
      final outerPaint = Paint()
        ..color = AppColors.accentGold
        ..style = PaintingStyle.stroke
        ..strokeWidth = d * 0.027;
      canvas.drawOval(topFace.inflate(d * 0.031), outerPaint);
    }

    if (inCheck) {
      final paint = Paint()
        ..color = AppColors.error
        ..style = PaintingStyle.stroke
        ..strokeWidth = d * 0.030
        ..strokeCap = StrokeCap.round;
      final rect = topFace.inflate(d * 0.046);
      // Eight short arcs read as an alarm frame while keeping the state
      // independent from the red player lacquer.
      for (var i = 0; i < 8; i++) {
        canvas.drawArc(
          rect,
          -math.pi / 2 + i * math.pi / 4,
          math.pi / 9,
          false,
          paint,
        );
      }
    }
  }

  void _paintDrumBody(Canvas canvas, double d, Rect topFace) {
    // A token body that swells at its centre, like the shell of a small drum.
    // It is one filled material plane: intentionally no stroke is applied.
    final baseFace = Rect.fromLTWH(
      topFace.left + d * 0.020,
      topFace.top + d * 0.125,
      topFace.width - d * 0.040,
      topFace.height,
    );
    final topControlX = topFace.width * 0.276;
    final topControlY = topFace.height * 0.276;
    final baseControlX = baseFace.width * 0.276;
    final baseControlY = baseFace.height * 0.276;
    final body = Path()
      ..moveTo(topFace.left, topFace.center.dy)
      ..cubicTo(
        topFace.left,
        topFace.center.dy + topControlY,
        topFace.center.dx - topControlX,
        topFace.bottom,
        topFace.center.dx,
        topFace.bottom,
      )
      ..cubicTo(
        topFace.center.dx + topControlX,
        topFace.bottom,
        topFace.right,
        topFace.center.dy + topControlY,
        topFace.right,
        topFace.center.dy,
      )
      ..cubicTo(
        topFace.right + d * 0.035,
        topFace.center.dy + d * 0.035,
        baseFace.right + d * 0.025,
        baseFace.center.dy - d * 0.020,
        baseFace.right,
        baseFace.center.dy,
      )
      ..cubicTo(
        baseFace.right,
        baseFace.center.dy + baseControlY,
        baseFace.center.dx + baseControlX,
        baseFace.bottom,
        baseFace.center.dx,
        baseFace.bottom,
      )
      ..cubicTo(
        baseFace.center.dx - baseControlX,
        baseFace.bottom,
        baseFace.left,
        baseFace.center.dy + baseControlY,
        baseFace.left,
        baseFace.center.dy,
      )
      ..cubicTo(
        baseFace.left - d * 0.025,
        baseFace.center.dy - d * 0.020,
        topFace.left - d * 0.035,
        topFace.center.dy + d * 0.035,
        topFace.left,
        topFace.center.dy,
      )
      ..close();

    final bodyColors = faceDown
        ? const [Color(0xFF9A6B43), Color(0xFF674022), Color(0xFF3A2114)]
        : const [Color(0xFFD7B77D), Color(0xFFA56F39), Color(0xFF70451F)];
    final bodyPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(d * 0.450, d * 0.735),
        d * 0.500,
        bodyColors,
        const [0.0, 0.40, 1.0],
      );
    canvas.drawPath(body, bodyPaint);
  }

  void _paintTopFace(Canvas canvas, double d, Rect outer) {
    final faceColors = faceDown
        ? const [Color(0xFF9A6942), Color(0xFF684023), Color(0xFF321E12)]
        : const [Color(0xFFFFE7B5), Color(0xFFD4A96A), Color(0xFF8B5B35)];
    final facePaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(d * 0.335, d * 0.245),
        d * 0.72,
        faceColors,
        const [0.0, 0.54, 1.0],
      );
    canvas.drawOval(outer, facePaint);

    // A single painted rim, with a genuine 2–3 physical-pixel gap between
    // the outer face and the outside edge of the painted line.
    final edgeGap = (d * 0.055).clamp(2.0, 3.0).toDouble();
    final rimWidth = (d * 0.024).clamp(0.9, 1.4).toDouble();
    final lacquerOutline = Paint()
      ..color = lacquerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = rimWidth;
    canvas.drawOval(outer.deflate(edgeGap + rimWidth / 2), lacquerOutline);
  }

  @override
  bool shouldRepaint(covariant _TiltedCylinderPiecePainter oldDelegate) {
    return lacquerColor != oldDelegate.lacquerColor ||
        faceDown != oldDelegate.faceDown ||
        selected != oldDelegate.selected ||
        inCheck != oldDelegate.inCheck ||
        lastMoveHighlight != oldDelegate.lastMoveHighlight;
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
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.85),
          width: 1,
        ),
      ),
    );
  }
}
