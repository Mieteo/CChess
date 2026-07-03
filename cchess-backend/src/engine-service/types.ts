export type EngineFeature = 'best-move' | 'hint' | 'analyze';

export type MoveClassification =
  | 'best'
  | 'excellent'
  | 'good'
  | 'inaccuracy'
  | 'mistake'
  | 'blunder';

export interface EngineLimit {
  movetimeMs?: number;
  depth?: number;
  timeoutMs?: number;
  /** Probability (0..1) of deliberately playing a weaker MultiPV alternate
   * instead of Pikafish's actual best move. Pikafish has no native strength
   * dial (no `UCI_LimitStrength`/`UCI_Elo`/`Skill Level`), so the ELO ladder's
   * 2000-2900 bands use this — the same blunder-band idea as the local
   * minimax engine — instead. */
  blunderRate?: number;
}

export interface EngineBestMove {
  uci: string | null;
  scoreCp: number | null;
  depth: number | null;
  pv: string[];
  cached?: boolean;
}

export interface EngineBestMoveRequest {
  fen: string;
  level?: string;
  movetimeMs?: number;
  depth?: number;
  /** ELO-ladder blunder probability (0..1) — see EngineLimit.blunderRate. */
  blunderRate?: number;
}

export interface EngineAnalyzeRequest {
  startingFen?: string;
  fen?: string;
  moves?: string[];
  movesUci?: string[];
  movetimeMs?: number;
  depth?: number;
}

export interface EngineAnalyzeMove {
  moveIndex: number;
  uci: string;
  bestUci: string | null;
  scoreCp: number | null;
  actualScoreCp: number | null;
  /** Eval of the position AFTER this move, RED-positive centipawns (the eval
   * chart series). Mate scores use ±(30000 − pliesToMate); a finished game
   * scores ±29999 (or 0 for a draw). Null when the engine gave no score. */
  evalAfterCp: number | null;
  centipawnLoss: number;
  classification: MoveClassification;
  depth: number | null;
}

export interface EngineAnalyzeResult {
  perMove: EngineAnalyzeMove[];
  summary: {
    redAccuracy: number;
    blackAccuracy: number;
    redBlunders: number;
    blackBlunders: number;
    redMistakes: number;
    blackMistakes: number;
  };
}

export type AnalyzeJobStatus = 'queued' | 'running' | 'done' | 'error';

/** What GET /engine/analyze-jobs/:id returns while a job is queued/running/
 * finished. `perMove` grows as moves are graded so the client can render
 * partial results and real progress. */
export interface AnalyzeJobSnapshot {
  jobId: string;
  status: AnalyzeJobStatus;
  totalMoves: number;
  completedMoves: number;
  /** 0..1 — completedMoves / totalMoves. */
  progress: number;
  perMove: EngineAnalyzeMove[];
  summary?: EngineAnalyzeResult['summary'];
  error?: { code: string; message: string };
}

export class EngineServiceError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
    public readonly expose = true,
  ) {
    super(message);
    this.name = 'EngineServiceError';
  }
}
