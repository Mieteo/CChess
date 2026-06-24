import 'package:flutter/material.dart';

import '../../data/models/shop_item.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chess/board_theme.dart';

/// Accent color for a rarity tier.
Color rarityColor(Rarity rarity) {
  switch (rarity) {
    case Rarity.common:
      return AppColors.onSurfaceVariant;
    case Rarity.rare:
      return AppColors.tertiary;
    case Rarity.epic:
      return const Color(0xFFB983FF);
    case Rarity.legendary:
      return AppColors.accentGold;
  }
}

IconData kindIcon(ShopItemKind kind) {
  switch (kind) {
    case ShopItemKind.boardTheme:
      return Icons.grid_on;
    case ShopItemKind.pieceSet:
      return Icons.circle;
    case ShopItemKind.avatarFrame:
      return Icons.filter_frames_outlined;
    case ShopItemKind.chatBubble:
      return Icons.chat_bubble_outline;
    case ShopItemKind.nameplate:
      return Icons.badge_outlined;
    case ShopItemKind.soundPack:
      return Icons.music_note_outlined;
    case ShopItemKind.consumable:
      return Icons.bolt;
  }
}

/// A small visual swatch for a shop/inventory item. Board themes get a real
/// mini-board preview (so the player sees the actual surface they're buying);
/// other kinds fall back to a tinted kind icon.
class ShopItemPreview extends StatelessWidget {
  final ShopItem item;
  final double size;
  const ShopItemPreview({super.key, required this.item, this.size = 56});

  @override
  Widget build(BuildContext context) {
    if (item.kind == ShopItemKind.boardTheme) {
      return _BoardSwatch(theme: boardThemeForKey(item.payloadKey), size: size);
    }
    final color = rarityColor(item.rarity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(kindIcon(item.kind), color: color, size: size * 0.45),
    );
  }
}

class _BoardSwatch extends StatelessWidget {
  final BoardTheme theme;
  final double size;
  const _BoardSwatch({required this.theme, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: theme.woodGradient,
        ),
        border: Border.all(color: theme.markerInk.withValues(alpha: 0.6)),
      ),
      child: CustomPaint(painter: _MiniGridPainter(theme.grid)),
    );
  }
}

class _MiniGridPainter extends CustomPainter {
  final Color grid;
  const _MiniGridPainter(this.grid);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = grid
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const pad = 6.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    for (int i = 0; i < 4; i++) {
      final y = pad + h * i / 3;
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), paint);
    }
    for (int i = 0; i < 4; i++) {
      final x = pad + w * i / 3;
      canvas.drawLine(Offset(x, pad), Offset(x, pad + h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniGridPainter old) => old.grid != grid;
}
