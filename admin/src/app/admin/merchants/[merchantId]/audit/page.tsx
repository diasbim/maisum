import { Suspense } from 'react';

import { fetchAuditEvents } from '@/lib/admin-api';
import {
  EmptyState,
  Pagination,
  TableSkeleton,
  formatDateTime,
  load,
  parseOffset,
} from '../../../ui';
import { AuditDetails } from '../../../audit/AuditDetails';

export const metadata = { title: 'Auditoria do negócio | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const PAGE_SIZE = 25;

async function Events({
  merchantId,
  offset,
}: {
  merchantId: string;
  offset: number;
}) {
  const result = await load(() =>
    fetchAuditEvents({ merchantId, limit: PAGE_SIZE, offset }),
  );

  if (result.error !== null) return <p className="error">{result.error}</p>;
  if (result.data.items.length === 0) {
    return <EmptyState message="Sem eventos de auditoria para este negócio." />;
  }

  return (
    <>
      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th>Quando</th>
              <th>Ação</th>
              <th>Alvo</th>
              <th>Autor</th>
              <th>Detalhe</th>
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
                  {event.target_id ? ` · ${event.target_id}` : ''}
                </td>
                <td>{event.actor_app_user_id ?? event.actor_role ?? '—'}</td>
                <td>
                  <AuditDetails details={event.details} />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <Pagination
        basePath={`/admin/merchants/${encodeURIComponent(merchantId)}/audit`}
        limit={PAGE_SIZE}
        offset={offset}
        hasMore={result.data.paging?.has_more ?? false}
        returned={result.data.items.length}
      />
    </>
  );
}

export default async function MerchantAuditPage({
  params,
  searchParams,
}: {
  params: Promise<{ merchantId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { merchantId } = await params;
  const offset = parseOffset((await searchParams).offset);

  return (
    <Suspense key={offset} fallback={<TableSkeleton rows={8} />}>
      <Events merchantId={merchantId} offset={offset} />
    </Suspense>
  );
}
