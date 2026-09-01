'use client';

import { useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import {
  browserSessionPersistence,
  setPersistence,
  signInWithEmailAndPassword,
  signOut,
} from 'firebase/auth';

import { clientAuth } from '@/lib/firebase-client';

/** Maps Firebase error codes to something an operator can act on. */
function describe(error: unknown): string {
  const code =
    typeof error === 'object' && error !== null && 'code' in error
      ? String((error as { code: unknown }).code)
      : '';
  switch (code) {
    case 'auth/invalid-email':
      return 'Email inválido.';
    case 'auth/user-disabled':
      return 'Esta conta está desativada.';
    case 'auth/invalid-credential':
    case 'auth/wrong-password':
    case 'auth/user-not-found':
      // Deliberately identical for all three: distinguishing them tells an
      // attacker which emails exist.
      return 'Email ou palavra-passe incorretos.';
    case 'auth/too-many-requests':
      return 'Demasiadas tentativas. Tente novamente mais tarde.';
    case 'auth/network-request-failed':
      return 'Sem ligação. Verifique a rede.';
    default:
      return error instanceof Error && error.message
        ? error.message
        : 'Não foi possível entrar.';
  }
}

export function LoginForm() {
  const router = useRouter();
  const params = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function handleSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setBusy(true);

    const auth = clientAuth();
    try {
      // Session persistence: closing the browser ends the session. Internal
      // tooling should not stay signed in on a shared machine indefinitely.
      await setPersistence(auth, browserSessionPersistence);
      const credential = await signInWithEmailAndPassword(
        auth,
        email.trim(),
        password,
      );
      const idToken = await credential.user.getIdToken();

      const response = await fetch('/api/session', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken }),
      });

      if (!response.ok) {
        // The account authenticated but is not an admin, so drop the Firebase
        // session too rather than leaving a half-signed-in state.
        await signOut(auth).catch(() => undefined);
        const body: unknown = await response.json().catch(() => null);
        const message =
          typeof body === 'object' && body !== null && 'error' in body
            ? String((body as { error: unknown }).error)
            : 'Não foi possível iniciar sessão.';
        setError(message);
        return;
      }

      const next = params.get('next');
      router.replace(next && next.startsWith('/') ? next : '/admin');
      router.refresh();
    } catch (caught) {
      setError(describe(caught));
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={handleSubmit}>
      {error ? (
        <p className="error" style={{ marginBottom: 16 }}>
          {error}
        </p>
      ) : null}
      <div className="field">
        <label htmlFor="email">Email</label>
        <input
          id="email"
          className="input"
          type="email"
          name="email"
          autoComplete="username"
          required
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
      </div>
      <div className="field">
        <label htmlFor="password">Palavra-passe</label>
        <input
          id="password"
          className="input"
          type="password"
          name="password"
          autoComplete="current-password"
          required
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
      </div>
      <button
        className="btn btn-gold btn-lg"
        type="submit"
        disabled={busy}
        style={{ width: "100%" }}
      >
        {busy ? 'A entrar…' : 'Entrar'}
      </button>
    </form>
  );
}
