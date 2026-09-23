import { redirect } from 'next/navigation';

import { adminClaimNames } from '@/lib/admin-claims';
import { getAdminSession } from '@/lib/session';
import { SignOutButton } from '../SignOutButton';
import { Card, DefinitionList, EmptyState, PageHeader, Panel } from '../ui';

export const metadata = { title: 'A minha conta | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * The operator's own account.
 *
 * Every write in this console is attributed to the signed-in person in the
 * admin audit trail, so "which account am I acting as, and what does it let me
 * do" is a question the portal has to be able to answer directly — the topbar
 * showed an email and nothing else. It reads from the verified session rather
 * than the browser: the same token the API sees is the one described here.
 */

/** Seconds since the epoch, as the claims carry them. */
function fromClaimSeconds(seconds: unknown): string {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return '—';
  return new Date(seconds * 1000).toLocaleString('pt-PT', {
    dateStyle: 'short',
    timeStyle: 'short',
  });
}

/** How the person signed in, in words rather than Firebase's identifiers. */
function providerLabel(claims: Record<string, unknown>): string {
  const firebase = claims.firebase as { sign_in_provider?: unknown } | undefined;
  const provider = firebase?.sign_in_provider;
  if (typeof provider !== 'string') return '—';
  if (provider === 'password') return 'Email e palavra-passe';
  if (provider === 'google.com') return 'Google';
  if (provider === 'phone') return 'Telefone';
  return provider;
}

export default async function ProfilePage() {
  const session = await getAdminSession();
  // The layout already gates this, so a null here means the session expired
  // between that check and this one.
  if (!session) redirect('/login');

  const claims = session.claims as unknown as Record<string, unknown>;
  const granting = adminClaimNames(claims);
  const expiresAt = fromClaimSeconds(claims.exp);

  return (
    <>
      <PageHeader
        title="A minha conta"
        subtitle="A conta com que está a operar este portal."
        action={<SignOutButton />}
      />

      <Card title="Identificação">
        <DefinitionList
          entries={[
            ['Email', session.email ?? '—'],
            [
              'Email verificado',
              claims.email_verified === true ? 'Sim' : 'Não',
            ],
            ['ID do utilizador', <code key="uid">{session.uid}</code>],
            ['Método de entrada', providerLabel(claims)],
          ]}
        />
      </Card>

      <Panel title="Acesso">
        <Card
          hint={
            granting.length > 1
              ? 'Mais do que uma permissão concede este acesso. Revogar apenas uma delas não o retira.'
              : 'Esta é a permissão que abre o portal. O acesso é verificado de novo pela API em cada pedido.'
          }
          title="Permissões de administrador"
        >
          {granting.length === 0 ? (
            <EmptyState message="Nenhuma permissão de administrador encontrada nesta sessão." />
          ) : (
            <ul className="claim-list">
              {granting.map((claim) => (
                <li key={claim}>
                  <code>{claim}</code>
                </li>
              ))}
            </ul>
          )}
        </Card>
      </Panel>

      <Panel title="Sessão">
        <Card
          hint="A sessão renova-se sozinha enquanto o separador estiver aberto. Ao terminar, é preciso entrar de novo."
          title="Validade"
        >
          <DefinitionList
            entries={[
              ['Entrou em', fromClaimSeconds(claims.auth_time)],
              ['Sessão válida até', expiresAt],
            ]}
          />
        </Card>
      </Panel>
    </>
  );
}
