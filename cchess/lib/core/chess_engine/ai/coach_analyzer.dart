import '../../constants/piece_constants.dart';
import 'game_analyzer.dart';

/// AI Coach (spec B3) — turns a raw per-move [GameAnalysis] into actionable,
/// player-centric coaching: how you did in each phase (khai/trung/tàn cuộc),
/// where your biggest mistakes were, and what to practise next.
///
/// This is PURE logic (no engine, no UI) so it can be unit-tested directly and
/// reused regardless of whether the underlying analysis came from the local
/// minimax engine or the remote Pikafish service.

/// The three classic game phases.
enum GamePhase { opening, middlegame, endgame }

extension GamePhaseX on GamePhase {
  String get nameVi {
    switch (this) {
      case GamePhase.opening:
        return 'Khai cuộc';
      case GamePhase.middlegame:
        return 'Trung cuộc';
      case GamePhase.endgame:
        return 'Tàn cuộc';
    }
  }
}

/// What a coaching insight nudges the player to do next, so the UI can route to
/// the matching feature.
enum CoachActionKind { reviewMoves, practicePuzzles, studyOpenings, takeLessons }

/// Tone of an insight, so the UI can colour/iconify it.
enum CoachTone { praise, tip, warning }

/// One coaching insight: a short Vietnamese headline + explanation, optionally
/// pointing at a concrete next step.
class CoachInsight {
  final String title;
  final String detail;
  final CoachTone tone;
  final CoachActionKind? action;

  const CoachInsight({
    required this.title,
    required this.detail,
    required this.tone,
    this.action,
  });
}

/// Per-phase scorecard for the player's own moves.
class PhaseReport {
  final GamePhase phase;
  final int moveCount;
  final double accuracy; // 0..100, average move quality of the player's moves
  final int inaccuracies;
  final int mistakes;
  final int blunders;

  const PhaseReport({
    required this.phase,
    required this.moveCount,
    required this.accuracy,
    required this.inaccuracies,
    required this.mistakes,
    required this.blunders,
  });

  bool get hasData => moveCount > 0;
  int get errorCount => inaccuracies + mistakes + blunders;
}

/// The full coach report for one game, from the player's perspective.
class CoachReport {
  final PieceColor playerColor;
  final double overallAccuracy; // 0..100
  final List<PhaseReport> phases; // always opening, middlegame, endgame in order
  final GamePhase? weakestPhase;
  final GamePhase? strongestPhase;
  final List<CoachInsight> insights;

  /// The player's most costly moves (worst first), for a "review these" list.
  final List<MoveAnalysis> criticalMoments;

  /// Number of the player's analysed moves. 0 means there was nothing to grade
  /// (e.g. the player never moved) — the UI should show an empty state.
  final int analysedMoveCount;

  const CoachReport({
    required this.playerColor,
    required this.overallAccuracy,
    required this.phases,
    required this.weakestPhase,
    required this.strongestPhase,
    required this.insights,
    required this.criticalMoments,
    required this.analysedMoveCount,
  });

  bool get isEmpty => analysedMoveCount == 0;

  PhaseReport phaseReport(GamePhase phase) =>
      phases.firstWhere((p) => p.phase == phase);

  /// Coarse Vietnamese grade band for the overall accuracy.
  String get gradeVi => gradeForAccuracy(overallAccuracy);
}

/// Vietnamese grade band shared by the report and the UI.
String gradeForAccuracy(double accuracy) {
  if (accuracy >= 90) return 'Xuất sắc';
  if (accuracy >= 80) return 'Tốt';
  if (accuracy >= 70) return 'Khá';
  if (accuracy >= 55) return 'Trung bình';
  return 'Cần cải thiện';
}

/// Builds [CoachReport]s from [GameAnalysis].
class CoachAnalyzer {
  /// Plies (half-moves) 0..[openingPlies)-1 count as the opening. Default 16
  /// ≈ first 8 moves per side, a reasonable opening window in Xiangqi.
  final int openingPlies;

  /// From this ply onward (0-based) counts as the endgame. Default 48
  /// ≈ move 24+. Heuristic by move number since [GameAnalysis] carries evals,
  /// not material counts.
  final int endgameStartPly;

  /// A phase needs at least this many of the player's moves before we'll call
  /// it their weakest/strongest — avoids over-reacting to a 1-move "phase".
  final int minPhaseMoves;

  const CoachAnalyzer({
    this.openingPlies = 16,
    this.endgameStartPly = 48,
    this.minPhaseMoves = 3,
  });

  GamePhase phaseForPly(int ply) {
    if (ply < openingPlies) return GamePhase.opening;
    if (ply >= endgameStartPly) return GamePhase.endgame;
    return GamePhase.middlegame;
  }

  CoachReport analyze(GameAnalysis analysis, PieceColor playerColor) {
    final playerMoves =
        analysis.moves.where((m) => m.mover == playerColor).toList();

    final phases = [
      for (final phase in GamePhase.values)
        _phaseReport(
          phase,
          playerMoves.where((m) => phaseForPly(m.moveIndex) == phase).toList(),
        ),
    ];

    final overall = analysis.accuracyFor(playerColor);
    final ranked = phases.where((p) => p.moveCount >= minPhaseMoves).toList()
      ..sort((a, b) => a.accuracy.compareTo(b.accuracy));
    final weakest = ranked.isEmpty ? null : ranked.first.phase;
    final strongest = ranked.isEmpty ? null : ranked.last.phase;

    final critical = playerMoves
        .where((m) => m.quality.index >= MoveQuality.mistake.index)
        .toList()
      ..sort((a, b) => b.centipawnLoss.compareTo(a.centipawnLoss));

    final insights = _buildInsights(
      overall: overall,
      phases: phases,
      weakest: weakest,
      strongest: strongest,
      criticalCount: critical.length,
      hasData: playerMoves.isNotEmpty,
    );

    return CoachReport(
      playerColor: playerColor,
      overallAccuracy: overall,
      phases: phases,
      weakestPhase: weakest,
      strongestPhase: strongest == weakest ? null : strongest,
      insights: insights,
      criticalMoments: critical.take(3).toList(),
      analysedMoveCount: playerMoves.length,
    );
  }

  PhaseReport _phaseReport(GamePhase phase, List<MoveAnalysis> moves) {
    if (moves.isEmpty) {
      return PhaseReport(
        phase: phase,
        moveCount: 0,
        accuracy: 0,
        inaccuracies: 0,
        mistakes: 0,
        blunders: 0,
      );
    }
    var score = 0;
    var inacc = 0, mist = 0, blun = 0;
    for (final m in moves) {
      score += m.quality.scoreOut100;
      switch (m.quality) {
        case MoveQuality.inaccuracy:
          inacc++;
          break;
        case MoveQuality.mistake:
          mist++;
          break;
        case MoveQuality.blunder:
          blun++;
          break;
        default:
          break;
      }
    }
    return PhaseReport(
      phase: phase,
      moveCount: moves.length,
      accuracy: score / moves.length,
      inaccuracies: inacc,
      mistakes: mist,
      blunders: blun,
    );
  }

  List<CoachInsight> _buildInsights({
    required double overall,
    required List<PhaseReport> phases,
    required GamePhase? weakest,
    required GamePhase? strongest,
    required int criticalCount,
    required bool hasData,
  }) {
    if (!hasData) return const [];
    final insights = <CoachInsight>[];

    // 1. Overall headline.
    if (overall >= 85) {
      insights.add(CoachInsight(
        title: 'Ván đấu chắc tay',
        detail:
            'Độ chính xác tổng thể ${overall.toStringAsFixed(0)}% — bạn chơi rất ổn định. Hãy giữ phong độ và thử bot mạnh hơn.',
        tone: CoachTone.praise,
      ));
    } else if (overall >= 70) {
      insights.add(CoachInsight(
        title: 'Nền tảng tốt, còn chỗ mài giũa',
        detail:
            'Độ chính xác tổng thể ${overall.toStringAsFixed(0)}%. Vài nước thiếu chính xác đã kéo điểm xuống — xem lại các nước đáng tiếc bên dưới.',
        tone: CoachTone.tip,
        action: CoachActionKind.reviewMoves,
      ));
    } else {
      insights.add(CoachInsight(
        title: 'Tập trung vào nền tảng',
        detail:
            'Độ chính xác tổng thể ${overall.toStringAsFixed(0)}%. Nhiều nước đi chệch hướng — luyện thêm bài tập chiến thuật sẽ cải thiện nhanh.',
        tone: CoachTone.warning,
        action: CoachActionKind.practicePuzzles,
      ));
    }

    // 2. Weakest phase → targeted, routable advice.
    if (weakest != null) {
      final wr = phases.firstWhere((p) => p.phase == weakest);
      insights.add(_weakPhaseInsight(wr));
    }

    // 3. Praise the strongest phase if it's genuinely strong and distinct.
    if (strongest != null && strongest != weakest) {
      final sr = phases.firstWhere((p) => p.phase == strongest);
      if (sr.accuracy >= 80) {
        insights.add(CoachInsight(
          title: '${sr.phase.nameVi} là điểm mạnh',
          detail:
              'Bạn xử lý ${sr.phase.nameVi.toLowerCase()} rất tốt (${sr.accuracy.toStringAsFixed(0)}%). Đây là vũ khí đáng tin cậy của bạn.',
          tone: CoachTone.praise,
        ));
      }
    }

    // 4. Blunder callout.
    if (criticalCount > 0) {
      insights.add(CoachInsight(
        title: 'Có $criticalCount nước cờ bước ngoặt',
        detail:
            'Những nước sai lầm này thay đổi cục diện nhiều nhất. Xem lại để hiểu nước đi tốt hơn ở mỗi thế.',
        tone: CoachTone.warning,
        action: CoachActionKind.reviewMoves,
      ));
    }

    return insights;
  }

  CoachInsight _weakPhaseInsight(PhaseReport wr) {
    switch (wr.phase) {
      case GamePhase.opening:
        return CoachInsight(
          title: 'Khai cuộc cần vững hơn',
          detail:
              'Khai cuộc của bạn đạt ${wr.accuracy.toStringAsFixed(0)}% (${wr.errorCount} nước chưa tối ưu). Học các thế khai cuộc đại sư để vào trung cuộc thuận thế.',
          tone: CoachTone.tip,
          action: CoachActionKind.studyOpenings,
        );
      case GamePhase.middlegame:
        // Tune the message to the error shape: blunder-heavy play means missed
        // tactics (drill attacking combinations), while mistakes without
        // blunders means getting slowly outplayed (drill solid defense).
        if (wr.blunders > 0 && wr.blunders >= wr.mistakes) {
          return CoachInsight(
            title: 'Trung cuộc bỏ lỡ đòn quyết định',
            detail:
                'Trung cuộc của bạn đạt ${wr.accuracy.toStringAsFixed(0)}% với ${wr.blunders} sai lầm lớn. Luyện các thế tấn công và phối hợp để chớp thời cơ dứt điểm.',
            tone: CoachTone.warning,
            action: CoachActionKind.practicePuzzles,
          );
        }
        if (wr.mistakes > 0 && wr.blunders == 0) {
          return CoachInsight(
            title: 'Trung cuộc bị lấn thế dần',
            detail:
                'Trung cuộc của bạn đạt ${wr.accuracy.toStringAsFixed(0)}% (${wr.errorCount} nước chưa tối ưu). Luyện phòng thủ chắc chắn để không bị ép thế từng nước.',
            tone: CoachTone.tip,
            action: CoachActionKind.practicePuzzles,
          );
        }
        return CoachInsight(
          title: 'Trung cuộc dễ tính sai',
          detail:
              'Trung cuộc của bạn đạt ${wr.accuracy.toStringAsFixed(0)}% (${wr.errorCount} nước chưa tối ưu). Luyện bài tập chiến thuật để tính nước phối hợp tốt hơn.',
          tone: CoachTone.tip,
          action: CoachActionKind.practicePuzzles,
        );
      case GamePhase.endgame:
        return CoachInsight(
          title: 'Tàn cuộc là nơi để cải thiện',
          detail:
              'Tàn cuộc của bạn đạt ${wr.accuracy.toStringAsFixed(0)}% (${wr.errorCount} nước chưa tối ưu). Luyện tàn cục cổ điển để dứt điểm chắc chắn hơn.',
          tone: CoachTone.tip,
          action: CoachActionKind.practicePuzzles,
        );
    }
  }
}
