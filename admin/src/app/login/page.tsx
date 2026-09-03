import { Suspense } from 'react';

import { Wordmark } from '../components/Wordmark';
import { LoginForm } from './LoginForm';

export const metadata = { title: 'Entrar | Portal MaisUm' };

export default function LoginPage() {
  return (
    <main className="auth-shell">
      <div className="auth-card">
        <div style={{ marginBottom: 16 }}>
          <Wordmark tone="onLight" area={null} />
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
          Para a equipa interna e para responsáveis de negócio.
        </p>
        <Suspense fallback={null}>
          <LoginForm />
        </Suspense>
      </div>
    </main>
  );
}
