import { getAuth } from 'firebase-admin/auth';
import { initFirebaseAdmin } from '../../src/auth';
import type { SimTarget } from './world';

const DEFAULT_FIREBASE_API_KEY = 'AIzaSyBIoJ-uY79BtqM8nMkd4RfhzoQ_xqdDExY';

export type SimAuthMode = 'stub' | 'anonymous' | 'custom-token' | 'id-token-list';

export interface SimIdentity {
  agentId: string;
  uid: string;
  token: string;
  authMode: SimAuthMode;
  createdBySimulator: boolean;
}

export interface ResolveSimIdentitiesOptions {
  count: number;
  runId: string;
  target: SimTarget;
  mode?: SimAuthMode;
  apiKey?: string;
  idTokens?: string[];
  uidPrefix?: string;
}

interface IdentityToolkitResponse {
  idToken?: string;
  localId?: string;
  error?: { message?: string };
}

export async function resolveSimIdentities(
  options: ResolveSimIdentitiesOptions,
): Promise<SimIdentity[]> {
  const mode = resolveAuthMode(options);
  if (mode === 'stub') return stubIdentities(options);
  if (mode === 'id-token-list') return suppliedTokenIdentities(options);
  if (mode === 'anonymous') return anonymousIdentities(options);
  return customTokenIdentities(options);
}

export function defaultFirebaseApiKey(): string {
  return process.env.FIREBASE_API_KEY ?? DEFAULT_FIREBASE_API_KEY;
}

function resolveAuthMode(options: ResolveSimIdentitiesOptions): SimAuthMode {
  if (options.mode) return options.mode;
  if (options.target === 'in-process') return 'stub';
  if (options.idTokens && options.idTokens.length > 0) return 'id-token-list';
  return 'custom-token';
}

function stubIdentities(options: ResolveSimIdentitiesOptions): SimIdentity[] {
  return Array.from({ length: options.count }, (_, index) => {
    const uid = simUid(options.runId, index, options.uidPrefix);
    return {
      agentId: agentId(index),
      uid,
      token: uid,
      authMode: 'stub',
      createdBySimulator: false,
    };
  });
}

async function suppliedTokenIdentities(
  options: ResolveSimIdentitiesOptions,
): Promise<SimIdentity[]> {
  const tokens = options.idTokens ?? [];
  if (tokens.length < options.count) {
    throw new Error(`need ${options.count} Firebase ID tokens, got ${tokens.length}`);
  }
  return tokens.slice(0, options.count).map((token, index) => ({
    agentId: agentId(index),
    uid: uidFromIdToken(token),
    token,
    authMode: 'id-token-list',
    createdBySimulator: false,
  }));
}

async function anonymousIdentities(
  options: ResolveSimIdentitiesOptions,
): Promise<SimIdentity[]> {
  const apiKey = options.apiKey ?? defaultFirebaseApiKey();
  const users = await Promise.all(
    Array.from({ length: options.count }, () => anonymousSignIn(apiKey)),
  );
  return users.map((user, index) => ({
    agentId: agentId(index),
    uid: user.localId,
    token: user.idToken,
    authMode: 'anonymous',
    createdBySimulator: true,
  }));
}

async function customTokenIdentities(
  options: ResolveSimIdentitiesOptions,
): Promise<SimIdentity[]> {
  const apiKey = options.apiKey ?? defaultFirebaseApiKey();
  initFirebaseAdmin();
  const auth = getAuth();
  const identities: SimIdentity[] = [];
  for (let index = 0; index < options.count; index++) {
    const uid = simUid(options.runId, index, options.uidPrefix);
    const customToken = await auth.createCustomToken(uid, {
      simRunId: options.runId,
      simAgentId: agentId(index),
    });
    const user = await signInWithCustomToken(apiKey, customToken);
    if (user.localId !== uid) {
      throw new Error(`custom token for ${uid} signed in as ${user.localId}`);
    }
    identities.push({
      agentId: agentId(index),
      uid,
      token: user.idToken,
      authMode: 'custom-token',
      createdBySimulator: true,
    });
  }
  return identities;
}

function simUid(runId: string, index: number, uidPrefix?: string): string {
  const safeRunId = runId.replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 80);
  const prefix = uidPrefix?.trim() || `sim_${safeRunId}`;
  return `${prefix}_${String(index).padStart(3, '0')}`.slice(0, 128);
}

function agentId(index: number): string {
  return `sim_${String(index).padStart(3, '0')}`;
}

async function anonymousSignIn(apiKey: string): Promise<Required<Pick<IdentityToolkitResponse, 'idToken' | 'localId'>>> {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  return parseIdentityToolkitResponse(res, 'anonymous sign-in');
}

async function signInWithCustomToken(
  apiKey: string,
  token: string,
): Promise<Required<Pick<IdentityToolkitResponse, 'idToken' | 'localId'>>> {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ token, returnSecureToken: true }),
    },
  );
  return parseIdentityToolkitResponse(res, 'custom-token sign-in');
}

async function parseIdentityToolkitResponse(
  res: Awaited<ReturnType<typeof fetch>>,
  label: string,
): Promise<Required<Pick<IdentityToolkitResponse, 'idToken' | 'localId'>>> {
  const data = await res.json() as IdentityToolkitResponse;
  if (!res.ok || !data.idToken || !data.localId) {
    const why = data.error?.message ?? JSON.stringify(data);
    throw new Error(`${label} failed (${why})`);
  }
  return { idToken: data.idToken, localId: data.localId };
}

function uidFromIdToken(token: string): string {
  const payload = token.split('.')[1];
  if (!payload) throw new Error('Firebase ID token is not a JWT');
  const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as {
    user_id?: unknown;
    sub?: unknown;
  };
  const uid = typeof decoded.user_id === 'string' ? decoded.user_id : decoded.sub;
  if (typeof uid !== 'string' || uid.length === 0) {
    throw new Error('Firebase ID token payload does not contain user_id/sub');
  }
  return uid;
}
