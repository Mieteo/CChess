import 'coach_analyzer.dart';

/// AI Coach (spec B3) — personalized practice plan.
///
/// Turns a [CoachReport] (where you're weak, how badly) into a concrete,
/// routable "what to drill today" plan: which kind of training, which puzzle
/// tags/category to pull, and a difficulty band sized to your current level.
///
/// PURE logic (no engine, no UI, no I/O) so it unit-tests directly. The UI layer
/// feeds the resulting [CoachPlan] to the puzzle repository to fetch the actual
/// recommended exercises.

/// The training theme a plan steers the player toward, so the UI can label and
/// route it.
enum CoachFocus { opening, tactics, attack, defense, endgame }

extension CoachFocusX on CoachFocus {
  String get nameVi {
    switch (this) {
      case CoachFocus.opening:
        return 'Khai cuộc';
      case CoachFocus.tactics:
        return 'Chiến thuật';
      case CoachFocus.attack:
        return 'Tấn công';
      case CoachFocus.defense:
        return 'Phòng thủ';
      case CoachFocus.endgame:
        return 'Tàn cuộc';
    }
  }
}

/// A concrete, personalized practice plan derived from one game's coaching.
class CoachPlan {
  final CoachFocus focus;

  /// The game phase this plan targets (the player's weakest, when known).
  final GamePhase targetPhase;

  /// Ordered preference of puzzle tags to search for, most specific first.
  /// The fetch layer tries these against the catalog (and broadens if empty).
  final List<String> tags;

  /// Backend puzzle category to filter by, when the focus maps cleanly to one.
  /// Empty when the search should rely on [tags] alone.
  final String category;

  /// Inclusive difficulty band (1..5) sized to the player's overall accuracy.
  final int minDifficulty;
  final int maxDifficulty;

  /// One-line Vietnamese explanation of *why* this is today's plan.
  final String rationaleVi;

  const CoachPlan({
    required this.focus,
    required this.targetPhase,
    required this.tags,
    required this.category,
    required this.minDifficulty,
    required this.maxDifficulty,
    required this.rationaleVi,
  });

  /// A representative difficulty inside the band — the midpoint, rounded down.
  int get suggestedDifficulty => (minDifficulty + maxDifficulty) ~/ 2;

  bool difficultyInBand(int difficulty) =>
      difficulty >= minDifficulty && difficulty <= maxDifficulty;
}

/// Builds a [CoachPlan] from a [CoachReport].
class CoachRecommender {
  const CoachRecommender();

  CoachPlan plan(CoachReport report) {
    final targetPhase = _targetPhase(report);
    final phase = report.phaseReport(targetPhase);
    final focus = _focusFor(targetPhase, phase);
    final (minD, maxD) = _difficultyBand(report.overallAccuracy);
    return CoachPlan(
      focus: focus,
      targetPhase: targetPhase,
      tags: _tagsFor(focus),
      category: _categoryFor(focus),
      minDifficulty: minD,
      maxDifficulty: maxD,
      rationaleVi: _rationale(phase, focus),
    );
  }

  /// The phase to drill: the report's weakest when known, otherwise the phase
  /// (with enough data) carrying the most errors; falls back to middlegame.
  GamePhase _targetPhase(CoachReport report) {
    if (report.weakestPhase != null) return report.weakestPhase!;
    PhaseReport? worst;
    for (final p in report.phases) {
      if (!p.hasData) continue;
      if (worst == null || p.errorCount > worst.errorCount) worst = p;
    }
    return worst?.phase ?? GamePhase.middlegame;
  }

  /// Map a weak phase + its error profile to a training focus.
  ///
  /// Opening/endgame map straight to their phase. The middlegame is where the
  /// error *shape* matters: blunder-heavy play means missed tactics (drill
  /// attacking combinations), mistake-heavy-but-no-blunders means getting
  /// slowly outplayed (drill defense), otherwise general tactics.
  CoachFocus _focusFor(GamePhase phase, PhaseReport report) {
    switch (phase) {
      case GamePhase.opening:
        return CoachFocus.opening;
      case GamePhase.endgame:
        return CoachFocus.endgame;
      case GamePhase.middlegame:
        if (report.blunders > 0 && report.blunders >= report.mistakes) {
          return CoachFocus.attack;
        }
        if (report.mistakes > 0 && report.blunders == 0) {
          return CoachFocus.defense;
        }
        return CoachFocus.tactics;
    }
  }

  /// Harder players get harder puzzles. Bands overlap by design so a session
  /// always has a mix rather than a single fixed difficulty.
  (int, int) _difficultyBand(double accuracy) {
    if (accuracy < 55) return (1, 2);
    if (accuracy < 70) return (2, 3);
    if (accuracy < 85) return (3, 4);
    return (4, 5);
  }

  List<String> _tagsFor(CoachFocus focus) {
    switch (focus) {
      case CoachFocus.opening:
        return const ['Khai môn', 'Khai cuộc', 'Chiến thuật'];
      case CoachFocus.tactics:
        return const ['Tactic', 'Chiến thuật'];
      case CoachFocus.attack:
        return const ['Chiếu hết', 'Tactic', 'Chiến thuật'];
      case CoachFocus.defense:
        return const ['Phòng thủ', 'Tàn cục'];
      case CoachFocus.endgame:
        return const ['Tàn cục', 'Tactic'];
    }
  }

  String _categoryFor(CoachFocus focus) {
    switch (focus) {
      case CoachFocus.opening:
        return 'opening';
      case CoachFocus.tactics:
        return 'tactic';
      case CoachFocus.attack:
        return 'checkmate';
      case CoachFocus.defense:
        return 'defense';
      case CoachFocus.endgame:
        return 'endgame';
    }
  }

  String _rationale(PhaseReport pr, CoachFocus focus) {
    final acc = pr.hasData
        ? ' (độ chính xác ${pr.accuracy.toStringAsFixed(0)}%)'
        : '';
    switch (focus) {
      case CoachFocus.opening:
        return 'Khai cuộc của bạn còn chệch hướng$acc — luyện các bài khai cuộc '
            'để vào trung cuộc thuận thế.';
      case CoachFocus.tactics:
        return 'Trung cuộc là nơi bạn mất điểm nhiều nhất$acc — luyện chiến '
            'thuật để tính nước phối hợp sắc bén hơn.';
      case CoachFocus.attack:
        return 'Bạn bỏ lỡ những đòn quyết định ở trung cuộc$acc — luyện các thế '
            'tấn công và chiếu hết để dứt điểm.';
      case CoachFocus.defense:
        return 'Bạn bị lấn thế dần ở trung cuộc$acc — luyện phòng thủ để giữ '
            'vững thế trận trước sức ép.';
      case CoachFocus.endgame:
        return 'Tàn cuộc là nơi để cải thiện$acc — luyện tàn cục cổ điển để dứt '
            'điểm chắc chắn hơn.';
    }
  }
}
