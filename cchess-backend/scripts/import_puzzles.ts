// Bulk-import endgame puzzles into Firestore `puzzles/{id}`.
//
// Writes via the Admin SDK (bypasses security rules), so it needs the same
// service-account credentials the backend uses — see src/auth.ts for the
// lookup order (FIREBASE_SERVICE_ACCOUNT_JSON, GOOGLE_APPLICATION_CREDENTIALS,
// ./serviceAccount.json, or ADC).
//
// Usage:
//   npm run puzzles:import -- scripts/puzzles.seed.json
//   npm run puzzles:import -- path/to/batch.json --publish   (force isDraft=false)
//   npm run puzzles:import -- path/to/batch.json --dry-run    (validate only)
//
// The JSON file is either an array of puzzles or { "puzzles": [...] }. Each item
// is validated (FEN shape, UCI moves, title, difficulty) before any write; with
// --dry-run nothing is written and only the validation report is printed.

import { readFileSync } from 'fs';
import { resolve } from 'path';

import { initFirebaseAdmin } from '../src/auth';
import { FirestorePuzzleStore } from '../src/puzzles/puzzle_store';
import { validatePuzzleInput, type PuzzleInput } from '../src/puzzles/types';

interface Args {
  file: string;
  dryRun: boolean;
  publish: boolean;
}

function parseArgs(argv: string[]): Args {
  const positional: string[] = [];
  let dryRun = false;
  let publish = false;
  for (const arg of argv) {
    if (arg === '--dry-run') dryRun = true;
    else if (arg === '--publish') publish = true;
    else positional.push(arg);
  }
  if (positional.length === 0) {
    console.error('Usage: npm run puzzles:import -- <file.json> [--publish] [--dry-run]');
    process.exit(1);
  }
  return { file: positional[0], dryRun, publish };
}

function loadPuzzles(file: string): unknown[] {
  const text = readFileSync(resolve(process.cwd(), file), 'utf-8');
  const parsed = JSON.parse(text);
  if (Array.isArray(parsed)) return parsed;
  if (Array.isArray(parsed?.puzzles)) return parsed.puzzles;
  throw new Error('JSON must be an array or { "puzzles": [...] }');
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const raw = loadPuzzles(args.file);
  console.log(`[import] ${raw.length} puzzle(s) from ${args.file}`);

  // Validate everything first so a bad item doesn't leave a half-written batch.
  const valid: PuzzleInput[] = [];
  const errors: { index: number; message: string }[] = [];
  raw.forEach((item, index) => {
    try {
      const input = validatePuzzleInput(item);
      if (args.publish) input.isDraft = false;
      valid.push(input);
    } catch (e) {
      errors.push({ index, message: e instanceof Error ? e.message : String(e) });
    }
  });

  if (errors.length > 0) {
    console.error(`[import] ${errors.length} invalid item(s):`);
    for (const e of errors) console.error(`  #${e.index}: ${e.message}`);
  }
  console.log(`[import] ${valid.length} valid, ${errors.length} invalid`);

  if (args.dryRun) {
    console.log('[import] --dry-run: nothing written.');
    return;
  }
  if (valid.length === 0) {
    console.log('[import] nothing to write.');
    return;
  }

  initFirebaseAdmin();
  const store = new FirestorePuzzleStore();
  let written = 0;
  for (const input of valid) {
    const doc = await store.upsert(input);
    written++;
    console.log(`  ✓ ${doc.id} — ${doc.titleVi} (★${doc.difficulty})`);
  }
  console.log(`[import] done: ${written} written, ${errors.length} skipped.`);
}

main().catch((e) => {
  console.error('[import] fatal:', e);
  process.exit(1);
});
