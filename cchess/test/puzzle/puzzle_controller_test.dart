// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:cchess/core/chess_engine/chess_engine.dart';
import 'package:cchess/data/datasources/local/puzzle_seed.dart';
import 'package:cchess/data/repositories/puzzle_repository.dart';
import 'package:cchess/presentation/puzzle/puzzle_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fake path provider used by Hive's `initFlutter`.
class _MemPathProvider extends PathProviderPlatform {
  String? _dir;
  Future<String> _ensureDir() async {
    _dir ??= Directory.systemTemp
        .createTempSync('cchess_puzzle_test_')
        .path;
    return _dir!;
  }

  @override
  Future<String?> getApplicationDocumentsPath() => _ensureDir();
  @override
  Future<String?> getApplicationSupportPath() => _ensureDir();
  @override
  Future<String?> getTemporaryPath() => _ensureDir();
}

/// Spin the event loop until [done] is true (or a small timeout elapses) so
/// tests can wait on the controller's async save/sync without guessing a delay.
Future<void> _pumpUntil(bool Function() done, {int maxTicks = 50}) async {
  for (var i = 0; i < maxTicks && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    PathProviderPlatform.instance = _MemPathProvider();
    await Hive.initFlutter();
  });

  setUp(() async {
    // Wipe progress between tests so state doesn't leak. Use clear() instead
    // of deleteBoxFromDisk because the cached box handle in PuzzleRepository
    // holds an open file handle on Windows.
    final box = await Hive.openBox<dynamic>('cchess_puzzle_progress');
    await box.clear();
  });

  group('PuzzleController', () {
    final repo = PuzzleRepository();
    final puzzle = seedPuzzles.first; // p001 — Bắt Pháo Hớ
    final coords = Move.parseUciCoords(puzzle.solution.first)!;
    final correctFrom = coords.$1;
    final correctTo = coords.$2;

    test('starts in idle state with no progress', () {
      final c = PuzzleController(puzzle: puzzle, repo: repo);
      expect(c.state.feedback, PuzzleFeedback.idle);
      expect(c.state.solutionStep, 0);
      expect(c.state.wrongAttempts, 0);
      expect(c.state.isSolved, isFalse);
    });

    test('correct first move solves a 1-move puzzle', () async {
      final c = PuzzleController(puzzle: puzzle, repo: repo);
      c.onTap(correctFrom.row, correctFrom.col);
      expect(c.state.selected, correctFrom);

      c.onTap(correctTo.row, correctTo.col);
      // Allow the async progress save to complete.
      await Future<void>.delayed(Duration.zero);
      expect(c.state.feedback, PuzzleFeedback.solved);
      expect(c.state.isSolved, isTrue);
      expect(c.state.solutionStep, puzzle.solution.length);
    });

    test('wrong move increments wrongAttempts and stays unsolved', () async {
      final c = PuzzleController(puzzle: puzzle, repo: repo);
      // Move Red king instead of the chariot — definitely not the solution.
      c.onTap(9, 4); // select red K
      // Tap any valid king square that's NOT the puzzle answer.
      final kingMoves = c.state.validTargets;
      if (kingMoves.isNotEmpty) {
        final wrong = kingMoves.firstWhere(
          (p) => !(p.row == correctTo.row && p.col == correctTo.col),
          orElse: () => kingMoves.first,
        );
        c.onTap(wrong.row, wrong.col);
        await Future<void>.delayed(Duration.zero);
        expect(c.state.wrongAttempts, 1);
        expect(c.state.feedback, PuzzleFeedback.wrong);
        expect(c.state.isSolved, isFalse);
      }
    });

    test('requestHint escalates through 3 levels', () async {
      final c = PuzzleController(puzzle: puzzle, repo: repo);

      // Level 1: textual nudge only — no board coordinates revealed yet.
      await c.requestHint();
      expect(c.state.hintLevel, 1);
      expect(c.state.hintsRemaining, 2);
      expect(c.state.hintFrom, isNull);
      expect(c.state.hintTo, isNull);
      expect(c.state.hintText, isNotNull);

      // Level 2: highlights the source square.
      await c.requestHint();
      expect(c.state.hintLevel, 2);
      expect(c.state.hintFrom, correctFrom);
      expect(c.state.hintTo, isNull);

      // Level 3: reveals the full move.
      await c.requestHint();
      expect(c.state.hintLevel, 3);
      expect(c.state.hintFrom, correctFrom);
      expect(c.state.hintTo, correctTo);
      expect(c.state.hintsRemaining, 0);
      expect(c.state.hintsUsedTotal, 3);

      // No further escalation past level 3.
      await c.requestHint();
      expect(c.state.hintLevel, 3);
      expect(c.state.hintsUsedTotal, 3);
    });

    test('solved score decays with hints used', () async {
      final c = PuzzleController(puzzle: puzzle, repo: repo);
      await c.requestHint(); // one hint → -12
      c.onTap(correctFrom.row, correctFrom.col);
      c.onTap(correctTo.row, correctTo.col);
      // lastScore is set only after the async local-save + sync round-trip.
      await _pumpUntil(() => c.state.lastScore != null);
      expect(c.state.isSolved, isTrue);
      expect(c.state.lastScore, 88); // 100 - 1*12
    });

    test('restart resets feedback, step and per-step hints', () async {
      final c = PuzzleController(puzzle: puzzle, repo: repo);
      await c.requestHint();
      c.onTap(correctFrom.row, correctFrom.col);
      c.onTap(correctTo.row, correctTo.col);
      await Future<void>.delayed(Duration.zero);
      expect(c.state.isSolved, isTrue);
      c.restart();
      expect(c.state.feedback, PuzzleFeedback.idle);
      expect(c.state.solutionStep, 0);
      expect(c.state.hintLevel, 0);
      expect(c.state.hintsRemaining, kMaxHintLevel);
    });
  });
}
