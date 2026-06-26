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
///   * Pikafish      → [skillLevel] / [uciElo] + [movetimeMs] ([depth] is the
///     fallback search depth used if the remote call has to be served locally).
class EngineConfig {
  /// Which engine plays this ELO band.
  final EngineSource engine;

  /// Search depth in plies. Interpreted by [engine]: minimax ply for
  /// [EngineSource.localMinimax], native ply for [EngineSource.localElephantEye],
  /// fallback ply for [EngineSource.remotePikafish].
  final int depth;

  /// Move-time budget in milliseconds (Pikafish bands only).
  final int? movetimeMs;

  /// Pikafish `Skill Level` (0–20). Null for the local engines.
  final int? skillLevel;

  /// Pikafish `UCI_Elo` when `UCI_LimitStrength` is enabled. Null for the
  /// local engines.
  final int? uciElo;

  /// Probability (0..1) of throwing in a deliberately random move. Only the
  /// low minimax band uses this to feel beatable; 0 everywhere else.
  final double blunderRate;

  const EngineConfig({
    required this.engine,
    required this.depth,
    this.movetimeMs,
    this.skillLevel,
    this.uciElo,
    this.blunderRate = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is EngineConfig &&
      other.engine == engine &&
      other.depth == depth &&
      other.movetimeMs == movetimeMs &&
      other.skillLevel == skillLevel &&
      other.uciElo == uciElo &&
      other.blunderRate == blunderRate;

  @override
  int get hashCode =>
      Object.hash(engine, depth, movetimeMs, skillLevel, uciElo, blunderRate);

  @override
  String toString() =>
      'EngineConfig(${engine.name}, depth: $depth, movetimeMs: $movetimeMs, '
      'skill: $skillLevel, uciElo: $uciElo, blunder: $blunderRate)';
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
  // 2600–2900+ : Pikafish near / full strength.
  _Band(
    2800,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 14,
      movetimeMs: 1500,
      skillLevel: 20,
      uciElo: 2850,
    ),
  ),
  _Band(
    2600,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 12,
      movetimeMs: 1000,
      skillLevel: 18,
      uciElo: 2650,
    ),
  ),
  // 2000–2600 : Pikafish, strength-limited.
  _Band(
    2400,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 10,
      movetimeMs: 600,
      skillLevel: 14,
      uciElo: 2450,
    ),
  ),
  _Band(
    2200,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 9,
      movetimeMs: 400,
      skillLevel: 10,
      uciElo: 2250,
    ),
  ),
  _Band(
    2000,
    EngineConfig(
      engine: EngineSource.remotePikafish,
      depth: 8,
      movetimeMs: 250,
      skillLevel: 6,
      uciElo: 2050,
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
