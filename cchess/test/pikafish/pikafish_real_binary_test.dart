@Timeout(Duration(minutes: 3))
library;

/// End-to-end check against a REAL Pikafish binary + NNUE. Skipped unless
/// both env vars point at existing files, e.g. (PowerShell):
///
///   $env:PIKAFISH_TEST_BINARY = 'D:\...\engine\Windows\pikafish-sse41-popcnt.exe'
///   $env:PIKAFISH_TEST_NNUE   = 'D:\...\engine\pikafish.nnue'
///   flutter test test/pikafish/pikafish_real_binary_test.dart
import 'dart:io';

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/core/chess_engine/pikafish/pikafish_support_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binary = Platform.environment['PIKAFISH_TEST_BINARY'];
  final nnue = Platform.environment['PIKAFISH_TEST_NNUE'];
  final available = binary != null &&
      nnue != null &&
      File(binary).existsSync() &&
      File(nnue).existsSync();
  final skip = available
      ? false
      : 'Set PIKAFISH_TEST_BINARY and PIKAFISH_TEST_NNUE to run';

  PikafishLocalEngine engine() => PikafishLocalEngine(
        resolveRuntime: () async => PikafishRuntime(
          binaryPath: binary!,
          nnuePath: nnue!,
          threads: 2,
        ),
        startTransport: (runtime) =>
            ProcessUciTransport.start(runtime.binaryPath),
        analysisMovetimeMs: 80,
      );

  test('real Pikafish returns a legal scored best move', () async {
    final e = engine();
    try {
      final move = await e.bestMove(
        kInitialFen,
        level: EngineLevel.grandmaster,
        useCase: EngineUseCase.hint,
      );
      expect(move, isNotNull);
      expect(move!.source, EngineSource.localPikafish);
      expect(move.scoreCp, isNotNull);
      // The move must be legal in the real rules engine.
      final game = XiangqiGame.fromFen(kInitialFen);
      expect(game.isValidMove(move.move.from, move.move.to), isTrue);
    } finally {
      await e.dispose();
    }
  }, skip: skip);

  test('real Pikafish analyzes a short game', () async {
    final e = engine();
    try {
      final analysis = await e.analyze(
        startingFen: kInitialFen,
        moveUcis: ['b2e2', 'b9c7', 'b0c2', 'h9g7'],
      );
      expect(analysis.moves, hasLength(4));
      for (final m in analysis.moves) {
        expect(m.centipawnLoss, greaterThanOrEqualTo(0));
      }
    } finally {
      await e.dispose();
    }
  }, skip: skip);
}
