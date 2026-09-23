import { Suspense } from 'react';

import { Wordmark } from '../components/Wordmark';
import { LoginForm } from './LoginForm';

export const metadata = { title: 'Entrar | Portal MaisUm' };

/**
 * Rendered on the server, deliberately.
 *
 * If the form fell back to a plain submit, JavaScript is not running — so the
 * explanation cannot come from the client component that also is not running.
 */
function SemJavascript() {
  return (
    <p className="error" role="alert" style={{ marginBottom: 16 }}>
      Esta página precisa de JavaScript para entrar. Nada foi enviado. Verifique
      se o navegador o tem ativo e volte a tentar.
    </p>
  );
}

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const semJavascript = params.erro === 'sem-javascript';

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
        {semJavascript ? <SemJavascript /> : null}
        <noscript>
          <p className="error" role="alert" style={{ marginBottom: 16 }}>
            Esta página precisa de JavaScript para entrar.
          </p>
        </noscript>
        <Suspense fallback={null}>
          <LoginForm />
        </Suspense>
      </div>
    </main>
  );
}
