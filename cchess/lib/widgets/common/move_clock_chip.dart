import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

/// Small inline per-move countdown chip — `⏱ mm:ss` — shared by the online and
/// the local/bot game screens so the move clock renders identically everywhere.
///
/// [visible] toggles whether the chip is drawn for the side to move, but the
/// chip ALWAYS reserves its footprint (via [Visibility.maintainSize]). That way
/// showing/hiding it on a turn change never alters the player strip's height —
/// which previously nudged the whole board up/down each turn.
class MoveClockChip extends StatelessWidget {
  const MoveClockChip({
    super.key,
    required this.timeLeft,
    required this.visible,
  });

  final Duration timeLeft;
  final bool visible;

  static String _format(Duration d) {
    final total = d.isNegative ? 0 : d.inSeconds;
    final mm = (total ~/ 60).toString().padLeft(2, '0');
    final ss = (total % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final color = timeLeft.inSeconds <= 10
        ? Colors.redAccent
        : AppColors.accentGold;
    return Visibility(
      visible: visible,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 3),
          Text(
            _format(timeLeft),
            style: AppTextStyles.captionSm.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
