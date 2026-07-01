import { Board } from '../engine/board';
import { INITIAL_FEN } from '../engine/piece';
import { EngineServiceError, type EngineLimit } from './types';

export const UCI_REGEX = /^[a-i][0-9][a-i][0-9]$/;

export function normalizeFen(raw: unknown, fallback = INITIAL_FEN): string {
  const input = typeof raw === 'string' && raw.trim().length > 0
    ? raw.trim()
    : fallback;
  const parts = input.split(/\s+/);
  const placement = parts[0] ?? '';
  try {
    Board.fromFen(placement);
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    throw new EngineServiceError(400, 'invalid-fen', message);
  }

  const side = parts[1] === 'b' ? 'b' : 'w';
  const halfmove = parseNonNegativeInt(parts[4], 0);
  const fullmove = Math.max(1, parseNonNegativeInt(parts[5], 1));
  return `${placement} ${side} - - ${halfmove} ${fullmove}`;
}

export function normalizeUci(raw: unknown): string {
  if (typeof raw !== 'string') {
    throw new EngineServiceError(400, 'invalid-uci', 'UCI move must be a string');
  }
  const uci = raw.trim().toLowerCase();
  if (!UCI_REGEX.test(uci)) {
    throw new EngineServiceError(400, 'invalid-uci', `Invalid Xiangqi UCI move: ${raw}`);
  }
  return uci;
}

export function bestMoveCacheKey(fen: string, limit: EngineLimit): string {
  const depth = limit.depth === undefined ? '' : `d${limit.depth}`;
  const movetime = limit.movetimeMs === undefined ? '' : `m${limit.movetimeMs}`;
  // blunderRate is intentionally NOT part of this key — callers must bypass
  // the cache entirely when it's set (see server.ts cachedBestMove) since a
  // blunder roll makes the result non-deterministic for a given fen+limit.
  return `${fen}|${depth}|${movetime}`;
}

function parseNonNegativeInt(raw: string | undefined, fallback: number): number {
  if (raw === undefined) return fallback;
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) && value >= 0 ? value : fallback;
}
