import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/app_text_styles.dart';

/// Bottom toolbar with the secondary game actions: leave, undo, draw, resign,
/// sound toggle.
class GameActionBar extends StatelessWidget {
  final bool canUndo;
  final bool soundOn;
  final VoidCallback onLeave;
  final VoidCallback onUndo;
  final VoidCallback onDraw;
  final VoidCallback onResign;
  final VoidCallback onToggleSound;
  final VoidCallback onFlip;

  const GameActionBar({
    super.key,
    required this.canUndo,
    required this.soundOn,
    required this.onLeave,
    required this.onUndo,
    required this.onDraw,
    required this.onResign,
    required this.onToggleSound,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.charcoalDark,
        border: Border.all(color: AppColors.outlineVariant),
        borderRadius: AppRadius.card,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ActionButton(
            icon: Icons.exit_to_app,
            label: 'Ra ngoài',
            onTap: onLeave,
          ),
          _ActionButton(
            icon: Icons.undo,
            label: 'Đi lại',
            onTap: canUndo ? onUndo : null,
          ),
          _ActionButton(
            icon: Icons.handshake_outlined,
            label: 'Cầu hòa',
            onTap: onDraw,
          ),
          _ActionButton(
            icon: Icons.flag_outlined,
            label: 'Xin thua',
            onTap: onResign,
          ),
          _ActionButton(
            icon: Icons.flip_camera_android_outlined,
            label: 'Xoay',
            onTap: onFlip,
          ),
          _ActionButton(
            icon: soundOn ? Icons.volume_up : Icons.volume_off,
            label: soundOn ? 'Tiếng' : 'Im',
            onTap: onToggleSound,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final color = enabled ? AppColors.primary : AppColors.parchmentTan;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.card,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              AppSpacing.vGapXs,
              Text(
                label,
                style: AppTextStyles.captionSm.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
