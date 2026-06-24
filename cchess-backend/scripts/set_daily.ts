// Set the featured daily puzzle for a date (daily_puzzles/{YYYY-MM-DD}).
//
// Writes via the Admin SDK (same credentials as import_puzzles.ts).
//
// Usage:
//   npm run puzzles:set-daily -- 2026-06-25 p007     explicit puzzle
//   npm run puzzles:set-daily -- 2026-06-25          auto-pick (published,
//                                                     not used as daily in the
//                                                     last 90 days, easiest-ish)
//   npm run puzzles:set-daily                          auto-pick for today (VN)
//
// Auto-pick is deliberately simple: it pulls published puzzles, drops any whose
// dailyDate is within the last 90 days, and chooses one at pseudo-random seeded
// by the date so re-running for the same day is stable.

import { getFirestore } from 'firebase-admin/firestore';

import { initFirebaseAdmin } from '../src/auth';
import { FirestorePuzzleStore } from '../src/puzzles/puzzle_store';
import { dateKeyVN, isValidDateKey } from '../src/puzzles/types';

const RECENT_DAILY_DAYS = 90;

function daysBetween(a: string, b: string): number {
  return Math.abs((Date.parse(a) - Date.parse(b)) / 86_400_000);
}

/// Deterministic 0..1 from a string (so a given date always picks the same one).
function seededFraction(seed: string): number {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return ((h >>> 0) % 100000) / 100000;
}

async function autoPick(date: string): Promise<string | null> {
  const snap = await getFirestore().collection('puzzles').where('isDraft', '==', false).get();
  const eligible = snap.docs.filter((d) => {
    const dd = d.data().dailyDate;
    return !(typeof dd === 'string' && daysBetween(dd, date) < RECENT_DAILY_DAYS);
  });
  if (eligible.length === 0) return null;
  // Prefer easier puzzles for the daily so casual players engage; sort by
  // difficulty then pick within the easiest third using the date seed.
  eligible.sort((a, b) => (a.data().difficulty ?? 3) - (b.data().difficulty ?? 3));
  const pool = eligible.slice(0, Math.max(1, Math.ceil(eligible.length / 3)));
  return pool[Math.floor(seededFraction(date) * pool.length)].id;
}

async function main(): Promise<void> {
  const argv = process.argv.slice(2);
  const date = argv[0] && isValidDateKey(argv[0]) ? argv[0] : dateKeyVN();
  if (argv[0] && !isValidDateKey(argv[0])) {
    console.error(`Invalid date "${argv[0]}" — expected YYYY-MM-DD`);
    process.exit(1);
  }

  initFirebaseAdmin();
  const store = new FirestorePuzzleStore();

  let puzzleId = argv[1];
  if (!puzzleId) {
    const picked = await autoPick(date);
    if (!picked) {
      console.error(`[set-daily] no eligible puzzle for ${date} (need published puzzles not used in last ${RECENT_DAILY_DAYS}d).`);
      process.exit(1);
    }
    puzzleId = picked;
    console.log(`[set-daily] auto-picked ${puzzleId} for ${date}`);
  }

  await store.setDaily(date, puzzleId);
  console.log(`[set-daily] ${date} → ${puzzleId}`);
}

main().catch((e) => {
  console.error('[set-daily] fatal:', e);
  process.exit(1);
});
