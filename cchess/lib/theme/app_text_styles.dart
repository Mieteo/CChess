import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography tokens for CChess.
///
/// Uses Noto Serif for body / display (Vietnamese-friendly serif) and
/// Courier Prime for monospaced game timers, matching the design system.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get _baseSerif => GoogleFonts.notoSerif(
        color: AppColors.onSurface,
        height: 1.4,
      );

  static TextStyle get _baseMono => GoogleFonts.courierPrime(
        color: AppColors.onSurface,
        height: 1.4,
      );

  /// "Kỳ Vương Việt" / logo-style heading.
  static TextStyle get displayCalligraphy => _baseSerif.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        height: 1.25,
        color: AppColors.accentGold,
        letterSpacing: 1.2,
      );

  /// Section titles like "Học Cờ".
  static TextStyle get titleLg => _baseSerif.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 32 / 24,
        color: AppColors.secondary,
      );

  /// Card titles, dialog headings.
  static TextStyle get headingMd => _baseSerif.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 24 / 18,
        color: AppColors.onSurface,
      );

  /// Default body copy.
  static TextStyle get bodyMd => _baseSerif.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 20 / 14,
        color: AppColors.onSurface,
      );

  /// Captions / footnotes.
  static TextStyle get captionSm => _baseSerif.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 16 / 12,
        color: AppColors.onSurfaceVariant,
      );

  /// Button label.
  static TextStyle get buttonText => _baseSerif.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 20 / 16,
        letterSpacing: 0.5,
        color: AppColors.onPrimary,
      );

  /// Game countdown timer (mono).
  static TextStyle get monoTimer => _baseMono.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 24 / 18,
        letterSpacing: 1.0,
      );

  /// 12px mono — small timer / counter.
  static TextStyle get monoSm => _baseMono.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.2,
      );

  /// Style for Chinese character on a chess piece.
  static TextStyle pieceText(Color color, double size) =>
      GoogleFonts.notoSerifSc(
        fontSize: size,
        fontWeight: FontWeight.w900,
        color: color,
        height: 1.0,
      );
}
