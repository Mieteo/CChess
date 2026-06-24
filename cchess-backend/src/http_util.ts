// Small shared HTTP helpers for the mountable JSON APIs (puzzles already has its
// own copy; the shop API uses these). Kept dependency-free so any route module
// can `import` them without pulling in Firestore.

import type { IncomingMessage, ServerResponse } from 'http';

import type { VerifiedToken } from './auth';

/// HTTP-shaped error the routers convert to `{ code, message }` + status.
export class HttpError extends Error {
  constructor(
    public readonly statusCode: number,
    public readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'HttpError';
  }
}

/// Duck-typed check so route modules can throw their own error class (e.g.
/// ShopError) without importing HttpError, as long as it carries statusCode/code.
export function isHttpError(
  error: unknown,
): error is { statusCode: number; code: string; message: string } {
  return (
    typeof error === 'object' &&
    error !== null &&
    typeof (error as { statusCode?: unknown }).statusCode === 'number' &&
    typeof (error as { code?: unknown }).code === 'string'
  );
}

export async function requireAuth(
  req: IncomingMessage,
  authenticate: (token: string) => Promise<VerifiedToken>,
): Promise<VerifiedToken> {
  const auth = req.headers.authorization ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(Array.isArray(auth) ? auth[0] : auth);
  if (!match) throw new HttpError(401, 'missing-token', 'Missing Bearer token');
  try {
    return await authenticate(match[1]);
  } catch {
    throw new HttpError(401, 'invalid-token', 'Invalid Firebase ID token');
  }
}

export function readJsonBody(req: IncomingMessage, maxBytes: number): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on('data', (chunk: Buffer) => {
      size += chunk.length;
      if (size > maxBytes) {
        reject(new HttpError(413, 'request-too-large', 'Request body is too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(text.length === 0 ? {} : JSON.parse(text));
      } catch {
        reject(new HttpError(400, 'invalid-json', 'Request body must be valid JSON'));
      }
    });
    req.on('error', (error) => reject(error));
  });
}

export function sendJson(res: ServerResponse, statusCode: number, body: unknown): void {
  res.writeHead(statusCode, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(body));
}

export function sendError(res: ServerResponse, error: unknown, logPrefix = 'http'): void {
  if (isHttpError(error)) {
    sendJson(res, error.statusCode, { code: error.code, message: error.message });
    return;
  }
  const message = error instanceof Error ? error.message : String(error);
  console.error(`[${logPrefix}] internal error:`, message);
  sendJson(res, 500, { code: 'internal-error', message: 'Internal error' });
}

export function setCors(res: ServerResponse): void {
  res.setHeader('Access-Control-Allow-Origin', process.env.CORS_ORIGIN ?? '*');
  res.setHeader('Access-Control-Allow-Headers', 'authorization, content-type, x-admin-key');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
}

/// Length-independent constant-time string compare (avoids leaking the key
/// length / prefix via early-exit timing).
export function timingSafeEqual(a: string, b: string): boolean {
  let mismatch = a.length === b.length ? 0 : 1;
  const len = Math.max(a.length, b.length);
  for (let i = 0; i < len; i++) {
    mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return mismatch === 0;
}

export function clampInt(raw: string | null, min: number, max: number): number | undefined {
  if (raw === null || raw.trim() === '') return undefined;
  const value = Number(raw);
  if (!Number.isFinite(value)) return undefined;
  return Math.min(max, Math.max(min, Math.trunc(value)));
}

export function nonEmpty(raw: string | null): string | undefined {
  const v = raw?.trim();
  return v && v.length > 0 ? v : undefined;
}
