import 'package:cchess/widgets/chess/board_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('boardThemeForKey resolves known keys', () {
    expect(boardThemeForKey('jade').key, 'jade');
    expect(boardThemeForKey('sandalwood').key, 'sandalwood');
    expect(boardThemeForKey('midnight').nameVi, 'Mực Nửa Đêm');
  });

  test('unknown / null keys fall back to classic', () {
    expect(boardThemeForKey('does-not-exist').key, 'classic');
    expect(boardThemeForKey(null).key, 'classic');
    expect(boardThemeForKey(''), BoardTheme.classic);
  });

  test('classic default matches the original hardcoded board look', () {
    expect(BoardTheme.classic.woodGradient.length, 3);
    // The middle stop is the wood-light tone the painter used by default.
    expect(BoardTheme.classic.woodGradient[1], const Color(0xFFD4A96A));
  });

  test('every theme defines a full color set + 3-stop gradient', () {
    for (final theme in kBoardThemes.values) {
      expect(theme.key, isNotEmpty);
      expect(theme.nameVi, isNotEmpty);
      expect(theme.woodGradient.length, greaterThanOrEqualTo(2));
    }
  });
}
