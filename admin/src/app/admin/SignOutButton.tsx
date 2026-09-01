'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { signOut } from 'firebase/auth';

import { clientAuth } from '@/lib/firebase-client';

export function SignOutButton() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);

  async function handleClick() {
    setBusy(true);
    // Clear the httpOnly cookie first: if the Firebase sign-out fails, the
    // server-side session is already gone, which is the one that grants access.
    await fetch('/api/session', { method: 'DELETE' }).catch(() => undefined);
    await signOut(clientAuth()).catch(() => undefined);
    router.replace('/login');
    router.refresh();
  }

  return (
    <button
      className="btn btn-ghost-dark btn-sm"
      type="button"
      onClick={handleClick}
      disabled={busy}
    >
      {busy ? 'A sair…' : 'Sair'}
    </button>
  );
}
