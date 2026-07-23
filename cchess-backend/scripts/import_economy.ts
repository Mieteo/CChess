// Bulk-import S16 economy content into Firestore: seasonal events into
// `events/{id}` and craft recipes into `craft_recipes/{id}`.
//
// Writes via the Admin SDK (bypasses security rules), so it needs the same
// service-account credentials the backend uses — see src/auth.ts for the lookup
// order (FIREBASE_SERVICE_ACCOUNT_JSON, GOOGLE_APPLICATION_CREDENTIALS,
// ./serviceAccount.json, or ADC).
//
// Usage:
//   npm run economy:import -- scripts/economy.seed.json
//   npm run economy:import -- path/to/batch.json --dry-run   (validate only)
//
// The JSON file is { "events": [...], "recipes": [...] } — either key may be
// omitted. Every entry is validated before any write; with --dry-run nothing
// is written and only the validation report is printed.

import { readFileSync } from 'fs';
import { resolve } from 'path';

import { initFirebaseAdmin } from '../src/auth';
import { FirestoreEconomyStore } from '../src/economy/economy_store';
import {
  validateEventInput,
  validateRecipeInput,
  type CraftRecipeInput,
  type EventInput,
} from '../src/economy/types';

interface Args {
  file: string;
  dryRun: boolean;
}

function parseArgs(argv: string[]): Args {
  const positional: string[] = [];
  let dryRun = false;
  for (const arg of argv) {
    if (arg === '--dry-run') dryRun = true;
    else positional.push(arg);
  }
  if (positional.length === 0) {
    console.error('Usage: npm run economy:import -- <file.json> [--dry-run]');
    process.exit(1);
  }
  return { file: positional[0], dryRun };
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const raw = JSON.parse(readFileSync(resolve(args.file), 'utf8')) as {
    events?: unknown[];
    recipes?: unknown[];
  };

  const events: EventInput[] = [];
  const recipes: CraftRecipeInput[] = [];
  const errors: string[] = [];

  (raw.events ?? []).forEach((e, i) => {
    try {
      events.push(validateEventInput(e));
    } catch (err) {
      errors.push(`events[${i}]: ${err instanceof Error ? err.message : String(err)}`);
    }
  });
  (raw.recipes ?? []).forEach((r, i) => {
    try {
      recipes.push(validateRecipeInput(r));
    } catch (err) {
      errors.push(`recipes[${i}]: ${err instanceof Error ? err.message : String(err)}`);
    }
  });

  console.log(`Validated: ${events.length} event(s), ${recipes.length} recipe(s)`);
  for (const e of errors) console.error(`  ✗ ${e}`);
  if (errors.length > 0) process.exitCode = 1;
  if (args.dryRun) {
    console.log('(dry run — nothing written)');
    return;
  }
  if (events.length === 0 && recipes.length === 0) return;

  initFirebaseAdmin();
  const store = new FirestoreEconomyStore();
  for (const e of events) {
    const doc = await store.upsertEvent(e);
    console.log(`  event ${doc.id} ✓`);
  }
  for (const r of recipes) {
    const doc = await store.upsertRecipe(r);
    console.log(`  recipe ${doc.id} ✓`);
  }
  console.log('Done.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
