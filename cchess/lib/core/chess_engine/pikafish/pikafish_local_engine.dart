import 'dart:async';
import 'dart:math';

import '../../constants/piece_constants.dart';
import '../ai/engine_config.dart';
import '../ai/game_analyzer.dart';
import '../move.dart';
import '../move_engine.dart';
import '../xiangqi_game.dart';
import 'uci_client.dart';

/// Everything needed to boot the offline engine: where the binary lives and
/// where the NNUE network file was installed.
class PikafishRuntime {
  final String binaryPath;
  final String nnuePath;

  /// Threads the engine may use. Callers size this off the device
  /// (see `pikafish_support_io.dart`); tests pass 1.
  final int threads;

  const PikafishRuntime({
    required this.binaryPath,
    required this.nnuePath,
    this.threads = 1,
  });
}

/// Resolves the runtime, or null when the device can't run offline Pikafish
/// (unsupported platform, missing binary, NNUE not downloaded yet).
typedef PikafishRuntimeResolver = Future<PikafishRuntime?> Function();

/// Boots a transport for the resolved runtime (spawns the child process).
typedef PikafishTransportFactory = Future<UciTransport> Function(
  PikafishRuntime runtime,
);

/// Thrown when offline Pikafish is asked to work but isn't installed/usable.
class PikafishUnavailableException implements Exception {
  final String message;
  PikafishUnavailableException(this.message);
  @override
  String toString() => 'PikafishUnavailableException: $message';
}

/// Offline Pikafish running as a UCI child process on the user's device.
///
/// Mirrors the server engine-service semantics so the router can swap them
/// freely: full-strength for hint/analysis, MultiPV blunder dial for ELO-band
/// bot play, and the same centipawn-loss classification for [analyze]. The
/// child process is started lazily on first use and reused afterwards; if it
/// dies it is restarted on the next request.
class PikafishLocalEngine implements MoveEngine {
  PikafishLocalEngine({
    required PikafishRuntimeResolver resolveRuntime,
    required PikafishTransportFactory startTransport,
    this.hashMb = 64,
    this.analysisMovetimeMs = 300,
    int? seed,
  })  : _resolveRuntime = resolveRuntime,
        _startTransport = startTransport,
        _random = Random(seed);

  final PikafishRuntimeResolver _resolveRuntime;
  final PikafishTransportFactory _startTransport;
  final int hashMb;

  /// Per-position budget for [analyze] — matches the server's
  /// ANALYZE_MOVETIME_MS default so grades stay comparable.
  final int analysisMovetimeMs;

  final Random _random;
  UciClient? _client;
  Future<UciClient>? _starting;

  /// MultiPV width used when a blunder roll needs weaker candidate lines —
  /// same as the backend's uci_engine.ts.
  static const int _blunderMultiPv = 4;
  static const int _cpLossCap = 1000;

  /// Quick probe: can this engine serve requests right now?
  Future<bool> isAvailable() async => (await _resolveRuntime()) != null;

  @override
  Future<EngineMove?> bestMove(
    String fen, {
    required EngineLevel level,
    EngineUseCase useCase = EngineUseCase.bot,
    EngineConfig? config,
  }) async {
    final client = await _ensureStarted();
    final blunderRate =
        useCase == EngineUseCase.bot ? (config?.blunderRate ?? 0) : 0.0;
    final multiPv = blunderRate > 0 ? _blunderMultiPv : 1;

    final result = await client.search(
      fen: fen,
      movetimeMs: _movetimeFor(level, useCase, config),
      multiPv: multiPv,
    );
    if (result.bestUci == null) return null;

    var uci = result.bestUci!;
    UciPvLine? line = result.best;
    if (blunderRate > 0 &&
        result.pvLines.length > 1 &&
        _random.nextDouble() < blunderRate) {
      // Deliberately play a weaker candidate (multipv 2..N), like the server.
      final alternates =
          result.pvLines.where((l) => l.multipv != 1).toList();
      final pick = alternates[_random.nextInt(alternates.length)];
      if (pick.firstMove != null) {
        uci = pick.firstMove!;
        line = pick;
      }
    }

    final move = _moveFromUci(fen, uci);
    if (move == null) return null;
    return EngineMove(
      move: move,
      uci: uci,
      scoreCp: line?.score.toCp(),
      depth: line?.depth,
      source: EngineSource.localPikafish,
    );
  }

  @override
  Future<GameAnalysis> analyze({
    required String startingFen,
    required List<String> moveUcis,
  }) async {
    final client = await _ensureStarted();
    final game = XiangqiGame.fromFen(startingFen);
    final analyses = <MoveAnalysis>[];

    // One search per *position* (not two per move): the eval after move i is
    // exactly the eval before move i+1, so a game of N moves costs N+1
    // searches and the eval series is self-consistent by construction.
    UciSearchResult? current = await client.search(
      fen: game.toFen(),
      movetimeMs: analysisMovetimeMs,
    );

    for (var i = 0; i < moveUcis.length; i++) {
      final coords = Move.parseUciCoords(moveUcis[i]);
      if (coords == null) break;
      final (from, to) = coords;
      final piece = game.board.at(from);
      if (piece == null || !game.isValidMove(from, to)) break;

      final mover = game.turn;
      final bestCp = current?.best?.score.toCp() ?? 0; // mover perspective
      final recommended = _recommendedMove(game, current?.bestUci);
      final actualMove = Move(
        from: from,
        to: to,
        moved: piece,
        captured: game.board.at(to),
      );

      game.makeMove(from, to);

      int actualCp; // mover perspective, after the played move
      UciSearchResult? next;
      if (game.status.isOver) {
        actualCp = _terminalScore(game, mover);
      } else {
        next = await client.search(
          fen: game.toFen(),
          movetimeMs: analysisMovetimeMs,
        );
        // `next` scores are opponent-to-move relative — negate for the mover.
        actualCp = -(next.best?.score.toCp() ?? 0);
      }

      var loss = bestCp - actualCp;
      if (loss < 0) loss = 0;
      if (loss > _cpLossCap) loss = _cpLossCap;

      final isBest = current?.bestUci == moveUcis[i];
      analyses.add(
        MoveAnalysis(
          moveIndex: i,
          move: actualMove,
          mover: mover,
          recommendedMove: recommended,
          bestEval: mover == PieceColor.red ? bestCp : -bestCp,
          actualEval: mover == PieceColor.red ? actualCp : -actualCp,
          centipawnLoss: loss,
          quality: _classify(loss, isBestMove: isBest),
        ),
      );

      if (game.status.isOver) break;
      current = next;
    }

    return GameAnalysis.aggregate(analyses);
  }

  Future<void> dispose() async {
    final client = _client;
    _client = null;
    _starting = null;
    await client?.dispose();
  }

  // ── Internals ──────────────────────────────────────────────────────────

  Future<UciClient> _ensureStarted() {
    final existing = _client;
    if (existing != null && existing.isAlive) return Future.value(existing);
    // A dead client (engine crashed) is replaced transparently.
    return _starting ??= _startFresh().whenComplete(() => _starting = null);
  }

  Future<UciClient> _startFresh() async {
    await _client?.dispose();
    _client = null;

    final runtime = await _resolveRuntime();
    if (runtime == null) {
      throw PikafishUnavailableException(
        'Offline Pikafish is not installed on this device',
      );
    }
    final transport = await _startTransport(runtime);
    final client = UciClient(transport);
    await client.start(
      options: {
        'Threads': '${runtime.threads.clamp(1, 8)}',
        'Hash': '$hashMb',
        'EvalFile': runtime.nnuePath,
      },
    );
    _client = client;
    return client;
  }

  int _movetimeFor(
    EngineLevel level,
    EngineUseCase useCase,
    EngineConfig? config,
  ) {
    if (useCase == EngineUseCase.analysis) return analysisMovetimeMs;
    if (useCase == EngineUseCase.hint) return 500;
    if (config?.movetimeMs != null) return config!.movetimeMs!;
    switch (level) {
      case EngineLevel.grandmaster:
        return 1200;
      case EngineLevel.hard:
      case EngineLevel.veryHard:
        return 800;
      case EngineLevel.veryEasy:
      case EngineLevel.easy:
      case EngineLevel.medium:
        return 600;
    }
  }

  /// Mover-perspective score for a game that just ended with the mover's move.
  int _terminalScore(XiangqiGame game, PieceColor mover) {
    switch (game.status) {
      case GameStatus.redWin:
        return mover == PieceColor.red ? 29999 : -29999;
      case GameStatus.blackWin:
        return mover == PieceColor.black ? 29999 : -29999;
      case GameStatus.draw:
      case GameStatus.playing:
        return 0;
    }
  }

  Move? _moveFromUci(String fen, String uci) {
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final game = XiangqiGame.fromFen(fen);
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    return Move(from: from, to: to, moved: piece, captured: game.board.at(to));
  }

  Move? _recommendedMove(XiangqiGame game, String? uci) {
    if (uci == null) return null;
    final coords = Move.parseUciCoords(uci);
    if (coords == null) return null;
    final (from, to) = coords;
    final piece = game.board.at(from);
    if (piece == null) return null;
    return Move(from: from, to: to, moved: piece, captured: game.board.at(to));
  }

  static MoveQuality _classify(int cpLoss, {required bool isBestMove}) {
    if (isBestMove) return MoveQuality.best;
    if (cpLoss <= 15) return MoveQuality.excellent;
    if (cpLoss <= 60) return MoveQuality.good;
    if (cpLoss <= 150) return MoveQuality.inaccuracy;
    if (cpLoss <= 300) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }
}
