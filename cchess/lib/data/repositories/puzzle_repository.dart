import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../datasources/local/puzzle_seed.dart';
import '../models/chess_puzzle.dart';

/// Repository combining the built-in puzzle catalog with locally persisted
/// per-user progress. Progress lives in a single Hive box keyed by puzzle
/// id; values are serialized as `Map<String, dynamic>` (no codegen needed).
class PuzzleRepository {
  static const String _boxName = AppConstants.boxPuzzleProgress;

  Box<dynamic>? _box;

  /// Open the Hive box lazily on first access.
  Future<Box<dynamic>> _openBox() async {
    final existing = _box;
    if (existing != null && existing.isOpen) return existing;
    final box = await Hive.openBox<dynamic>(_boxName);
    _box = box;
    return box;
  }

  /// All puzzles available to the user. For MVP this is the in-code seed
  /// list; later sprints will merge in remote / downloaded content.
  List<ChessPuzzle> allPuzzles() => List.unmodifiable(seedPuzzles);

  ChessPuzzle? puzzleById(String id) {
    for (final p in seedPuzzles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Read the progress entry for a puzzle, or a default "not attempted yet".
  Future<PuzzleProgress> getProgress(String puzzleId) async {
    final box = await _openBox();
    final raw = box.get(puzzleId);
    if (raw is Map) {
      return PuzzleProgress.fromJson(raw);
    }
    return PuzzleProgress(puzzleId: puzzleId);
  }

  /// Bulk fetch — useful for the list screen.
  Future<Map<String, PuzzleProgress>> getAllProgress() async {
    final box = await _openBox();
    final map = <String, PuzzleProgress>{};
    for (final p in seedPuzzles) {
      final raw = box.get(p.id);
      if (raw is Map) {
        map[p.id] = PuzzleProgress.fromJson(raw);
      } else {
        map[p.id] = PuzzleProgress(puzzleId: p.id);
      }
    }
    return map;
  }

  Future<void> saveProgress(PuzzleProgress progress) async {
    final box = await _openBox();
    await box.put(progress.puzzleId, progress.toJson());
  }

  /// Increment attempt counter, persist, return the new value.
  Future<PuzzleProgress> recordAttempt(
    String puzzleId, {
    bool solved = false,
    bool hintUsed = false,
  }) async {
    final current = await getProgress(puzzleId);
    final updated = current.copyWith(
      attempts: current.attempts + 1,
      hintsUsed: current.hintsUsed + (hintUsed ? 1 : 0),
      solved: current.solved || solved,
      solvedAt: solved && !current.solved ? DateTime.now() : current.solvedAt,
    );
    await saveProgress(updated);
    return updated;
  }
}

final puzzleRepositoryProvider = Provider<PuzzleRepository>((ref) {
  return PuzzleRepository();
});
