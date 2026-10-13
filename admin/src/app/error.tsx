'use client';

/**
 * A render that threw outside either area's shell.
 *
 * The console has its own boundary; this one covers what sits above both —
 * chiefly `/`, which now asks the API which area the visitor belongs in and so
 * has a way to fail that it did not have when it was a fixed redirect. Without
 * a boundary here that failure would reach the framework's own error page.
 */
export default function RootError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <main className="auth-shell">
      <div className="auth-card">
        <h1 style={{ fontSize: '1.4rem', fontWeight: 800, margin: '0 0 8px' }}>
          Não foi possível continuar
        </h1>
        <p
          style={{
            margin: '0 0 22px',
            color: 'var(--g500)',
            fontSize: '0.88rem',
          }}
        >
          O serviço não respondeu, por isso não sabemos ainda para onde o levar.
          Se tiver sido passageiro, voltar a tentar resolve.
        </p>

        {error.digest ? (
          <p className="micro" style={{ marginBottom: 14 }}>
            Referência para os registos:{' '}
            <code className="inline">{error.digest}</code>
          </p>
        ) : null}

        <button
          className="btn btn-navy btn-lg"
          type="button"
          onClick={reset}
          style={{ width: '100%' }}
        >
          Tentar de novo
        </button>
      </div>
    </main>
  );
}
