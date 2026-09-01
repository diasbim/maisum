import { Suspense } from 'react';

import { LoginForm } from './LoginForm';

export const metadata = { title: 'Entrar | Portal MaisUm' };

export default function LoginPage() {
  return (
    <main className="auth-shell">
      <div className="auth-card">
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            marginBottom: 18,
          }}
        >
          <span
            style={{
              width: 10,
              height: 10,
              borderRadius: '50%',
              background: 'var(--gold)',
            }}
          />
          <span
            style={{
              fontFamily: 'var(--font-head), system-ui, sans-serif',
              fontWeight: 800,
              color: 'var(--navy)',
            }}
          >
            MaisUm · Operações
          </span>
        </div>
        <h1 style={{ fontSize: '1.5rem', fontWeight: 800, marginBottom: 6 }}>
          Entrar
        </h1>
        <p
          style={{
            margin: '0 0 24px',
            color: 'var(--g500)',
            fontSize: '0.88rem',
          }}
        >
          Acesso restrito à equipa interna.
        </p>
        <Suspense fallback={null}>
          <LoginForm />
        </Suspense>
      </div>
    </main>
  );
}
