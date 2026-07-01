// Pure single-elimination bracket algorithm (C4). Deliberately Firestore-free
// so it can be unit tested directly without a fake store or emulator — the
// store (tournament_store.ts) just persists whatever this produces.

import type { MatchDoc, MatchSlot } from './types';

export function nextPowerOfTwo(n: number): number {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

/// Build every round's matches for a single-elimination bracket over
/// `participantUids` (already in the order they should be seeded — callers
/// that want random seeding shuffle before calling this). Round-1 byes (when
/// `participantUids.length` isn't a power of two) are resolved immediately:
/// the lone present player is advanced into the next round right away, so the
/// caller never has to run a separate "process byes" pass.
///
/// Byes are placed one-per-pair, never two-per-pair: since `bracketSize` is
/// the smallest power of two ≥ n, byeCount = bracketSize - n is always
/// strictly less than half = bracketSize / 2, so there are always at least
/// `half - byeCount` fully-real pairs to soak up the non-bye players first.
export function generateBracket(participantUids: string[]): MatchDoc[] {
  const n = participantUids.length;
  if (n < 2) {
    throw new Error('generateBracket requires at least 2 participants');
  }
  const bracketSize = nextPowerOfTwo(n);
  const totalRounds = Math.log2(bracketSize);
  const half = bracketSize / 2;
  const byeCount = bracketSize - n;
  const fullPairs = half - byeCount;

  const matchesByRound: MatchDoc[][] = [];
  for (let r = 1; r <= totalRounds; r++) {
    const count = bracketSize / 2 ** r;
    const round: MatchDoc[] = [];
    for (let i = 0; i < count; i++) {
      round.push({
        id: `r${r}_m${i}`,
        round: r,
        slotIndex: i,
        player1Id: null,
        player2Id: null,
        result: null,
        roomId: null,
        status: 'pending',
        nextMatchId: r < totalRounds ? `r${r + 1}_m${Math.floor(i / 2)}` : null,
        nextMatchSlot: r < totalRounds ? ((i % 2 === 0 ? 'player1' : 'player2') as MatchSlot) : null,
        createdAtMs: null,
        finishedAtMs: null,
      });
    }
    matchesByRound.push(round);
  }
  const all = matchesByRound.flat();
  const byId = new Map(all.map((m) => [m.id, m]));

  const round1 = matchesByRound[0];
  let idx = 0;
  for (let i = 0; i < round1.length; i++) {
    const m = round1[i];
    m.player1Id = participantUids[idx++] ?? null;
    if (i < fullPairs) {
      m.player2Id = participantUids[idx++] ?? null;
      m.status = 'ready';
    } else {
      m.player2Id = null;
      m.result = 'bye';
      m.status = 'finished';
      advanceWinner(m, m.player1Id!, byId);
    }
  }
  return all;
}

/// Write `winnerUid` into the next match's slot (if any) and flip it to
/// 'ready' once both its slots are filled. Non-recursive: filling a round-2+
/// slot never itself constitutes a bye (a null slot there just means "still
/// waiting on the sibling match"), so there's nothing further to cascade.
function advanceWinner(match: MatchDoc, winnerUid: string, byId: Map<string, MatchDoc>): void {
  if (!match.nextMatchId || !match.nextMatchSlot) return;
  const next = byId.get(match.nextMatchId);
  if (!next) return;
  if (match.nextMatchSlot === 'player1') next.player1Id = winnerUid;
  else next.player2Id = winnerUid;
  if (next.player1Id && next.player2Id) next.status = 'ready';
}

export interface ApplyMatchResultOutcome {
  matches: MatchDoc[];
  /// True only when this call just decided the tournament (the final match).
  tournamentFinished: boolean;
  winnerUid: string | null;
  /// True if the match was already finished — caller should treat this as a
  /// no-op (idempotent retry), not apply anything.
  alreadyFinished: boolean;
}

/// Apply a match outcome to a bracket snapshot, returning a NEW matches array
/// (does not mutate the input) plus whether the tournament just finished.
/// A draw resets the match to 'ready' with no roomId (replay required) and
/// does not advance anyone — single-elimination has no draws.
export function applyMatchResult(
  matches: MatchDoc[],
  matchId: string,
  outcome: { winnerUid: string } | { draw: true },
): ApplyMatchResultOutcome {
  const byId = new Map(matches.map((m) => [m.id, { ...m }]));
  const match = byId.get(matchId);
  if (!match) throw new Error('match-not-found');

  if (match.status === 'finished') {
    return { matches: [...byId.values()], tournamentFinished: false, winnerUid: null, alreadyFinished: true };
  }

  if ('draw' in outcome) {
    match.status = 'ready';
    match.roomId = null;
    return { matches: [...byId.values()], tournamentFinished: false, winnerUid: null, alreadyFinished: false };
  }

  const winnerUid = outcome.winnerUid;
  if (winnerUid !== match.player1Id && winnerUid !== match.player2Id) {
    throw new Error('invalid-winner');
  }
  match.result = winnerUid === match.player1Id ? 'player1' : 'player2';
  match.status = 'finished';
  match.finishedAtMs = Date.now();

  let tournamentFinished = false;
  let championUid: string | null = null;
  if (match.nextMatchId && match.nextMatchSlot) {
    const next = byId.get(match.nextMatchId);
    if (next) {
      if (match.nextMatchSlot === 'player1') next.player1Id = winnerUid;
      else next.player2Id = winnerUid;
      if (next.player1Id && next.player2Id) next.status = 'ready';
    }
  } else {
    tournamentFinished = true;
    championUid = winnerUid;
  }

  return { matches: [...byId.values()], tournamentFinished, winnerUid: championUid, alreadyFinished: false };
}

/// The other player in a 2-player match (or null for a bye/incomplete match).
export function loserOf(match: MatchDoc, winnerUid: string): string | null {
  if (match.player1Id === winnerUid) return match.player2Id;
  if (match.player2Id === winnerUid) return match.player1Id;
  return null;
}
