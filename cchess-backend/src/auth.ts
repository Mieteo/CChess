import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import * as admin from 'firebase-admin';

let initialized = false;

/// Initialize Firebase Admin once for the process.
///
/// Tries to load credentials in this order:
///   1. FIREBASE_SERVICE_ACCOUNT_JSON env var — full JSON inline (Render/Railway pattern).
///   2. GOOGLE_APPLICATION_CREDENTIALS env var — path to JSON file (gcloud convention).
///   3. ./serviceAccount.json (project root, gitignored, local dev).
///   4. Application Default Credentials (Cloud Run / GCE / Cloud Functions).
export function initFirebaseAdmin(): void {
  if (initialized) return;

  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  const envPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const localPath = resolve(process.cwd(), 'serviceAccount.json');

  if (inlineJson && inlineJson.length > 0) {
    let parsed;
    try {
      parsed = JSON.parse(inlineJson);
    } catch (e) {
      throw new Error(
        `FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON: ${e instanceof Error ? e.message : e}`,
      );
    }
    admin.initializeApp({ credential: admin.credential.cert(parsed) });
    console.log('[admin] initialized from FIREBASE_SERVICE_ACCOUNT_JSON env');
  } else if (envPath && existsSync(envPath)) {
    const json = JSON.parse(readFileSync(envPath, 'utf-8'));
    admin.initializeApp({ credential: admin.credential.cert(json) });
    console.log(`[admin] initialized from GOOGLE_APPLICATION_CREDENTIALS=${envPath}`);
  } else if (existsSync(localPath)) {
    const json = JSON.parse(readFileSync(localPath, 'utf-8'));
    admin.initializeApp({ credential: admin.credential.cert(json) });
    console.log(`[admin] initialized from ${localPath}`);
  } else {
    admin.initializeApp();
    console.log('[admin] initialized via Application Default Credentials');
  }

  initialized = true;
}

export interface VerifiedToken {
  uid: string;
  email?: string;
  firebase?: {
    sign_in_provider?: string;
  };
}

export async function verifyIdToken(token: string): Promise<VerifiedToken> {
  const decoded = await admin.auth().verifyIdToken(token);
  return {
    uid: decoded.uid,
    email: decoded.email,
    firebase: {
      sign_in_provider: decoded.firebase?.sign_in_provider,
    },
  };
}
