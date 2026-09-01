'use client';

import { useEffect } from 'react';
import { onIdTokenChanged } from 'firebase/auth';

import { clientAuth } from '@/lib/firebase-client';

/**
 * Keeps the httpOnly session cookie in step with the Firebase ID token.
 *
 * ID tokens last an hour and the SDK rotates them in the background. Without
 * this, the cookie would go stale mid-session and the next server render would
 * bounce the operator to the login page for no visible reason.
 */
export function SessionRefresher() {
  useEffect(() => {
    const auth = clientAuth();
    return onIdTokenChanged(auth, async (user) => {
      if (!user) return;
      try {
        const idToken = await user.getIdToken();
        await fetch('/api/session', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ idToken }),
        });
      } catch {
        // A failed refresh is not actionable here; the next server render will
        // redirect to /login if the cookie has actually expired.
      }
    });
  }, []);

  return null;
}
