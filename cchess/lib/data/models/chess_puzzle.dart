import 'package:equatable/equatable.dart';

import '../../core/chess_engine/chess_engine.dart';

/// A single Xiangqi puzzle (tàn cục).
///
/// `solution` is the canonical sequence of moves in UCI notation. The first
/// move belongs to the solving player (whoever's turn FEN says it is); the
/// second to the opponent (auto-played); the third to the solver; etc.
class ChessPuzzle extends Equatable {
  /// Stable identifier — used as the key for progress persistence.
  final String id;

  /// Starting position FEN. Includes side-to-move.
  final String fen;

  /// UCI-format moves: solver, opponent, solver, …
  final List<String> solution;

  /// Vietnamese title ("Bắt pháo hớ", "Chiếu hết trong 2 nước"…).
  final String titleVi;

  /// Longer description / hint for the puzzle.
  final String descriptionVi;

  /// Tags such as "Tàn cục", "Xe Pháo", "Chiếu bí".
  final List<String> tags;

  /// 1 (easiest) .. 5 (hardest).
  final int difficulty;

  const ChessPuzzle({
    required this.id,
    required this.fen,
    required this.solution,
    required this.titleVi,
    required this.descriptionVi,
    this.tags = const [],
    this.difficulty = 1,
  });

  /// Number of moves the solver makes (odd-indexed entries are opponent
  /// replies that get auto-played).
  int get solverMoveCount => (solution.length + 1) ~/ 2;

  PieceColor get playerColor {
    // FEN's side-to-move field is the second whitespace-delimited token.
    final parts = fen.split(' ');
    if (parts.length < 2) return PieceColor.red;
    return parts[1] == 'b' ? PieceColor.black : PieceColor.red;
  }

  @override
  List<Object?> get props =>
      [id, fen, solution, titleVi, descriptionVi, tags, difficulty];
}

/// Per-user progress for one puzzle. Persisted as JSON in Hive.
class PuzzleProgress extends Equatable {
  final String puzzleId;
  final bool solved;
  final int attempts;
  final int hintsUsed;
  final DateTime? solvedAt;

  const PuzzleProgress({
    required this.puzzleId,
    this.solved = false,
    this.attempts = 0,
    this.hintsUsed = 0,
    this.solvedAt,
  });

  PuzzleProgress copyWith({
    bool? solved,
    int? attempts,
    int? hintsUsed,
    DateTime? solvedAt,
  }) {
    return PuzzleProgress(
      puzzleId: puzzleId,
      solved: solved ?? this.solved,
      attempts: attempts ?? this.attempts,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      solvedAt: solvedAt ?? this.solvedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'puzzleId': puzzleId,
        'solved': solved,
        'attempts': attempts,
        'hintsUsed': hintsUsed,
        'solvedAt': solvedAt?.toIso8601String(),
      };

  factory PuzzleProgress.fromJson(Map<dynamic, dynamic> json) {
    return PuzzleProgress(
      puzzleId: json['puzzleId'] as String,
      solved: json['solved'] as bool? ?? false,
      attempts: json['attempts'] as int? ?? 0,
      hintsUsed: json['hintsUsed'] as int? ?? 0,
      solvedAt: (json['solvedAt'] as String?) == null
          ? null
          : DateTime.tryParse(json['solvedAt'] as String),
    );
  }

  @override
  List<Object?> get props =>
      [puzzleId, solved, attempts, hintsUsed, solvedAt];
}
