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
