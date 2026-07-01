import '../move_engine.dart' show EngineSource;

/// Lower / upper bounds of the bot ELO ladder.
///
/// [configForElo] clamps its input to this range and the matchmaker clamps
/// every generated match inside it, so no code path can ask for a bot weaker
/// than [kMinBotElo] or stronger than [kMaxBotElo].
const int kMinBotElo = 1000;
const int kMaxBotElo = 2900;

/// A concrete engine "strength dial" for a single target ELO.
///
/// This is the one knob the rest of the bot system turns: instead of hand-
/// crafting a bot per rank, [configForElo] maps any ELO onto one of these.
/// Each backing engine reads only the fields it understands:
///   * minimax       → [depth] + [blunderRate];
///   * ElephantEye   → [depth] (native search ply);
///   * Pikafish      → [movetimeMs] + [blunderRate] ([depth] is the fallback
///     search depth used if the remote call has to be served locally).
///
/// Note: Pikafish has no native strength dial — the official release has no
/// `UCI_LimitStrength`/`UCI_Elo`/`Skill Level` option (confirmed against the
/// real binary; unknown-option `setoption` calls are silently ignored). So
/// Pikafish bands lean on [blunderRate] too, same as minimax: the backend
/// raises `MultiPV` and occasionally plays a weaker candidate line instead of
/// the engine's actual best move (see `cchess-backend/engine-service/uci_engine.ts`).
class EngineConfig {
  /// Which engine plays this ELO band.
  final EngineSource engine;

  /// Search depth in plies. Interpreted by [engine]: minimax ply for
  /// [EngineSource.localMinimax], native ply for [EngineSource.localElephantEye],
  /// fallback ply for [EngineSource.remotePikafish].
  final int depth;

  /// Move-time budget in milliseconds (Pikafish bands only).
  final int? movetimeMs;

  /// Probability (0..1) of deliberately playing a weaker move instead of the
  /// engine's actual best move. Minimax throws in a random legal move;
  /// Pikafish (via the backend) plays a weaker MultiPV alternate. 0 means
  /// always play the engine's best move.
  final double blunderRate;

  const EngineConfig({
    required this.engine,
    required this.depth,
    this.movetimeMs,
    this.blunderRate = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is EngineConfig &&
      other.engine == engine &&
      other.depth == depth &&
      other.movetimeMs == movetimeMs &&
      other.blunderRate == blunderRate;

  @override
  int get hashCode => Object.hash(engine, depth, movetimeMs, blunderRate);

  @override
  String toString() =>
      'EngineConfig(${engine.name}, depth: $depth, movetimeMs: $movetimeMs, '
      'blunder: $blunderRate)';
}

/// One ELO band → its [EngineConfig]. [minElo] is the inclusive lower edge.
class _Band {
  final int minElo;
  final EngineConfig config;
  const _Band(this.minElo, this.config);
}

/// The strength ladder, ordered strongest → weakest. [configForElo] walks it
/// top-down and returns the first band whose [minElo] the (clamped) ELO meets.
///
/// Numbers below are a *starting point only* — engine self-reported ELO is very
/// unreliable in Xiangqi, so the bands must be re-calibrated against known
/// opponents (doc 13, Phase 6). Keep this table monotonic: a higher ELO must
/// never map to a weaker config.
const List<_Band> _ladder = [
  // 2600–2900+ : Pikafish near / full strength — top band blunders are 0,
  // it's exactly as strong as the real engine's movetime budget allows.
  _Band(
    2800,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 14,
      movetimeMs: 1500,
      blunderRate: 0,
    ),
  ),
  _Band(
    2600,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 12,
      movetimeMs: 1000,
      blunderRate: 0.02,
    ),
  ),
  // 2000–2600 : Pikafish, weakened via occasional MultiPV-alternate blunders
  // (see EngineConfig doc — Pikafish has no native strength dial).
  _Band(
    2400,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 10,
      movetimeMs: 600,
      blunderRate: 0.05,
    ),
  ),
  _Band(
    2200,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 9,
      movetimeMs: 400,
      blunderRate: 0.08,
    ),
  ),
  _Band(
    2000,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 8,
      movetimeMs: 250,
      blunderRate: 0.12,
    ),
  ),
  // 1400–2000 : minimax (deep) / ElephantEye native search.
  _Band(1900, EngineConfig(engine: EngineSource.localElephantEye, depth: 6)),
  _Band(1700, EngineConfig(engine: EngineSource.localElephantEye, depth: 5)),
  _Band(1500, EngineConfig(engine: EngineSource.localElephantEye, depth: 4)),
  // 1000–1400 : minimax with a shrinking blunder rate (Pikafish here feels
  // robotic; a noisy minimax is more human and beatable).
  _Band(
    1400,
    EngineConfig(
      engine: EngineSource.localMinimax,
      depth: 3,
      blunderRate: 0.05,
    ),
  ),
  _Band(
    1300,
    EngineConfig(
      engine: EngineSource.localMinimax,
      depth: 3,
      blunderRate: 0.12,
    ),
  ),
  _Band(
    1200,
    EngineConfig(
      engine: EngineSource.localMinimax,
      depth: 2,
      blunderRate: 0.22,
    ),
  ),
  _Band(
    1100,
    EngineConfig(
      engine: EngineSource.localMinimax,
      depth: 2,
      blunderRate: 0.35,
    ),
  ),
  _Band(
    kMinBotElo,
    EngineConfig(
      engine: EngineSource.localMinimax,
      depth: 1,
      blunderRate: 0.50,
    ),
  ),
];

/// Map any target ELO onto a concrete [EngineConfig].
///
/// The input is clamped to `[kMinBotElo, kMaxBotElo]` first, so out-of-range
/// values (e.g. a brand-new player below 1000) still return a sensible config.
EngineConfig configForElo(int targetElo) {
  final elo = targetElo.clamp(kMinBotElo, kMaxBotElo);
  for (final band in _ladder) {
    if (elo >= band.minElo) return band.config;
  }
  // Unreachable: the last band's minElo == kMinBotElo == the clamp floor.
  return _ladder.last.config;
}
