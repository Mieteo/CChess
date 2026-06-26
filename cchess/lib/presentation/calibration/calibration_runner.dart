import '../../core/chess_engine/ai/engine_config.dart';
import '../../core/chess_engine/local_elephanteye_engine.dart';
import '../../core/chess_engine/move.dart';
import '../../core/chess_engine/move_engine.dart';
import '../../core/constants/piece_constants.dart';
import '../../core/chess_engine/xiangqi_game.dart';

/// One (lower ELO, higher ELO) matchup to benchmark.
class _Pair {
  final int lower;
  final int higher;
  const _Pair(this.lower, this.higher);
}

// 7 adjacent-band pairs covering Zone A (local engines only).
// ELO 2000+ (remotePikafish) is excluded — each move would be a server call.
const List<_Pair> _kPairs = [
  _Pair(1000, 1100), // minimax d1 vs minimax d2
  _Pair(1100, 1200), // minimax d2 blunder 35% vs 22%
  _Pair(1200, 1300), // minimax d2 vs minimax d3
  _Pair(1300, 1400), // minimax d3 blunder 12% vs 5%
  _Pair(1400, 1500), // minimax d3 vs ElephantEye d4  ← junction
  _Pair(1500, 1700), // ElephantEye d4 vs d5
  _Pair(1700, 1900), // ElephantEye d5 vs d6
];

const int _kGamesPerPair = 6; // 3 as red + 3 as black (color-balanced)
const int _kMaxHalfMoves = 300; // 150 full moves → forced draw

/// Accumulated result for one ELO pair.
class PairResult {
  final int lowerElo;
  final int higherElo;
  int lowerWins = 0;
  int higherWins = 0;
  int draws = 0;

  PairResult(this.lowerElo, this.higherElo);

  int get total => lowerWins + higherWins + draws;
  double get lowerWinRate => total == 0 ? 0 : lowerWins / total;
  double get higherWinRate => total == 0 ? 0 : higherWins / total;
  double get drawRate => total == 0 ? 0 : draws / total;
}

/// A single progress event streamed to the UI.
class CalibrationEvent {
  final String log;
  final int pairIndex;
  final int gameIndex;
  final List<PairResult> results;
  final bool done;

  const CalibrationEvent({
    required this.log,
    required this.pairIndex,
    required this.gameIndex,
    required this.results,
    this.done = false,
  });

  static const int totalPairs = 7;
  static const int gamesPerPair = _kGamesPerPair;

  double get progress {
    final completed = pairIndex.clamp(0, totalPairs);
    final gameFraction =
        gamesPerPair > 0 ? (gameIndex / gamesPerPair).clamp(0.0, 1.0) : 0.0;
    return (completed + gameFraction) / totalPairs;
  }
}

/// Runs bot-vs-bot calibration games across Zone A bands.
///
/// Uses [LocalElephantEye] only (no network calls — no quota consumed).
class CalibrationRunner {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  Stream<CalibrationEvent> run() async* {
    _cancelled = false;
    final engine = LocalElephantEye();
    final results = <PairResult>[];

    for (int pi = 0; pi < _kPairs.length; pi++) {
      if (_cancelled) break;
      final pair = _kPairs[pi];
      final result = PairResult(pair.lower, pair.higher);
      results.add(result);

      yield CalibrationEvent(
        log: '── Cặp ${pi + 1}/${_kPairs.length}: ${pair.lower} vs ${pair.higher} ──',
        pairIndex: pi,
        gameIndex: 0,
        results: List.of(results),
      );

      for (int g = 0; g < _kGamesPerPair; g++) {
        if (_cancelled) break;

        // First half: lower plays red. Second half: lower plays black.
        final lowerIsRed = g < _kGamesPerPair ~/ 2;
        final redConfig = configForElo(lowerIsRed ? pair.lower : pair.higher);
        final blackConfig = configForElo(lowerIsRed ? pair.higher : pair.lower);

        yield CalibrationEvent(
          log:
              '  Ván ${g + 1}/$_kGamesPerPair  '
              '${pair.lower}(${lowerIsRed ? "đỏ" : "đen"}) '
              'vs ${pair.higher}(${lowerIsRed ? "đen" : "đỏ"})  đang chạy…',
          pairIndex: pi,
          gameIndex: g,
          results: List.of(results),
        );

        final winner = await _playGame(
          engine: engine,
          redConfig: redConfig,
          blackConfig: blackConfig,
        );

        // Map game winner back to which ELO band won.
        final bool? lowerWon;
        switch (winner) {
          case _Side.red:
            lowerWon = lowerIsRed;
          case _Side.black:
            lowerWon = !lowerIsRed;
          case _Side.draw:
            lowerWon = null;
        }

        if (lowerWon == null) {
          result.draws++;
        } else if (lowerWon) {
          result.lowerWins++;
        } else {
          result.higherWins++;
        }

        final outcomeLabel = lowerWon == null
            ? 'Hòa'
            : lowerWon
            ? '${pair.lower} thắng'
            : '${pair.higher} thắng';

        final pct = result.total > 0
            ? '${(result.lowerWinRate * 100).toStringAsFixed(0)}%'
            : '-';

        yield CalibrationEvent(
          log:
              '    → $outcomeLabel  '
              '[${pair.lower}: ${result.lowerWins}W/'
              '${result.higherWins}L/${result.draws}D  win=$pct]',
          pairIndex: pi,
          gameIndex: g + 1,
          results: List.of(results),
        );
      }
    }

    yield CalibrationEvent(
      log: _cancelled
          ? '\n⛔ Đã huỷ sau ${results.length} cặp.'
          : '\n✅ Hoàn thành ${_kPairs.length} cặp!',
      pairIndex: _kPairs.length,
      gameIndex: _kGamesPerPair,
      results: List.of(results),
      done: true,
    );
  }

  Future<_Side> _playGame({
    required LocalElephantEye engine,
    required EngineConfig redConfig,
    required EngineConfig blackConfig,
  }) async {
    final game = XiangqiGame.initial();
    int halfMoves = 0;

    while (!game.status.isOver && halfMoves < _kMaxHalfMoves) {
      if (_cancelled) break;
      final config = game.turn == PieceColor.red ? redConfig : blackConfig;
      final em = await engine.bestMove(
        game.toFen(),
        level: EngineLevel.hard,
        useCase: EngineUseCase.bot,
        config: config,
      );
      if (em == null) break;
      game.makeMove(em.move.from, em.move.to);
      halfMoves++;
    }

    if (game.status == GameStatus.redWin) return _Side.red;
    if (game.status == GameStatus.blackWin) return _Side.black;
    return _Side.draw;
  }
}

enum _Side { red, black, draw }
