import { redirect } from 'next/navigation';

import { getMerchantSession } from '@/lib/merchant-session';
import { resolvePortalHome } from '@/lib/portal-home';
import { Wordmark } from '../components/Wordmark';
import { SessionRefresher } from '../admin/SessionRefresher';
import { SignOutButton } from '../admin/SignOutButton';
import { MerchantNav, MerchantMobileNav } from './MerchantNav';

/**
 * The business owner's area.
 *
 * A separate segment from `/admin`, not a mode inside it: the two answer
 * different questions about the same person. `/admin` asks whether they are
 * internal staff; this asks which business they are. Keeping them apart means
 * a mistake in one gate cannot quietly widen the other.
 */
export default async function MerchantLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const session = await getMerchantSession();

  if (!session) {
    // Signed in but running no business is a different problem from being
    // signed out, and sending it to /login would loop. Internal staff who end
    // up here belong in the console, not on a page telling them they have no
    // access at all.
    redirect(await resolvePortalHome());
  }

  return (
    <>
      <SessionRefresher />

      <a className="skip-link" href="#conteudo">
        Saltar para o conteúdo
      </a>

      <header className="topbar">
        <div className="topbar__inner">
          <MerchantMobileNav business={session.active.name ?? session.active.id} />

          <div className="topbar__logo">
            <Wordmark tone="onDark" area="Negócio" />
          </div>

          <div className="topbar__account">
            <span className="topbar__user">
              {session.active.name ?? session.active.id}
            </span>
            <SignOutButton />
          </div>
        </div>
      </header>

      <div className="shell">
        <nav className="sidebar" aria-label="Secções">
          <MerchantNav />
        </nav>
        <main id="conteudo">{children}</main>
      </div>

      {session.businesses.length > 1 ? (
        // Stated rather than hidden: an owner of several businesses needs to
        // know which one these numbers belong to. Switching arrives with the
        // screens that make it matter.
        <p className="micro" style={{ textAlign: 'center', padding: '0 24px 32px' }}>
          Esta conta gere {session.businesses.length} negócios. A mostrar{' '}
          <strong>{session.active.name ?? session.active.id}</strong>.
        </p>
      ) : null}
    </>
  );
}
