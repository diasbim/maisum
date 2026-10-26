import { Suspense } from 'react';
import Link from 'next/link';

import { fetchAuditEvents } from '@/lib/admin-api';
import {
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  formatDateTime,
  load,
  PageHeader,
  Pagination,
  Panel,
  parseOffset,
  parseSearch,
  TableSkeleton,
} from '../ui';
import { AuditDetails } from './AuditDetails';

export const metadata = { title: 'Auditoria | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const PAGE_SIZE = 25;

/**
 * The target types the API writes today, from the `recordAdminAuditEvent`
 * calls in functions/src/index.ts. Listed explicitly so a type that has not
 * happened recently is still reachable as a filter.
 */
const TARGET_TYPES = [
  { value: '', label: 'Tudo' },
  { value: 'entitlement', label: 'Entitlements' },
  { value: 'plan', label: 'Planos' },
  { value: 'plan_feature', label: 'Funcionalidades' },
  { value: 'price', label: 'Preços' },
];

async function Events({
  targetType,
  merchantId,
  offset,
}: {
  targetType: string;
  merchantId: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchAuditEvents({
      targetType: targetType || undefined,
      merchantId: merchantId || undefined,
      limit: PAGE_SIZE,
      offset,
    }),
  );

  if (result.error !== null) return <ErrorState message={result.error} />;
  if (result.data.items.length === 0) {
    return (
      <EmptyState
        action={<ClearFilters href="/admin/audit" />}
        message="Nenhum evento corresponde a estes filtros."
      />
    );
  }

  return (
    <>
      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Quando</th>
              <th scope="col">Ação</th>
              <th scope="col">Alvo</th>
              <th scope="col">Negócio</th>
              <th scope="col">Autor</th>
              <th scope="col">Detalhe</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((event) => (
              <tr key={event.id}>
                <td style={{ whiteSpace: 'nowrap' }}>
                  {formatDateTime(event.created_at)}
                </td>
                <td>{event.action}</td>
                <td>
                  {event.target_type}
                  {event.target_id ? (
                    <div style={{ color: 'var(--g500)', fontSize: '0.75rem' }}>
                      {event.target_id}
                    </div>
                  ) : null}
                </td>
                <td>
                  {event.merchant_id ? (
                    <Link
                      href={`/admin/merchants/${encodeURIComponent(event.merchant_id)}`}
                    >
                      {event.merchant_id}
                    </Link>
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
                <td>
                  {event.actor_app_user_id ?? event.actor_role ?? '—'}
                  {event.actor_firebase_uid ? (
                    <div style={{ color: 'var(--g500)', fontSize: '0.75rem' }}>
                      {event.actor_firebase_uid}
                    </div>
                  ) : null}
                </td>
                <td>
                  <AuditDetails details={event.details} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination
        basePath="/admin/audit"
        query={{
          target_type: targetType || undefined,
          merchant_id: merchantId || undefined,
        }}
        limit={PAGE_SIZE}
        offset={offset}
        hasMore={result.data.paging?.has_more ?? false}
        returned={result.data.items.length}
      />
    </>
  );
}

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const targetType = parseSearch(params.target_type);
  const merchantId = parseSearch(params.merchant_id);
  const offset = parseOffset(params.offset);

  return (
    <>
      <PageHeader
        title="Auditoria"
        subtitle="Todas as ações administrativas, com autor e alteração."
      />

      <div className="toolbar">
        <ChipFilter
          basePath="/admin/audit"
          param="target_type"
          current={targetType}
          options={TARGET_TYPES}
          keep={{ merchant_id: merchantId || undefined }}
        />
        {merchantId ? (
          <>
            <span className="toolbar__spacer" />
            <Link className="btn btn-outline btn-sm" href="/admin/audit">
              Limpar filtro de negócio
            </Link>
          </>
        ) : null}
      </div>

      <Panel>
        <Suspense
          key={`${targetType}|${merchantId}|${offset}`}
          fallback={<TableSkeleton rows={10} />}
        >
          <Events
            targetType={targetType}
            merchantId={merchantId}
            offset={offset}
          />
        </Suspense>
      </Panel>
    </>
  );
}
