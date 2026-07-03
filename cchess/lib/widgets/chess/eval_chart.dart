import 'package:flutter/material.dart';

import '../../core/chess_engine/chess_engine.dart';
import '../../theme/app_colors.dart';

/// Line chart of the engine eval across a finished game, synced with the
/// replay position — the "điểm số tăng giảm" view every serious xiangqi app
/// has. The series is Red-positive centipawns (`MoveAnalysis.evalAfterCp`):
/// above the midline Red is better, below it Black is. Tap or drag to seek.
class EvalChart extends StatelessWidget {
  final GameAnalysis analysis;
  final int totalPly;
  final int currentPly;
  final ValueChanged<int> onSeek;

  const EvalChart({
    super.key,
    required this.analysis,
    required this.totalPly,
    required this.currentPly,
    required this.onSeek,
  });

  /// Display clamp: beyond ±1500cp (and any mate score) the game is decided —
  /// flatten to the chart edge so mid-game swings stay readable.
  static const int displayCapCp = 1500;

  /// Chart series: `series[i]` = eval after ply i+1, Red-positive, null for
  /// moves the analysis never graded (e.g. it stopped at a broken record).
  static List<int?> evalSeries(GameAnalysis analysis, int totalPly) {
    final series = List<int?>.filled(totalPly, null);
    for (final m in analysis.moves) {
      if (m.moveIndex >= 0 && m.moveIndex < totalPly) {
        series[m.moveIndex] = m.evalAfterCp;
      }
    }
    return series;
  }

  /// Vertical position as a fraction (0 = top of chart) for an eval.
  static double yFraction(int evalCp) {
    final clamped = evalCp.clamp(-displayCapCp, displayCapCp);
    return 0.5 - clamped / (2 * displayCapCp);
  }

  /// Which ply (0..totalPly) a horizontal position maps to.
  static int plyForDx(double dx, double width, int totalPly) {
    if (totalPly <= 0 || width <= 0) return 0;
    return ((dx / width) * totalPly).round().clamp(0, totalPly);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seekAt(double dx) =>
            onSeek(plyForDx(dx, constraints.maxWidth, totalPly));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _EvalChartPainter(
              series: evalSeries(analysis, totalPly),
              qualities: _qualitySeries(),
              totalPly: totalPly,
              currentPly: currentPly,
            ),
          ),
        );
      },
    );
  }

  List<MoveQuality?> _qualitySeries() {
    final qualities = List<MoveQuality?>.filled(totalPly, null);
    for (final m in analysis.moves) {
      if (m.moveIndex >= 0 && m.moveIndex < totalPly) {
        qualities[m.moveIndex] = m.quality;
      }
    }
    return qualities;
  }
}

class _EvalChartPainter extends CustomPainter {
  final List<int?> series;
  final List<MoveQuality?> qualities;
  final int totalPly;
  final int currentPly;

  _EvalChartPainter({
    required this.series,
    required this.qualities,
    required this.totalPly,
    required this.currentPly,
  });

  double _x(int ply, Size size) =>
      totalPly == 0 ? 0 : size.width * ply / totalPly;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;

    // Background: red's half above the midline, black's half below.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height / 2),
      Paint()..color = AppColors.vermilionRed.withValues(alpha: 0.07),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2),
      Paint()..color = AppColors.deepNavyBlack.withValues(alpha: 0.18),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = AppColors.outlineVariant,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = AppColors.parchmentTan.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    // Eval polyline. Starts at the midline (equal position before move 1);
    // gaps in the series break the line rather than lying across them.
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = AppColors.accentGold;
    Path? path;
    if (series.isNotEmpty && series.first != null) {
      path = Path()..moveTo(0, size.height / 2);
    }
    for (var i = 0; i < series.length; i++) {
      final eval = series[i];
      if (eval == null) {
        if (path != null) canvas.drawPath(path, linePaint);
        path = null;
        continue;
      }
      final point = Offset(
        _x(i + 1, size),
        EvalChart.yFraction(eval) * size.height,
      );
      if (path == null) {
        path = Path()..moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (path != null) canvas.drawPath(path, linePaint);

    // Mistake/blunder markers — the "khoảnh khắc bước ngoặt" dots.
    for (var i = 0; i < series.length; i++) {
      final eval = series[i];
      final quality = qualities[i];
      if (eval == null || quality == null) continue;
      if (quality != MoveQuality.mistake && quality != MoveQuality.blunder) {
        continue;
      }
      canvas.drawCircle(
        Offset(_x(i + 1, size), EvalChart.yFraction(eval) * size.height),
        quality == MoveQuality.blunder ? 3.5 : 2.5,
        Paint()..color = quality.color,
      );
    }

    // Current replay position.
    final cursorX = _x(currentPly, size);
    canvas.drawLine(
      Offset(cursorX, 0),
      Offset(cursorX, size.height),
      Paint()
        ..color = AppColors.accentGold.withValues(alpha: 0.9)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_EvalChartPainter oldDelegate) =>
      oldDelegate.currentPly != currentPly ||
      oldDelegate.totalPly != totalPly ||
      !identical(oldDelegate.series, series) &&
          !_sameSeries(oldDelegate.series, series);

  static bool _sameSeries(List<int?> a, List<int?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
