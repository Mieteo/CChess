export interface UciInfo {
  depth?: number;
  scoreCp?: number;
  pv?: string[];
}

export function parseInfoLine(line: string): UciInfo | null {
  if (!line.startsWith('info ')) return null;
  const info: UciInfo = {};

  const depth = /\bdepth\s+(\d+)/.exec(line);
  if (depth) info.depth = Number.parseInt(depth[1], 10);

  const score = /\bscore\s+(cp|mate)\s+(-?\d+)/.exec(line);
  if (score) {
    const raw = Number.parseInt(score[2], 10);
    info.scoreCp = score[1] === 'mate' ? mateToCp(raw) : raw;
  }

  const pv = /\bpv\s+(.+)$/.exec(line);
  if (pv) {
    info.pv = pv[1]
      .trim()
      .split(/\s+/)
      .filter((move) => /^[a-i][0-9][a-i][0-9]$/.test(move));
  }

  return Object.keys(info).length === 0 ? null : info;
}

export function parseBestMoveLine(line: string): string | null | undefined {
  const match = /^bestmove\s+(\S+)/.exec(line);
  if (!match) return undefined;
  const move = match[1].toLowerCase();
  if (move === '(none)' || move === '0000') return null;
  return /^[a-i][0-9][a-i][0-9]$/.test(move) ? move : null;
}

function mateToCp(pliesToMate: number): number {
  const sign = pliesToMate < 0 ? -1 : 1;
  const distancePenalty = Math.min(Math.abs(pliesToMate), 1000);
  return sign * (100_000 - distancePenalty);
}
