import { Suspense } from 'react';
import Link from 'next/link';

import { fetchAdminDirectory, fetchStaff } from '@/lib/admin-api';
import {
  Badge,
  ChipFilter,
  EmptyState,
  PageHeader,
  Pagination,
  Panel,
  TableSkeleton,
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../ui';

export const metadata = { title: 'Acessos | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const PAGE_SIZE = 25;

const STATUSES = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'INVITED', label: 'Convidados' },
  { value: 'INACTIVE', label: 'Inativos' },
];

/**
 * Who holds an administrator claim.
 *
 * Read from Firebase Auth, because that is where the claim lives — there is no
 * table of administrators. Granting and revoking is still a command-line
 * operation (`functions/scripts/admin_claims.js`); this answers the question
 * that came first and had no answer at all: who has this power today.
 */
async function Directory() {
  const result = await load(fetchAdminDirectory);
  if (result.error !== null) return <p className="error">{result.error}</p>;

  if (result.data.entries.length === 0) {
    return <EmptyState message="Nenhuma conta com claim de administrador." />;
  }

  return (
    <>
      {result.data.truncated ? (
        <div className="notice notice--error" style={{ marginBottom: 14 }}>
          <span className="notice__mark" aria-hidden>
            ⚠
          </span>
          <span>
            O diretório é maior do que o limite de varrimento. Esta lista está
            incompleta — {result.data.scanned} contas percorridas.
          </span>
        </div>
      ) : null}

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th>Conta</th>
              <th>Claim que concede</th>
              <th>Estado</th>
              <th>Último início de sessão</th>
            </tr>
          </thead>
          <tbody>
            {result.data.entries.map((entry) => (
              <tr key={entry.uid}>
                <td>
                  {entry.email ?? entry.display_name ?? entry.uid}
                  <div className="micro">{entry.uid}</div>
                </td>
                <td>
                  {entry.claims.map((claim) => (
                    <code
                      className="inline"
                      key={claim}
                      style={{ marginRight: 4 }}
                    >
                      {claim}
                    </code>
                  ))}
                </td>
                <td>
                  <Badge label={entry.disabled ? 'DESATIVADA' : 'ACTIVE'} />
                </td>
                <td>{formatDateTime(entry.last_sign_in_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <p className="micro" style={{ marginTop: 10 }}>
        Conceder ou revogar continua a ser pela linha de comandos:{' '}
        <code className="inline">
          node functions/scripts/admin_claims.js --grant &lt;email&gt; --yes
        </code>
        . Revogar tem efeito imediato — a sessão do portal verifica cada pedido
        contra os tokens revogados.
      </p>
    </>
  );
}

async function Staff({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchStaff({
      search: search || undefined,
      status: status || undefined,
      limit: PAGE_SIZE,
      offset,
    }),
  );

  if (result.error !== null) return <p className="error">{result.error}</p>;
  if (result.data.items.length === 0) {
    return <EmptyState message="Nenhuma conta corresponde a estes filtros." />;
  }

  return (
    <>
      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th>Telefone</th>
              <th>Negócio</th>
              <th>Papel</th>
              <th>Estado</th>
              <th>Último início de sessão</th>
              <th>Criada</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((user) => (
              <tr key={user.id}>
                <td>
                  {user.phone}
                  <div className="micro">{user.id}</div>
                </td>
                <td>
                  <Link
                    href={`/admin/merchants/${encodeURIComponent(user.merchant_id)}`}
                  >
                    {user.merchant_name ?? user.merchant_id}
                  </Link>
                </td>
                <td>{user.role}</td>
                <td>
                  <Badge label={user.status} />
                </td>
                <td>{formatDateTime(user.last_login_at)}</td>
                <td>{formatDateTime(user.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination
        basePath="/admin/access"
        query={{ search: search || undefined, status: status || undefined }}
        limit={PAGE_SIZE}
        offset={offset}
        hasMore={result.data.paging?.has_more ?? false}
        returned={result.data.items.length}
      />
    </>
  );
}

export default async function AccessPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const search = parseSearch(params.search);
  const status = parseSearch(params.status).toUpperCase();
  const offset = parseOffset(params.offset);

  return (
    <>
      <PageHeader
        title="Acessos"
        subtitle="Quem administra a plataforma, e quem tem conta em cada negócio."
      />

      <Panel title="Administradores da plataforma">
        <Suspense fallback={<TableSkeleton rows={3} />}>
          <Directory />
        </Suspense>
      </Panel>

      <Panel title="Contas de equipa">
        <div className="toolbar">
          <form method="get" action="/admin/access" className="toolbar">
            <div className="field">
              <label htmlFor="search">Procurar</label>
              <input
                className="input"
                id="search"
                name="search"
                type="search"
                placeholder="telefone ou id"
                defaultValue={search}
              />
            </div>
            {status ? (
              <input type="hidden" name="status" value={status} />
            ) : null}
            <button className="btn btn-navy" type="submit">
              Procurar
            </button>
          </form>
          <span className="toolbar__spacer" />
          <ChipFilter
            basePath="/admin/access"
            param="status"
            current={status}
            options={STATUSES}
            keep={{ search: search || undefined }}
          />
        </div>

        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={8} />}
        >
          <Staff search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>
    </>
  );
}
