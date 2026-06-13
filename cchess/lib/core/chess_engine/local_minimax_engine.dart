import 'ai/bot_engine.dart';
import 'ai/game_analyzer.dart';
import 'move_engine.dart';
import 'xiangqi_game.dart';

class LocalMinimaxEngine implements MoveEngine {
  LocalMinimaxEngine({BotEngine? botEngine, this.analysisDepth = 2})
    : _botEngine = botEngine ?? BotEngine();

  final BotEngine _botEngine;
  final int analysisDepth;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
  }) async {
    final game = XiangqiGame.fromFen(fen);
    // Hint/analysis want the strongest answer fast: best-effort search (no
    // randomness, no artificial delay, time-budgeted iterative deepening).
    final move = await _botEngine.chooseMove(
      game,
      level.fallbackDifficulty,
      bestEffort: useCase != EngineUseCase.bot,
    );
    if (move == null) return null;
    return EngineMove(
      move: move,
      uci: move.toUci(),
      source: EngineSource.localMinimax,
    );
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) {
    return GameAnalyzer(
      depth: analysisDepth,
    ).analyze(startingFen: startingFen, moveUcis: moveUcis);
  }
}
