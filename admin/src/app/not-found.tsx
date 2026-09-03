import Link from 'next/link';

export const metadata = { title: 'Página não encontrada | Portal MaisUm' };

/**
 * An address that matches nothing at all.
 *
 * The area not-found pages only cover records that turned out not to exist
 * inside `/admin` or `/negocio`. A mistyped or stale URL matches no segment,
 * so it fell through to the framework's own page — "404: This page could not
 * be found", in English, with none of the portal on it.
 *
 * No shell here on purpose: an address that belongs to no area cannot know
 * which navigation to show, and `/` sends the visitor to whichever one is
 * theirs.
 */
export default function NotFound() {
  return (
    <main className="auth-shell">
      <div className="auth-card">
        <span className="badge badge-navy" style={{ marginBottom: 14 }}>
          404
        </span>
        <h1 style={{ fontSize: '1.4rem', fontWeight: 800, margin: '0 0 8px' }}>
          Página não encontrada
        </h1>
        <p
          style={{
            margin: '0 0 22px',
            color: 'var(--g500)',
            fontSize: '0.88rem',
          }}
        >
          Este endereço não existe. Pode ter sido escrito com um erro, ou a
          página pode ter mudado de sítio.
        </p>
        <Link className="btn btn-navy btn-lg" href="/" style={{ width: '100%' }}>
          Voltar ao início
        </Link>
      </div>
    </main>
  );
}
