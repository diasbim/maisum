import Link from 'next/link';
import { redirect } from 'next/navigation';

import { getAdminSession, hasValidNonAdminSession } from '@/lib/session';
import { AdminNav, MobileNav } from './AdminNav';
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
          {/* Only rendered below the shell breakpoint, where the sidebar is
              not on screen. */}
          <MobileNav account={session.email ?? session.uid} />

          <div className="topbar__logo">
            <span className="topbar__dot" />
            <span className="topbar__name">MaisUm · Operações</span>
          </div>

          <div className="topbar__account">
            {/* The account was previously a dead label. It is the way into the
                profile now, which is where "what does this login let me do"
                is answered. */}
            <Link className="topbar__user" href="/admin/perfil">
              {session.email ?? session.uid}
            </Link>
            <SignOutButton />
          </div>
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
