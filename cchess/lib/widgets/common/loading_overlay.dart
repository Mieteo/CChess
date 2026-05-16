import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Full-screen loading overlay with a custom brush-stroke spinner.
class LoadingOverlay extends StatelessWidget {
  final String? message;

  const LoadingOverlay({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BrushStrokeSpinner(),
          if (message != null) ...[
            AppSpacing.vGapMd,
            Text(
              message!,
              style: AppTextStyles.bodyMd.copyWith(color: AppColors.accentGold),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Ink-wash inspired loading indicator — a brush stroke that orbits.
class BrushStrokeSpinner extends StatefulWidget {
  final double size;
  final Color color;

  const BrushStrokeSpinner({
    super.key,
    this.size = 56,
    this.color = AppColors.accentGold,
  });

  @override
  State<BrushStrokeSpinner> createState() => _BrushStrokeSpinnerState();
}

class _BrushStrokeSpinnerState extends State<BrushStrokeSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, _) => CustomPaint(
          painter: _BrushPainter(progress: _ctrl.value, color: widget.color),
        ),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  final double progress;
  final Color color;

  _BrushPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;

    // Faint full ring.
    paint.color = color.withValues(alpha: 0.18);
    canvas.drawCircle(center, radius, paint);

    // Bright sweeping arc.
    paint.color = color;
    final startAngle = -math.pi / 2 + progress * math.pi * 2;
    const sweep = math.pi * 0.6;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle, sweep, false, paint);

    // Tiny ink dot tip.
    final tipX = center.dx + math.cos(startAngle + sweep) * radius;
    final tipY = center.dy + math.sin(startAngle + sweep) * radius;
    paint
      ..style = PaintingStyle.fill
      ..color = color;
    canvas.drawCircle(Offset(tipX, tipY), 3.5, paint);
  }

  @override
  bool shouldRepaint(covariant _BrushPainter old) =>
      old.progress != progress || old.color != color;
}
