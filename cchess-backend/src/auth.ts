import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import * as admin from 'firebase-admin';

let initialized = false;

/// Initialize Firebase Admin once for the process.
///
/// Tries to load credentials in this order:
///   1. GOOGLE_APPLICATION_CREDENTIALS env var (gcloud convention).
///   2. ./serviceAccount.json (project root, gitignored).
///   3. Application Default Credentials (gcloud auth login on dev,
///      attached service account when deployed to Cloud Run/GCE).
export function initFirebaseAdmin(): void {
  if (initialized) return;

  const envPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  const localPath = resolve(process.cwd(), 'serviceAccount.json');

  if (envPath && existsSync(envPath)) {
    const json = JSON.parse(readFileSync(envPath, 'utf-8'));
    admin.initializeApp({
      credential: admin.credential.cert(json),
    });
    console.log(`[admin] initialized from GOOGLE_APPLICATION_CREDENTIALS=${envPath}`);
  } else if (existsSync(localPath)) {
    const json = JSON.parse(readFileSync(localPath, 'utf-8'));
    admin.initializeApp({
      credential: admin.credential.cert(json),
    });
    console.log(`[admin] initialized from ${localPath}`);
  } else {
    // Application Default Credentials — works when deployed to GCP.
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
