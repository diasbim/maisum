import { Suspense } from 'react';
import Link from 'next/link';

import {
  fetchAuditEvents,
  fetchMerchants,
  fetchOperationsSummary,
  type AdminOperationsSummaryDto,
} from '@/lib/admin-api';
import {
  Badge,
  EmptyState,
  ErrorState,
  formatDateTime,
  load,
  MetricsSkeleton,
  PageHeader,
  Panel,
  TableSkeleton,
} from './ui';

export const metadata = { title: 'Visão geral | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * Metrics grouped by the question they answer.
 *
 * A flat grid of ten numbers made "requerem atenção" sit between "equipa
 * ativa" and "eventos de uso", where it read as one more statistic. It is the
 * only number on this page that asks someone to do something, so it gets its
 * own group.
 */
const GROUPS: Array<{
  label: string;
  metrics: Array<[string, (s: AdminOperationsSummaryDto) => number]>;
}> = [
  {
    label: 'Plataforma',
    metrics: [
      ['Negócios', (s) => s.merchant_count],
      ['Subscrições ativas', (s) => s.active_subscription_count],
      ['Em avaliação', (s) => s.trial_subscription_count],
      ['Equipa ativa', (s) => s.active_staff_count],
    ],
  },
  {
    label: 'Requer atenção',
    metrics: [
      ['Subscrições em risco', (s) => s.attention_subscription_count],
      ['Recuperações abertas', (s) => s.open_recovery_task_count],
    ],
  },
  {
    label: 'Últimas 24 horas',
    metrics: [
      ['Eventos de uso', (s) => s.usage_events_24h],
      ['Relatórios de visita', (s) => s.visit_reports_24h],
      ['Respostas a inquéritos', (s) => s.survey_responses_24h],
      ['Eventos de auditoria', (s) => s.admin_audit_events_24h],
    ],
  },
];

async function MetricsPanel() {
  const result = await load(fetchOperationsSummary);
  if (result.error !== null) return <ErrorState message={result.error} />;

  const summary = result.data;
  return (
    <>
      {GROUPS.map((group) => (
        <div key={group.label} style={{ marginBottom: 22 }}>
          <p className="section-label">{group.label}</p>
          <div className="grid">
            {group.metrics.map(([label, read]) => (
              <div className="card" key={label}>
                <p className="metric-label">{label}</p>
                <p className="metric-value">{read(summary)}</p>
              </div>
            ))}
          </div>
        </div>
      ))}
      <p className="micro">
        Última auditoria: {formatDateTime(summary.last_admin_audit_at)}
        {' · '}
        Último evento de uso: {formatDateTime(summary.last_usage_event_at)}
      </p>
    </>
  );
}

async function RecentMerchants() {
  const result = await load(() => fetchMerchants({ limit: 8 }));
  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    return (
      <EmptyState message="Ainda não há negócios registados na plataforma." />
    );
  }

  return (
    <>
      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Negócio</th>
              <th scope="col">Plano</th>
              <th scope="col">Subscrição</th>
              <th scope="col">Equipa</th>
              <th scope="col">Atualizado</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((merchant) => (
              <tr key={merchant.id}>
                <td>
                  <Link
                    href={`/admin/merchants/${encodeURIComponent(merchant.id)}`}
                  >
                    {merchant.name || merchant.id}
                  </Link>
                </td>
                <td>{merchant.plan_name ?? merchant.plan_code ?? '—'}</td>
                <td>
                  <Badge label={merchant.subscription_status} />
                </td>
                <td>
                  {merchant.active_staff_count}/{merchant.staff_count}
                </td>
                <td>{formatDateTime(merchant.last_operational_update_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p style={{ marginTop: 8, fontSize: '0.82rem' }}>
        <Link href="/admin/merchants">Ver todos os negócios →</Link>
      </p>
    </>
  );
}

async function RecentAudit() {
  const result = await load(() => fetchAuditEvents({ limit: 8 }));
  if (result.error !== null) return <ErrorState message={result.error} />;

  if (result.data.items.length === 0) {
    return <EmptyState message="Sem eventos de auditoria registados." />;
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
              <th scope="col">Autor</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((event) => (
              <tr key={event.id}>
                <td>{formatDateTime(event.created_at)}</td>
                <td>{event.action}</td>
                <td>
                  {event.target_type}
                  {event.target_id ? ` · ${event.target_id}` : ''}
                </td>
                <td>{event.actor_app_user_id ?? event.actor_role ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p style={{ marginTop: 8, fontSize: '0.82rem' }}>
        <Link href="/admin/audit">Ver todo o histórico →</Link>
      </p>
    </>
  );
}

/**
 * Each panel streams on its own boundary.
 *
 * The three queries hit different tables and the merchant list is the slowest;
 * awaiting them together meant the whole page waited on it. Now the metrics
 * land first and the tables fill in under them.
 */
export default function OverviewPage() {
  return (
    <>
      <PageHeader
        title="Visão geral"
        subtitle="Estado operacional em tempo real."
      />

      <Panel>
        <Suspense fallback={<MetricsSkeleton />}>
          <MetricsPanel />
        </Suspense>
      </Panel>

      <Panel title="Negócios recentes">
        <Suspense fallback={<TableSkeleton />}>
          <RecentMerchants />
        </Suspense>
      </Panel>

      <Panel title="Auditoria recente">
        <Suspense fallback={<TableSkeleton />}>
          <RecentAudit />
        </Suspense>
      </Panel>
    </>
  );
}
