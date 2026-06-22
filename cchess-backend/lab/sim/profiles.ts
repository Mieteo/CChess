export type PersonaKind =
  | 'casual'
  | 'private-room'
  | 'reconnect'
  | 'spectator'
  | 'abuse';

export type BrainKind = 'random-legal' | 'scripted' | 'heuristic' | 'remote-engine';
export type SimProfileName = 'mixed-local' | 'engine-staging' | 'engine-quota';

export interface SimProfile {
  readonly name: string;
  readonly personaWeights: Readonly<Record<PersonaKind, number>>;
  readonly brainWeights: Readonly<Record<BrainKind, number>>;
  readonly reconnectChance: number;
  readonly spectatorChance: number;
  readonly abuseChance: number;
  readonly rematchChance: number;
  readonly failOnEngineError: boolean;
  readonly engineRequired: boolean;
}

export const DEFAULT_PROFILE: SimProfile = {
  name: 'mixed-local',
  personaWeights: {
    casual: 48,
    'private-room': 24,
    reconnect: 14,
    spectator: 9,
    abuse: 5,
  },
  brainWeights: {
    'random-legal': 45,
    scripted: 18,
    heuristic: 32,
    'remote-engine': 5,
  },
  reconnectChance: 0.45,
  spectatorChance: 0.06,
  abuseChance: 0.03,
  rematchChance: 0.12,
  failOnEngineError: false,
  engineRequired: false,
};

export const ENGINE_STAGING_PROFILE: SimProfile = {
  ...DEFAULT_PROFILE,
  name: 'engine-staging',
  brainWeights: {
    'random-legal': 35,
    scripted: 20,
    heuristic: 40,
    'remote-engine': 5,
  },
  failOnEngineError: true,
  engineRequired: true,
};

export const ENGINE_QUOTA_PROFILE: SimProfile = {
  ...DEFAULT_PROFILE,
  name: 'engine-quota',
  personaWeights: {
    casual: 42,
    'private-room': 28,
    reconnect: 12,
    spectator: 10,
    abuse: 8,
  },
  brainWeights: {
    'random-legal': 10,
    scripted: 10,
    heuristic: 15,
    'remote-engine': 65,
  },
  reconnectChance: 0.35,
  spectatorChance: 0.05,
  abuseChance: 0.04,
  rematchChance: 0.08,
  failOnEngineError: true,
  engineRequired: true,
};

const PROFILES: Readonly<Record<SimProfileName, SimProfile>> = {
  'mixed-local': DEFAULT_PROFILE,
  'engine-staging': ENGINE_STAGING_PROFILE,
  'engine-quota': ENGINE_QUOTA_PROFILE,
};

const BRAIN_KINDS: readonly BrainKind[] = [
  'scripted',
  'heuristic',
  'remote-engine',
  'random-legal',
];

export function profileByName(name: string | undefined): SimProfile {
  if (name === undefined) return DEFAULT_PROFILE;
  const profile = PROFILES[name as SimProfileName];
  if (!profile) {
    throw new Error(`unknown simulation profile "${name}". Expected: ${Object.keys(PROFILES).join(', ')}`);
  }
  return profile;
}

export function profileForRun(
  name: string | undefined,
  engineConfigured: boolean,
  failOnEngineError?: boolean,
): SimProfile {
  const profile = profileByName(name);
  const shouldKeepEngine = engineConfigured || profile.engineRequired;
  return {
    ...profile,
    brainWeights: shouldKeepEngine
      ? profile.brainWeights
      : { ...profile.brainWeights, 'remote-engine': 0 },
    failOnEngineError: failOnEngineError ?? profile.failOnEngineError,
  };
}

export function personaPlan(users: number, profile = DEFAULT_PROFILE): PersonaKind[] {
  if (users < 2) return [];
  const counts = weightedCounts(users, profile.personaWeights);

  // The runner needs enough actual players to keep games flowing. Keep spectator
  // and abuse load bounded for small local runs, but still present for Phase 3.
  const maxSupport = Math.max(0, users - 2);
  counts.spectator = Math.min(counts.spectator, Math.max(0, Math.floor(users / 5)));
  counts.abuse = Math.min(counts.abuse, Math.max(0, Math.floor(users / 8)));
  if (counts.spectator + counts.abuse > maxSupport) {
    counts.abuse = Math.min(counts.abuse, maxSupport);
    counts.spectator = Math.min(counts.spectator, maxSupport - counts.abuse);
  }
  if (users >= 8 && counts.spectator === 0) counts.spectator = 1;
  if (users >= 12 && counts.abuse === 0) counts.abuse = 1;

  let players =
    users - counts.spectator - counts.abuse;
  if (players % 2 === 1) {
    counts.spectator = Math.max(0, counts.spectator - 1);
    players++;
  }
  counts.casual = Math.max(0, counts.casual);
  counts['private-room'] = Math.max(0, counts['private-room']);
  counts.reconnect = Math.max(0, players - counts.casual - counts['private-room']);

  while (counts.casual + counts['private-room'] + counts.reconnect < players) {
    counts.casual++;
  }
  while (counts.casual + counts['private-room'] + counts.reconnect > players) {
    if (counts.casual > 0) counts.casual--;
    else if (counts['private-room'] > 0) counts['private-room']--;
    else counts.reconnect--;
  }
  if (players >= 4 && counts.reconnect === 0) {
    if (counts.casual > counts['private-room'] && counts.casual > 0) counts.casual--;
    else if (counts['private-room'] > 0) counts['private-room']--;
    counts.reconnect++;
  }

  return [
    ...repeat<PersonaKind>('casual', counts.casual),
    ...repeat<PersonaKind>('private-room', counts['private-room']),
    ...repeat<PersonaKind>('reconnect', counts.reconnect),
    ...repeat<PersonaKind>('spectator', counts.spectator),
    ...repeat<PersonaKind>('abuse', counts.abuse),
  ];
}

export function brainPlan(players: number, profile = DEFAULT_PROFILE): BrainKind[] {
  const counts = weightedCounts(players, profile.brainWeights);
  ensureAtLeastOne(counts, 'scripted', players >= 4);
  ensureAtLeastOne(counts, 'heuristic', players >= 6);
  ensureAtLeastOne(
    counts,
    'remote-engine',
    profile.brainWeights['remote-engine'] > 0 && players >= 2,
  );
  return BRAIN_KINDS.flatMap((kind) => repeat<BrainKind>(kind, counts[kind]));
}

function weightedCounts<T extends string>(
  total: number,
  weights: Readonly<Record<T, number>>,
): Record<T, number> {
  const keys = Object.keys(weights) as T[];
  const sum = keys.reduce((acc, key) => acc + weights[key], 0);
  const counts = {} as Record<T, number>;
  let assigned = 0;
  for (const key of keys) {
    const count = Math.floor((total * weights[key]) / sum);
    counts[key] = count;
    assigned += count;
  }
  const sorted = [...keys].sort((a, b) => weights[b] - weights[a]);
  let i = 0;
  while (assigned < total) {
    counts[sorted[i % sorted.length]]++;
    assigned++;
    i++;
  }
  return counts;
}

function repeat<T>(value: T, count: number): T[] {
  return Array.from({ length: Math.max(0, count) }, () => value);
}

function ensureAtLeastOne(
  counts: Record<BrainKind, number>,
  kind: BrainKind,
  enabled: boolean,
): void {
  if (!enabled || counts[kind] > 0) return;
  const donor = [...BRAIN_KINDS]
    .filter((candidate) => candidate !== kind)
    .sort((a, b) => counts[b] - counts[a])[0];
  if (!donor || counts[donor] <= 0) return;
  counts[donor]--;
  counts[kind]++;
}
