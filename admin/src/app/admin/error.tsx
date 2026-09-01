'use client';

/**
 * The last resort for a render that threw.
 *
 * Panels handle their own API failures inline, so reaching here means
 * something unexpected broke. The digest is shown because it is the only
 * handle an operator has on the matching server log — the message itself is
 * redacted in production builds.
 */
export default function AdminError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div className="card" style={{ maxWidth: 620 }}>
      <p className="card__title">Esta página não carregou</p>
      <p className="card__hint">
        Algo falhou ao montar a página. Voltar a tentar resolve, se tiver sido
        passageiro.
      </p>

      {error.digest ? (
        <p className="micro">
          Referência para os registos: <code className="inline">{error.digest}</code>
        </p>
      ) : null}

      <div className="form-actions">
        <button className="btn btn-navy" type="button" onClick={reset}>
          Tentar de novo
        </button>
      </div>
    </div>
  );
}
