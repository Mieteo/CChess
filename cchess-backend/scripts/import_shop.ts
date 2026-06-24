// Bulk-import shop catalog items into Firestore `shop_items/{id}` (S16 economy).
//
// Writes via the Admin SDK (bypasses security rules), so it needs the same
// service-account credentials the backend uses — see src/auth.ts for the lookup
// order (FIREBASE_SERVICE_ACCOUNT_JSON, GOOGLE_APPLICATION_CREDENTIALS,
// ./serviceAccount.json, or ADC).
//
// Usage:
//   npm run shop:import -- scripts/shop.seed.json
//   npm run shop:import -- path/to/batch.json --dry-run   (validate only)
//
// The JSON file is either an array of items or { "items": [...] }. Each item is
// validated (kind, name, price, payloadKey) before any write; with --dry-run
// nothing is written and only the validation report is printed.

import { readFileSync } from 'fs';
import { resolve } from 'path';

import { initFirebaseAdmin } from '../src/auth';
import { FirestoreShopStore } from '../src/shop/shop_store';
import { validateShopItemInput, type ShopItemInput } from '../src/shop/types';

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
    console.error('Usage: npm run shop:import -- <file.json> [--dry-run]');
    process.exit(1);
  }
  return { file: positional[0], dryRun };
}

function loadItems(file: string): unknown[] {
  const text = readFileSync(resolve(process.cwd(), file), 'utf-8');
  const parsed = JSON.parse(text);
  if (Array.isArray(parsed)) return parsed;
  if (Array.isArray(parsed?.items)) return parsed.items;
  throw new Error('JSON must be an array or { "items": [...] }');
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const raw = loadItems(args.file);
  console.log(`[shop:import] ${raw.length} item(s) from ${args.file}`);

  const valid: ShopItemInput[] = [];
  const errors: { index: number; message: string }[] = [];
  raw.forEach((item, index) => {
    try {
      valid.push(validateShopItemInput(item));
    } catch (e) {
      errors.push({ index, message: e instanceof Error ? e.message : String(e) });
    }
  });

  if (errors.length > 0) {
    console.error(`[shop:import] ${errors.length} invalid item(s):`);
    for (const e of errors) console.error(`  #${e.index}: ${e.message}`);
  }
  console.log(`[shop:import] ${valid.length} valid, ${errors.length} invalid`);

  if (args.dryRun) {
    console.log('[shop:import] --dry-run: nothing written.');
    return;
  }
  if (valid.length === 0) {
    console.log('[shop:import] nothing to write.');
    return;
  }

  initFirebaseAdmin();
  const store = new FirestoreShopStore();
  let written = 0;
  for (const input of valid) {
    const doc = await store.upsertItem(input);
    written++;
    const price = doc.priceGems > 0 ? `💎${doc.priceGems}` : `🪙${doc.priceCoins}`;
    console.log(`  ✓ ${doc.id} — ${doc.nameVi} (${price})`);
  }
  console.log(`[shop:import] done: ${written} written, ${errors.length} skipped.`);
}

main().catch((e) => {
  console.error('[shop:import] fatal:', e);
  process.exit(1);
});
