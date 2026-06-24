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

  /// Coarse bucket the backend filters by, e.g. `checkmate_1`, `capture`,
  /// `defense`, `tactic`. Empty for the built-in seed (which uses [tags]).
  final String category;

  /// Free-form sub-theme within a category (e.g. "Xe Pháo", "song xe"). Empty
  /// when unknown.
  final String theme;

  /// Server-maintained share of attempts that ended solved, in `0..1`. Zero
  /// for local-only puzzles that have never round-tripped through the backend.
  final double solveRate;

  const ChessPuzzle({
    required this.id,
    required this.fen,
    required this.solution,
    required this.titleVi,
    required this.descriptionVi,
    this.tags = const [],
    this.difficulty = 1,
    this.category = '',
    this.theme = '',
    this.solveRate = 0,
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

  ChessPuzzle copyWith({
    String? id,
    String? fen,
    List<String>? solution,
    String? titleVi,
    String? descriptionVi,
    List<String>? tags,
    int? difficulty,
    String? category,
    String? theme,
    double? solveRate,
  }) {
    return ChessPuzzle(
      id: id ?? this.id,
      fen: fen ?? this.fen,
      solution: solution ?? this.solution,
      titleVi: titleVi ?? this.titleVi,
      descriptionVi: descriptionVi ?? this.descriptionVi,
      tags: tags ?? this.tags,
      difficulty: difficulty ?? this.difficulty,
      category: category ?? this.category,
      theme: theme ?? this.theme,
      solveRate: solveRate ?? this.solveRate,
    );
  }

  /// Parse a puzzle from JSON. Handles both the backend `PuzzleDoc` shape
  /// (which carries `solveRateGlobal`) and the app's own cache shape (which
  /// stores `solveRate`). Unknown / missing fields fall back to defaults so a
  /// schema drift never throws at the boundary.
  factory ChessPuzzle.fromJson(Map<dynamic, dynamic> json) {
    return ChessPuzzle(
      id: (json['id'] as String?) ?? '',
      fen: (json['fen'] as String?) ?? '',
      solution: _stringList(json['solution']),
      titleVi: (json['titleVi'] as String?) ?? '',
      descriptionVi: (json['descriptionVi'] as String?) ?? '',
      tags: _stringList(json['tags']),
      difficulty: _asInt(json['difficulty']) ?? 1,
      category: (json['category'] as String?) ?? '',
      theme: (json['theme'] as String?) ?? '',
      solveRate: _asDouble(json['solveRate'] ?? json['solveRateGlobal']) ?? 0,
    );
  }

  /// Cache-friendly map (also a superset of what the list/detail screens need).
  Map<String, dynamic> toJson() => {
        'id': id,
        'fen': fen,
        'solution': solution,
        'titleVi': titleVi,
        'descriptionVi': descriptionVi,
        'tags': tags,
        'difficulty': difficulty,
        'category': category,
        'theme': theme,
        'solveRate': solveRate,
      };

  @override
  List<Object?> get props => [
        id,
        fen,
        solution,
        titleVi,
        descriptionVi,
        tags,
        difficulty,
        category,
        theme,
        solveRate,
      ];
}

/// Per-user progress for one puzzle. Persisted as JSON in Hive and mirrored to
/// the backend (`users/{uid}/puzzle_progress/{id}`) when signed in.
class PuzzleProgress extends Equatable {
  final String puzzleId;
  final bool solved;
  final int attempts;
  final int hintsUsed;

  /// Highest score earned on this puzzle (0..100). Server-clamped; 0 until the
  /// first scored attempt is reported.
  final int bestScore;
  final DateTime? solvedAt;

  const PuzzleProgress({
    required this.puzzleId,
    this.solved = false,
    this.attempts = 0,
    this.hintsUsed = 0,
    this.bestScore = 0,
    this.solvedAt,
  });

  PuzzleProgress copyWith({
    bool? solved,
    int? attempts,
    int? hintsUsed,
    int? bestScore,
    DateTime? solvedAt,
  }) {
    return PuzzleProgress(
      puzzleId: puzzleId,
      solved: solved ?? this.solved,
      attempts: attempts ?? this.attempts,
      hintsUsed: hintsUsed ?? this.hintsUsed,
      bestScore: bestScore ?? this.bestScore,
      solvedAt: solvedAt ?? this.solvedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'puzzleId': puzzleId,
        'solved': solved,
        'attempts': attempts,
        'hintsUsed': hintsUsed,
        'bestScore': bestScore,
        'solvedAt': solvedAt?.toIso8601String(),
      };

  factory PuzzleProgress.fromJson(Map<dynamic, dynamic> json) {
    return PuzzleProgress(
      puzzleId: json['puzzleId'] as String,
      solved: json['solved'] as bool? ?? false,
      attempts: _asInt(json['attempts']) ?? 0,
      hintsUsed: _asInt(json['hintsUsed']) ?? 0,
      bestScore: _asInt(json['bestScore']) ?? 0,
      solvedAt: (json['solvedAt'] as String?) == null
          ? null
          : DateTime.tryParse(json['solvedAt'] as String),
    );
  }

  /// Parse the backend `PuzzleProgressDoc` returned by POST /puzzles/:id/progress
  /// (timestamps are epoch millis there, not ISO strings).
  factory PuzzleProgress.fromRemoteJson(Map<dynamic, dynamic> json) {
    final solvedAtMs = _asInt(json['solvedAtMs']);
    return PuzzleProgress(
      puzzleId: json['puzzleId'] as String,
      solved: json['solved'] as bool? ?? false,
      attempts: _asInt(json['attempts']) ?? 0,
      hintsUsed: _asInt(json['hintsUsed']) ?? 0,
      bestScore: _asInt(json['bestScore']) ?? 0,
      solvedAt: solvedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(solvedAtMs),
    );
  }

  @override
  List<Object?> get props =>
      [puzzleId, solved, attempts, hintsUsed, bestScore, solvedAt];
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const [];
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

double? _asDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return null;
}
