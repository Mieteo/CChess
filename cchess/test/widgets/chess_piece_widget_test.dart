import 'package:cchess/core/chess_engine/piece.dart';
import 'package:cchess/widgets/chess/chess_piece_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPiece(WidgetTester tester, ChessPieceWidget piece) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: piece)),
      ),
    );
  }

  group('ChessPieceWidget', () {
    testWidgets('renders a lacquered painter and the visible Han character', (
      tester,
    ) async {
      await pumpPiece(
        tester,
        const ChessPieceWidget(piece: Piece.redGeneral, diameter: 56),
      );

      final pieceFinder = find.byType(ChessPieceWidget);
      expect(
        find.descendant(of: pieceFinder, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
      expect(find.text(Piece.redGeneral.hanChar), findsOneWidget);
      // The piece body is entirely custom-painted; this prevents accidentally
      // reintroducing a BoxDecoration-based drop shadow.
      expect(
        find.descendant(of: pieceFinder, matching: find.byType(Container)),
        findsNothing,
      );
    });

    testWidgets('keeps the 3D body but hides identity for a face-down piece', (
      tester,
    ) async {
      await pumpPiece(
        tester,
        const ChessPieceWidget(
          piece: Piece.blackHorse,
          diameter: 40,
          faceDown: true,
          selected: true,
          inCheck: true,
          lastMoveHighlight: true,
        ),
      );

      final pieceFinder = find.byType(ChessPieceWidget);
      expect(
        find.descendant(of: pieceFinder, matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
      expect(find.text(Piece.blackHorse.hanChar), findsNothing);
      expect(
        find.descendant(of: pieceFinder, matching: find.byType(AnimatedScale)),
        findsOneWidget,
      );
    });

    testWidgets('matches the lacquered-piece visual treatment', (tester) async {
      const previewKey = Key('piece-preview');
      await tester.binding.setSurfaceSize(const Size(380, 132));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: previewKey,
                child: Container(
                  width: 360,
                  height: 112,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFD4A96A), Color(0xFFA07850)],
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ChessPieceWidget(piece: Piece.redGeneral, diameter: 58),
                      ChessPieceWidget(piece: Piece.blackGeneral, diameter: 58),
                      ChessPieceWidget(
                        piece: Piece.redHorse,
                        diameter: 58,
                        selected: true,
                      ),
                      ChessPieceWidget(
                        piece: Piece.blackCannon,
                        diameter: 58,
                        inCheck: true,
                      ),
                      ChessPieceWidget(
                        piece: Piece.redSoldier,
                        diameter: 58,
                        faceDown: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byKey(previewKey),
        matchesGoldenFile('goldens/chess_piece_widget_preview.png'),
      );
    });
  });
}
