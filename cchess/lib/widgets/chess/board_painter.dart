import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Paints the static parts of a Xiangqi board: wood background, grid lines,
/// palace diagonals, the river, and the small "L" markers next to soldier
/// and cannon starting points.
///
/// Pieces are rendered on top of the painter as separate widgets, since they
/// have their own gradients, glows, and tap handling.
class BoardPainter extends CustomPainter {
  /// Padding (in board-cell units) reserved around the grid for the river
  /// text and so pieces near the edge don't overflow the widget.
  static const double edgePadCells = 0.6;

  /// Hex of the wood-grain background.
  final Color background;
  final Color grid;
  final Color riverText;
  final Color markerInk;

  BoardPainter({
    this.background = AppColors.woodLight,
    this.grid = AppColors.inkBlack,
    this.riverText = AppColors.parchmentTan,
    this.markerInk = AppColors.charcoalDark,
  });

  /// Maps a (row, col) board coordinate to its pixel center within [size].
  static Offset cellToOffset(Size size, int row, int col) {
    final geom = _BoardGeometry.fromSize(size);
    return geom.intersection(row, col);
  }

  /// Maps a pixel position back to the closest board (row, col), or null if
  /// the tap fell outside the grid (within a small tolerance).
  static (int row, int col)? offsetToCell(Size size, Offset position) {
    final geom = _BoardGeometry.fromSize(size);
    final dx = position.dx - geom.gridLeft;
    final dy = position.dy - geom.gridTop;
    final col = (dx / geom.cellSize).round();
    final row = (dy / geom.cellSize).round();
    if (row < 0 || row > 9 || col < 0 || col > 8) return null;
    // Reject taps too far from the closest intersection.
    final ideal = geom.intersection(row, col);
    if ((ideal - position).distance > geom.cellSize * 0.6) return null;
    return (row, col);
  }

  /// Returns the diameter to use for piece widgets at this canvas size.
  static double pieceDiameter(Size size) =>
      _BoardGeometry.fromSize(size).cellSize * 0.86;

  @override
  void paint(Canvas canvas, Size size) {
    final geom = _BoardGeometry.fromSize(size);
    final bgPaint = Paint()..shader = _woodShader(geom);
    canvas.drawRect(Offset.zero & size, bgPaint);

    _paintBoardFrame(canvas, geom);
    _paintHorizontalLines(canvas, geom);
    _paintVerticalLines(canvas, geom);
    _paintPalace(canvas, geom);
    _paintRiver(canvas, geom);
    _paintStartingMarkers(canvas, geom);
  }

  // The shape of the inner darker frame.
  void _paintBoardFrame(Canvas canvas, _BoardGeometry geom) {
    final framePaint = Paint()
      ..color = AppColors.charcoalDark.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final outer = Rect.fromLTRB(
      geom.gridLeft - 8,
      geom.gridTop - 8,
      geom.gridRight + 8,
      geom.gridBottom + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(4)),
      framePaint,
    );
  }

  void _paintHorizontalLines(Canvas canvas, _BoardGeometry geom) {
    final paint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (int r = 0; r < 10; r++) {
      final y = geom.gridTop + r * geom.cellSize;
      canvas.drawLine(
        Offset(geom.gridLeft, y),
        Offset(geom.gridRight, y),
        paint,
      );
    }
  }

  void _paintVerticalLines(Canvas canvas, _BoardGeometry geom) {
    final paint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (int c = 0; c < 9; c++) {
      final x = geom.gridLeft + c * geom.cellSize;
      // The river splits inner columns. Outer columns (0 and 8) go top to
      // bottom uninterrupted.
      if (c == 0 || c == 8) {
        canvas.drawLine(
          Offset(x, geom.gridTop),
          Offset(x, geom.gridBottom),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(x, geom.gridTop),
          Offset(x, geom.gridTop + 4 * geom.cellSize),
          paint,
        );
        canvas.drawLine(
          Offset(x, geom.gridTop + 5 * geom.cellSize),
          Offset(x, geom.gridBottom),
          paint,
        );
      }
    }
  }

  void _paintPalace(Canvas canvas, _BoardGeometry geom) {
    final paint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    // Black palace top: (0,3)-(2,5)
    canvas.drawLine(
      geom.intersection(0, 3),
      geom.intersection(2, 5),
      paint,
    );
    canvas.drawLine(
      geom.intersection(0, 5),
      geom.intersection(2, 3),
      paint,
    );
    // Red palace bottom: (7,3)-(9,5)
    canvas.drawLine(
      geom.intersection(7, 3),
      geom.intersection(9, 5),
      paint,
    );
    canvas.drawLine(
      geom.intersection(7, 5),
      geom.intersection(9, 3),
      paint,
    );
  }

  void _paintRiver(Canvas canvas, _BoardGeometry geom) {
    final midY = geom.gridTop + 4.5 * geom.cellSize;
    final textStyle = TextStyle(
      color: riverText,
      fontFamily: 'NotoSerif',
      fontSize: geom.cellSize * 0.5,
      fontStyle: FontStyle.italic,
      fontWeight: FontWeight.w600,
    );

    final left = TextPainter(
      text: TextSpan(text: 'Hán  Giới', style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    left.paint(
      canvas,
      Offset(
        geom.gridLeft + geom.cellSize * 1.0,
        midY - left.height / 2,
      ),
    );

    final right = TextPainter(
      text: TextSpan(text: 'Sở  Hà', style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    right.paint(
      canvas,
      Offset(
        geom.gridRight - geom.cellSize * 1.0 - right.width,
        midY - right.height / 2,
      ),
    );
  }

  /// Small ⌐⌐ corner ticks next to soldier (row 3 and 6) and cannon
  /// (row 2 and 7) starting intersections — a traditional Xiangqi cue.
  void _paintStartingMarkers(Canvas canvas, _BoardGeometry geom) {
    final paint = Paint()
      ..color = markerInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final tickLen = geom.cellSize * 0.18;
    const gap = 3.0;

    void drawTicks(int row, int col, {bool leftSide = true, bool rightSide = true}) {
      final center = geom.intersection(row, col);
      // Top-left tick group
      if (leftSide) {
        // ⌐ shape pointing into the cell on top-left of the intersection
        canvas.drawLine(
          Offset(center.dx - gap - tickLen, center.dy - gap),
          Offset(center.dx - gap, center.dy - gap),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx - gap, center.dy - gap - tickLen),
          Offset(center.dx - gap, center.dy - gap),
          paint,
        );
        // Bottom-left
        canvas.drawLine(
          Offset(center.dx - gap - tickLen, center.dy + gap),
          Offset(center.dx - gap, center.dy + gap),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx - gap, center.dy + gap),
          Offset(center.dx - gap, center.dy + gap + tickLen),
          paint,
        );
      }
      if (rightSide) {
        // Top-right
        canvas.drawLine(
          Offset(center.dx + gap, center.dy - gap),
          Offset(center.dx + gap + tickLen, center.dy - gap),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx + gap, center.dy - gap - tickLen),
          Offset(center.dx + gap, center.dy - gap),
          paint,
        );
        // Bottom-right
        canvas.drawLine(
          Offset(center.dx + gap, center.dy + gap),
          Offset(center.dx + gap + tickLen, center.dy + gap),
          paint,
        );
        canvas.drawLine(
          Offset(center.dx + gap, center.dy + gap),
          Offset(center.dx + gap, center.dy + gap + tickLen),
          paint,
        );
      }
    }

    // Cannons: (2,1)/(2,7) and (7,1)/(7,7).
    drawTicks(2, 1);
    drawTicks(2, 7);
    drawTicks(7, 1);
    drawTicks(7, 7);

    // Soldiers row 3 (black) and row 6 (red), cols 0,2,4,6,8. Skip the edge
    // half-ticks for cols 0 (no left) and 8 (no right).
    for (final (row, col) in [
      (3, 0),
      (3, 2),
      (3, 4),
      (3, 6),
      (3, 8),
      (6, 0),
      (6, 2),
      (6, 4),
      (6, 6),
      (6, 8),
    ]) {
      drawTicks(
        row,
        col,
        leftSide: col != 0,
        rightSide: col != 8,
      );
    }
  }

  Shader _woodShader(_BoardGeometry geom) {
    return const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFE6BF85), AppColors.woodLight, Color(0xFFC59559)],
    ).createShader(
      Rect.fromLTWH(0, 0, geom.size.width, geom.size.height),
    );
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.background != background ||
      old.grid != grid ||
      old.riverText != riverText ||
      old.markerInk != markerInk;
}

/// Internal helper precomputing the geometry of the board so painters
/// and tap handlers agree on intersection positions.
class _BoardGeometry {
  final Size size;
  final double cellSize;
  final double gridLeft;
  final double gridTop;
  final double gridRight;
  final double gridBottom;

  _BoardGeometry._(
    this.size,
    this.cellSize,
    this.gridLeft,
    this.gridTop,
  )   : gridRight = gridLeft + cellSize * 8,
        gridBottom = gridTop + cellSize * 9;

  factory _BoardGeometry.fromSize(Size size) {
    // Reserve padding around the grid so pieces near the edge are still
    // fully visible inside the widget.
    final padFactor = 1 + BoardPainter.edgePadCells * 2;
    final maxCellFromWidth = size.width / (8 + BoardPainter.edgePadCells * 2);
    final maxCellFromHeight = size.height / (9 + BoardPainter.edgePadCells * 2);
    final cellSize = maxCellFromWidth < maxCellFromHeight
        ? maxCellFromWidth
        : maxCellFromHeight;
    final boardW = cellSize * (8 + BoardPainter.edgePadCells * 2);
    final boardH = cellSize * (9 + BoardPainter.edgePadCells * 2);
    final left = (size.width - boardW) / 2 + cellSize * BoardPainter.edgePadCells;
    final top = (size.height - boardH) / 2 + cellSize * BoardPainter.edgePadCells;
    // padFactor isn't used directly but documents intent — silence linter.
    assert(padFactor > 1);
    return _BoardGeometry._(size, cellSize, left, top);
  }

  Offset intersection(int row, int col) => Offset(
        gridLeft + col * cellSize,
        gridTop + row * cellSize,
      );
}
