import 'ai/bot_engine.dart';
import 'ai/engine_config.dart';
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
    EngineConfig? config,
  }) async {
    final game = XiangqiGame.fromFen(fen);
    // Bot play follows the ELO config (depth + blunder rate) when one is given;
    // hint/analysis ignore it and want the strongest answer fast: best-effort
    // search (no randomness, no artificial delay, time-budgeted deepening).
    final botConfig = useCase == EngineUseCase.bot ? config : null;
    final move = await _botEngine.chooseMove(
      game,
      level.fallbackDifficulty,
      bestEffort: useCase != EngineUseCase.bot,
      depthOverride: botConfig?.depth,
      blunderRate: botConfig?.blunderRate,
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
