import '../../core/chess_engine/ai/engine_config.dart';
import '../../core/chess_engine/local_elephanteye_engine.dart';
import '../../core/chess_engine/move.dart';
import '../../core/chess_engine/move_engine.dart';
import '../../core/constants/piece_constants.dart';
import '../../core/chess_engine/xiangqi_game.dart';

/// One (lower ELO, higher ELO) matchup to benchmark.
class CalibrationPair {
  final int lower;
  final int higher;
  const CalibrationPair(this.lower, this.higher);

  /// Short label for a button, e.g. "1000 → 1100".
  String get label => '$lower → $higher';
}

// 7 adjacent-band pairs covering Zone A (local engines only).
// ELO 2000+ (remotePikafish) is excluded — each move would be a server call.
const List<CalibrationPair> kCalibrationPairs = [
  CalibrationPair(1000, 1100), // minimax d1 vs minimax d2
  CalibrationPair(1100, 1200), // minimax d2 blunder 35% vs 22%
  CalibrationPair(1200, 1300), // minimax d2 vs minimax d3
  CalibrationPair(1300, 1400), // minimax d3 blunder 12% vs 5%
  CalibrationPair(1400, 1500), // minimax d3 vs ElephantEye d4  ← junction
  CalibrationPair(1500, 1700), // ElephantEye d4 vs d5
  CalibrationPair(1700, 1900), // ElephantEye d5 vs d6
];

const int kGamesPerPair = 6; // 3 as red + 3 as black (color-balanced)
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

/// A single progress event streamed to the UI for one pair run.
class CalibrationEvent {
  final String log;

  /// Index into [kCalibrationPairs] of the pair being run.
  final int pairIndex;

  /// Accumulated result for the pair being run.
  final PairResult result;

  /// Completion of the current pair, 0.0 → 1.0.
  final double progress;

  final bool done;

  const CalibrationEvent({
    required this.log,
    required this.pairIndex,
    required this.result,
    required this.progress,
    this.done = false,
  });
}

/// Runs bot-vs-bot calibration games across Zone A bands.
///
/// Uses [LocalElephantEye] only (no network calls — no quota consumed).
class CalibrationRunner {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Runs the single ELO pair at [pairIndex] in [kCalibrationPairs].
  ///
  /// The UI runs these one at a time (one button per pair) so the phone's
  /// CPU never has two calibration matches competing for it.
  Stream<CalibrationEvent> runPair(int pairIndex) async* {
    _cancelled = false;
    final engine = LocalElephantEye();
    final pair = kCalibrationPairs[pairIndex];
    final result = PairResult(pair.lower, pair.higher);

    yield CalibrationEvent(
      log:
          '── Cặp ${pairIndex + 1}/${kCalibrationPairs.length}: '
          '${pair.lower} vs ${pair.higher} ──',
      pairIndex: pairIndex,
      result: result,
      progress: 0,
    );

    for (int g = 0; g < kGamesPerPair; g++) {
      if (_cancelled) break;

      // First half: lower plays red. Second half: lower plays black.
      final lowerIsRed = g < kGamesPerPair ~/ 2;
      final redConfig = configForElo(lowerIsRed ? pair.lower : pair.higher);
      final blackConfig = configForElo(lowerIsRed ? pair.higher : pair.lower);

      yield CalibrationEvent(
        log:
            '  Ván ${g + 1}/$kGamesPerPair  '
            '${pair.lower}(${lowerIsRed ? "đỏ" : "đen"}) '
            'vs ${pair.higher}(${lowerIsRed ? "đen" : "đỏ"})  đang chạy…',
        pairIndex: pairIndex,
        result: result,
        progress: g / kGamesPerPair,
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
        pairIndex: pairIndex,
        result: result,
        progress: (g + 1) / kGamesPerPair,
      );
    }

    yield CalibrationEvent(
      log: _cancelled
          ? '⛔ Đã huỷ cặp ${pair.lower} vs ${pair.higher}.'
          : '✅ Hoàn thành cặp ${pair.lower} vs ${pair.higher}!',
      pairIndex: pairIndex,
      result: result,
      progress: 1,
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
