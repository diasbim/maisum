import { SignOutButton } from '../admin/SignOutButton';

export const metadata = { title: 'Sem acesso | Portal MaisUm' };

export default function NoAccessPage() {
  return (
    <main className="auth-shell">
      <div className="auth-card">
        <span className="badge badge-amber" style={{ marginBottom: 14 }}>
          Sem permissão
        </span>
        <h1 style={{ fontSize: '1.4rem', fontWeight: 800, margin: '0 0 8px' }}>
          Sem acesso
        </h1>
        <p
          style={{
            margin: '0 0 22px',
            color: 'var(--g500)',
            fontSize: '0.88rem',
          }}
        >
          A sua conta entrou com sucesso, mas não tem acesso a este portal: não
          é da equipa interna, e não está associada a nenhum negócio. Se gere um
          negócio na MaisUm, peça que associem esta conta a ele.
        </p>
        <div style={{ background: 'var(--navy)', borderRadius: 'var(--r)', padding: 12 }}>
          <SignOutButton />
        </div>
      </div>
    </main>
  );
}
