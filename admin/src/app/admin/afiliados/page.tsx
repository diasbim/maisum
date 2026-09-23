import Link from 'next/link';
import { Suspense } from 'react';

import { fetchAffiliates } from '@/lib/admin-api';
import { createGlobalAffiliateAction } from '@/lib/actions';
import { MERCHANT_PAGE_SIZE } from '@/lib/merchant-list';
import { ActionForm, Field } from '../forms';
import {
  Badge,
  Card,
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  PageHeader,
  Pagination,
  Panel,
  TableSkeleton,
  formatDateTime,
  load,
  parseOffset,
  parseSearch,
} from '../ui';
import { ResultCount, SearchForm, TruncationNotice } from '../../negocio/records';

export const metadata = { title: 'Afiliados | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const AFFILIATES = '/admin/afiliados';

/**
 * The platform's directory of people who refer customers.
 *
 * One person is one record here, whatever number of businesses they refer for:
 * the id is derived from their phone, so adding somebody twice is a conflict
 * rather than a second identity. That is the whole reason this screen exists —
 * a business can add an affiliate and never know they were already suspended
 * somewhere else.
 *
 * What it never shows is a reachable number. `AdminAffiliateDto` carries a
 * mask and the last four digits, which is enough to recognise somebody in a
 * support call and not enough to contact them; the business that added them
 * holds the real one.
 */

const STATUSES = [
  { value: '', label: 'Todos' },
  { value: 'ACTIVE', label: 'Ativos' },
  { value: 'INACTIVE', label: 'Inativos' },
  { value: 'SUSPENDED', label: 'Suspensos' },
];

async function AffiliatesTable({
  search,
  status,
  offset,
}: {
  search: string;
  status: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchAffiliates({
      search: search || undefined,
      status: status || undefined,
      limit: MERCHANT_PAGE_SIZE,
      offset,
    }),
  );

  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    const filtered = Boolean(search || status);
    return (
      <EmptyState
        action={filtered ? <ClearFilters href={AFFILIATES} /> : undefined}
        message={
          filtered
            ? 'Nenhum afiliado corresponde a estes filtros.'
            : 'Ainda não há afiliados na plataforma.'
        }
      />
    );
  }

  return (
    <>
      <TruncationNotice truncated={result.data.truncated} />
      <ResultCount
        total={result.data.total}
        singular="afiliado"
        plural="afiliados"
      />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Afiliado</th>
              <th scope="col">Telefone</th>
              <th className="num" scope="col">
                Negócios
              </th>
              <th scope="col">Estado</th>
              <th scope="col">Criado</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((affiliate) => (
              <tr key={affiliate.id}>
                <td>
                  <Link href={`${AFFILIATES}/${encodeURIComponent(affiliate.id)}`}>
                    {affiliate.name || affiliate.id}
                  </Link>
                  <div style={{ color: 'var(--g500)', fontSize: '0.75rem' }}>
                    {affiliate.id}
                  </div>
                </td>
                <td>{affiliate.phone_masked}</td>
                <td className="num">{affiliate.merchant_count}</td>
                <td>
                  <Badge label={affiliate.status} />
                </td>
                <td>{formatDateTime(affiliate.created_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={AFFILIATES}
        query={{ search: search || undefined, status: status || undefined }}
        limit={MERCHANT_PAGE_SIZE}
        offset={offset}
        hasMore={result.data.hasMore}
        returned={result.data.items.length}
      />
    </>
  );
}

export default async function AdminAffiliatesPage({
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
        title="Afiliados"
        subtitle="Identidades da plataforma: uma pessoa, um registo, os negócios a que está ligada."
      />

      <Panel>
        <SearchForm
          action={AFFILIATES}
          label="Procurar afiliados"
          placeholder="Nome, id ou últimos 4 dígitos"
          value={search}
          keep={{ status: status || undefined }}
        />
        <ChipFilter
          basePath={AFFILIATES}
          param="status"
          current={status}
          options={STATUSES}
          keep={{ search: search || undefined }}
        />
      </Panel>

      <Panel>
        {/* Keyed on the filters so changing them shows the skeleton again
            instead of leaving the previous page's rows on screen. */}
        <Suspense
          key={`${search}|${status}|${offset}`}
          fallback={<TableSkeleton rows={8} />}
        >
          <AffiliatesTable search={search} status={status} offset={offset} />
        </Suspense>
      </Panel>

      <Panel>
        <Card
          title="Criar afiliado"
          hint="Cria a identidade sem a ligar a nenhum negócio. O id é derivado do telefone, por isso alguém que já exista responde com conflito em vez de ficar duplicado. A ligação a um negócio faz-se na ficha do afiliado."
        >
          <ActionForm
            action={createGlobalAffiliateAction}
            submitLabel="Criar afiliado"
            pendingLabel="A criar…"
            variant="btn-navy"
          >
            <div className="form-grid">
              <Field
                name="name"
                label="Nome"
                placeholder="Ana Matola"
                autoComplete="off"
                maxLength={60}
                required
              />
              <Field
                name="phone"
                label="Telemóvel"
                type="tel"
                inputMode="tel"
                placeholder="+258 84 123 4567"
                hint="Número de Moçambique. Não volta a ser mostrado depois de gravado."
                autoComplete="off"
                required
              />
            </div>
          </ActionForm>
        </Card>
      </Panel>
    </>
  );
}
