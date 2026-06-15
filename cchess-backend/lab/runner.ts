// Headless scenario runner. Each scenario runs against its own fresh
// in-process server (see run-one.ts); invariants are asserted after every step
// and once more at the end.
//
//   npx tsx lab/runner.ts            # run all
//   npx tsx lab/runner.ts reconnect  # only scenarios whose name matches a filter
//   LAB_VERBOSE=1 npx tsx lab/runner.ts   # also show the server's own logs

import { scenarios } from './scenarios';
import { runScenario } from './run-one';

async function main(): Promise<void> {
  // The runner's own report always prints; the server's chatty logs (and the
  // harmless Firebase ELO-fetch warning, which is caught + defaulted) are
  // silenced unless LAB_VERBOSE is set.
  const print = console.log.bind(console);
  if (!process.env.LAB_VERBOSE) {
    console.log = () => {};
    console.warn = () => {};
    console.error = () => {};
  }

  const filter = process.argv[2];
  const list = filter
    ? scenarios.filter((s) => s.name.includes(filter))
    : scenarios;

  if (list.length === 0) {
    print(`No scenario matches "${filter}". Available:`);
    for (const s of scenarios) print(`  - ${s.name}`);
    process.exit(1);
  }

  print(`\nCChess test lab — running ${list.length} scenario(s)\n`);
  let passed = 0;
  const failures: { name: string; error: string }[] = [];

  for (const sc of list) {
    const res = await runScenario(sc);
    if (res.ok) {
      print(`  ✔ ${res.name}  (${res.ms}ms)`);
      passed++;
    } else {
      print(`  ✘ ${res.name}  (${res.ms}ms)`);
      failures.push({ name: res.name, error: res.error ?? 'unknown' });
    }
  }

  print(`\n${passed}/${list.length} passed`);
  if (failures.length > 0) {
    print('\nFailures:');
    for (const f of failures) {
      print(`\n  ✘ ${f.name}\n    ${f.error.replace(/\n/g, '\n    ')}`);
    }
    process.exitCode = 1;
  }
  print('');
}

void main();
