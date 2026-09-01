import { redirect } from 'next/navigation';

import { getAdminSession, hasValidNonAdminSession } from '@/lib/session';
import { AdminNav } from './AdminNav';
import { SessionRefresher } from './SessionRefresher';
import { SignOutButton } from './SignOutButton';

/**
 * The real authorization gate. Middleware only checks that a cookie exists;
 * this verifies the token and the admin claim on every request into /admin.
 */
export default async function AdminLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getAdminSession();

  if (!session) {
    // A valid sign-in without the admin claim is a different problem from being
    // signed out, and sending it to /login would loop.
    if (await hasValidNonAdminSession()) {
      redirect('/no-access');
    }
    redirect('/login');
  }

  return (
    <>
      {/* Lives in the layout, not on the overview page: the cookie has to keep
          pace with token rotation on every screen, and an operator can sit on a
          merchant detail page for longer than a token lasts. */}
      <SessionRefresher />

      <a className="skip-link" href="#conteudo">
        Saltar para o conteúdo
      </a>

      <header className="topbar">
        <div className="topbar__inner">
          <div className="topbar__logo">
            <span className="topbar__dot" />
            MaisUm · Operações
          </div>
          <span style={{ marginLeft: 'auto' }} />
          <span className="topbar__user">{session.email ?? session.uid}</span>
          <SignOutButton />
        </div>
      </header>

      <div className="shell">
        <nav className="sidebar" aria-label="Secções">
          <AdminNav />
        </nav>
        <main id="conteudo">{children}</main>
      </div>
    </>
  );
}
