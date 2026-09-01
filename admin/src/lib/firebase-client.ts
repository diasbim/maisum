'use client';

import { getApp, getApps, initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth, type Auth } from 'firebase/auth';

import { assertPublicConfig, publicConfig } from './env';

let emulatorConnected = false;

/**
 * Browser-side Firebase, used only to sign in and to keep the ID token fresh.
 * The token itself never lives in JavaScript-readable storage: it is posted to
 * /api/session, which stores it in an httpOnly cookie.
 */
export function clientAuth(): Auth {
  assertPublicConfig();
  const app = getApps().length
    ? getApp()
    : initializeApp({
        apiKey: publicConfig.firebaseApiKey,
        authDomain: publicConfig.firebaseAuthDomain,
        projectId: publicConfig.firebaseProjectId,
      });
  const auth = getAuth(app);

  // Local development against the Firebase Auth emulator. Set only in
  // .env.local; unset in every deployed environment, so this is inert there.
  const emulatorHost = publicConfig.authEmulatorHost;
  if (emulatorHost && !emulatorConnected) {
    connectAuthEmulator(auth, emulatorHost, { disableWarnings: true });
    emulatorConnected = true;
  }

  return auth;
}
