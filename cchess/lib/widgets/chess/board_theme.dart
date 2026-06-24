import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Visual skin for the board surface — the colors [BoardPainter] paints with.
///
/// A shop `boardTheme` item carries a [payloadKey]; the equipped key is mapped
/// to one of [kBoardThemes] and applied to every board in the app. Unknown keys
/// fall back to [classic] so a stale/uninstalled theme never breaks rendering.
class BoardTheme {
  final String key;
  final String nameVi;
  final Color background;
  final Color grid;
  final Color riverText;
  final Color markerInk;

  /// Top→bottom wood-grain gradient painted behind the grid.
  final List<Color> woodGradient;

  const BoardTheme({
    required this.key,
    required this.nameVi,
    required this.background,
    required this.grid,
    required this.riverText,
    required this.markerInk,
    required this.woodGradient,
  });

  /// The built-in default — matches the original hardcoded board look. Every
  /// player has this without buying anything.
  static const BoardTheme classic = BoardTheme(
    key: 'classic',
    nameVi: 'Cổ Điển',
    background: AppColors.woodLight,
    grid: AppColors.inkBlack,
    riverText: AppColors.parchmentTan,
    markerInk: AppColors.charcoalDark,
    woodGradient: [Color(0xFFE6BF85), AppColors.woodLight, Color(0xFFC59559)],
  );
}

/// All themes the client knows how to render, keyed by shop `payloadKey`.
const Map<String, BoardTheme> kBoardThemes = {
  'classic': BoardTheme.classic,
  'sandalwood': BoardTheme(
    key: 'sandalwood',
    nameVi: 'Đàn Hương',
    background: Color(0xFF8A5A33),
    grid: Color(0xFF2A1606),
    riverText: Color(0xFFE8C9A0),
    markerInk: Color(0xFF3A2412),
    woodGradient: [Color(0xFFB07A47), Color(0xFF8A5A33), Color(0xFF6E441F)],
  ),
  'jade': BoardTheme(
    key: 'jade',
    nameVi: 'Ngọc Bích',
    background: Color(0xFF7BAE96),
    grid: Color(0xFF1E3D32),
    riverText: Color(0xFFEAF6EF),
    markerInk: Color(0xFF234A3C),
    woodGradient: [Color(0xFF9FCBB4), Color(0xFF7BAE96), Color(0xFF5C9079)],
  ),
  'midnight': BoardTheme(
    key: 'midnight',
    nameVi: 'Mực Nửa Đêm',
    background: Color(0xFF1F2433),
    grid: Color(0xFFB8A06A),
    riverText: Color(0xFFA9B4CC),
    markerInk: Color(0xFF8A7A4E),
    woodGradient: [Color(0xFF2A3043), Color(0xFF1F2433), Color(0xFF141826)],
  ),
  'festive': BoardTheme(
    key: 'festive',
    nameVi: 'Tết Đỏ',
    background: Color(0xFFB23A2E),
    grid: Color(0xFF4A0E08),
    riverText: Color(0xFFFFE2B0),
    markerInk: Color(0xFF6E1810),
    woodGradient: [Color(0xFFD45C44), Color(0xFFB23A2E), Color(0xFF8E2A20)],
  ),
};

/// Resolve a shop `payloadKey` to a [BoardTheme], defaulting to [classic].
BoardTheme boardThemeForKey(String? key) =>
    kBoardThemes[key] ?? BoardTheme.classic;
