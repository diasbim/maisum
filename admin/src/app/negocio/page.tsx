import { Suspense } from 'react';
import Link from 'next/link';

import {
  fetchMyRiskScores,
  fetchMySales,
  fetchMyRecoveryTasks,
  fetchMyUsage,
} from '@/lib/merchant-api';
import { metricLabel } from '@/lib/merchant-labels';
import {
  Card,
  ErrorState,
  PageHeader,
  Panel,
  Skeleton,
  formatAmount,
  load,
} from '../admin/ui';

export const metadata = { title: 'Painel | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * The first screen, which used to be the business's own address.
 *
 * `/negocio` opened on the profile — name, phone, date of registration — the
 * one page here that answers no question anybody logs in to ask. The profile
 * is still a page, at `/negocio/perfil`, and this is what an owner sees
 * instead: what came in, who is slipping away, and what the plan has left.
 *
 * Each panel is its own boundary and its own request. They read different
 * subcollections and the slowest no longer holds the others: the takings land
 * first and the rest fill in beneath.
 */

function Metric({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint?: string;
}) {
  return (
    <div>
      <p className="micro">{label}</p>
      <p style={{ fontSize: '1.6rem', fontWeight: 800, margin: '2px 0 0' }}>
        {value}
      </p>
      {hint ? <p className="micro">{hint}</p> : null}
    </div>
  );
}

async function TakingsPanel() {
  const result = await load(() => fetchMySales({ limit: 1, offset: 0 }));
  if (result.error !== null) return <ErrorState message={result.error} />;

  const { totals } = result.data;
  return (
    <Card title="Vendas">
      <div className="metric-row">
        <Metric label="Registadas" value={totals.count.toLocaleString('pt-PT')} />
        <Metric label="Valor" value={formatAmount(totals.amount, 'MZN')} />
        <Metric
          label="Pontos atribuídos"
          value={totals.points.toLocaleString('pt-PT')}
        />
      </div>
      <p className="micro">
        <Link href="/negocio/vendas">Ver todas as vendas</Link>
      </p>
    </Card>
  );
}

async function RiskPanel() {
  const [scores, tasks] = await Promise.all([
    load(() => fetchMyRiskScores({ limit: 1, offset: 0 })),
    load(() => fetchMyRecoveryTasks({ status: 'OPEN', limit: 1, offset: 0 })),
  ]);
  if (scores.error !== null) return <ErrorState message={scores.error} />;

  // Critical alone would understate it; the board is worked from the top, and
  // the top is everything that is not green.
  const [red, orange] = await Promise.all([
    load(() => fetchMyRiskScores({ status: 'RED', limit: 1, offset: 0 })),
    load(() => fetchMyRiskScores({ status: 'ORANGE', limit: 1, offset: 0 })),
  ]);

  return (
    <Card title="Retenção">
      <div className="metric-row">
        <Metric
          label="Críticos"
          value={(red.error === null ? red.data.total : 0).toLocaleString('pt-PT')}
          hint="Há muito sem vir"
        />
        <Metric
          label="Em alerta"
          value={(orange.error === null ? orange.data.total : 0).toLocaleString('pt-PT')}
        />
        <Metric
          label="Tarefas por fazer"
          value={(tasks.error === null ? tasks.data.total : 0).toLocaleString('pt-PT')}
        />
      </div>
      <p className="micro">
        <Link href="/negocio/retencao">Ver clientes em risco</Link>
        {' · '}
        <Link href="/negocio/tarefas">Ver tarefas</Link>
      </p>
    </Card>
  );
}

async function PlanPanel() {
  const result = await load(fetchMyUsage);
  if (result.error !== null) return <ErrorState message={result.error} />;

  // Only what has a ceiling: a measure with no limit cannot be close to one,
  // and listing it here would just be a number with nothing to compare to.
  const limited = result.data
    .filter((balance) => balance.limit_value !== null && balance.limit_value > 0)
    .map((balance) => ({
      ...balance,
      share: balance.used / (balance.limit_value as number),
    }))
    .sort((a, b) => b.share - a.share)
    .slice(0, 3);

  return (
    <Card title="Plano">
      {limited.length === 0 ? (
        <p className="micro">Nenhuma medida do seu plano tem limite definido.</p>
      ) : (
        <div className="metric-row">
          {limited.map((balance) => (
            <Metric
              key={balance.id}
              label={metricLabel(balance.metric_key) ?? '—'}
              value={`${Math.round(Math.min(1, balance.share) * 100)}%`}
              hint={`${balance.used.toLocaleString('pt-PT')} de ${(balance.limit_value as number).toLocaleString('pt-PT')}`}
            />
          ))}
        </div>
      )}
      <p className="micro">
        <Link href="/negocio/plano">Ver o plano</Link>
      </p>
    </Card>
  );
}

export default function MerchantHomePage() {
  return (
    <>
      <PageHeader
        title="Painel"
        subtitle="Como está o seu negócio, num relance."
      />

      <Panel>
        <Suspense fallback={<Skeleton lines={3} />}>
          <TakingsPanel />
        </Suspense>
      </Panel>

      <Panel>
        <Suspense fallback={<Skeleton lines={3} />}>
          <RiskPanel />
        </Suspense>
      </Panel>

      <Panel>
        <Suspense fallback={<Skeleton lines={3} />}>
          <PlanPanel />
        </Suspense>
      </Panel>
    </>
  );
}
