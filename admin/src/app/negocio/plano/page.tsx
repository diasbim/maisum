import { Suspense } from 'react';

import {
  fetchMyEntitlements,
  fetchMyProfile,
  fetchMyUsage,
} from '@/lib/merchant-api';
import { featureLabel, metricLabel, subscriptionLabel } from '@/lib/merchant-labels';
import {
  Badge,
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  Skeleton,
  TableSkeleton,
  formatDateTime,
  load,
} from '../../admin/ui';

export const metadata = { title: 'Plano | MaisUm' };
export const dynamic = 'force-dynamic';

async function PlanPanel() {
  const result = await load(fetchMyProfile);
  if (result.error !== null) return <ErrorState message={result.error} />;
  if (!result.data) {
    return <EmptyState message="Ainda não há um plano associado a este negócio." />;
  }

  const business = result.data;
  return (
    <Card title="Subscrição">
      <DefinitionList
        entries={[
          ['Plano', business.plan_name ?? business.plan_code ?? '—'],
          [
            'Estado',
            // The tone is read from the stored code, not from the translated
            // label, or every state would come out the same neutral colour.
            <Badge
              key="status"
              label={subscriptionLabel(business.subscription_status)}
              tone={business.subscription_status}
            />,
          ],
          ['Código', business.plan_code ? <code key="c">{business.plan_code}</code> : '—'],
        ]}
      />
    </Card>
  );
}

/**
 * What the plan actually grants, feature by feature.
 *
 * The console has shown this to internal staff for a while; the business it
 * describes could not see it. That asymmetry is the reason this screen exists
 * in the first phase rather than a later one.
 */
async function EntitlementsPanel() {
  const result = await load(fetchMyEntitlements);
  if (result.error !== null) return <ErrorState message={result.error} />;

  const entitlements = result.data;
  if (entitlements.length === 0) {
    return (
      <EmptyState message="Este negócio recebe exatamente o que o plano concede, sem exceções configuradas." />
    );
  }

  // A ceiling on an entitlement is the exception, not the rule: the plans in
  // use put their limits on the measures above, so this column stood at "Sem
  // limite" for every row on every plan. Shown only when something fills it.
  const temLimite = entitlements.some(
    (entitlement) => entitlement.limit_value != null,
  );

  return (
    <div className="card card--flush scroll-x">
      <table>
        <thead>
          <tr>
            <th scope="col">Funcionalidade</th>
            <th scope="col">Estado</th>
            {temLimite ? <th scope="col">Limite</th> : null}
            <th scope="col">Atualizado</th>
          </tr>
        </thead>
        <tbody>
          {entitlements.map((entitlement, index) => (
            <tr key={entitlement.id ?? entitlement.feature_key ?? index}>
              <td>{featureLabel(entitlement.feature_key) ?? '—'}</td>
              {/*
                Three states, not two. `is_enabled` is nullable on purpose —
                `asBool` in the Functions keeps "not stored" apart from
                "stored false", because a missing flag should not read as
                disabled. Collapsing it with `? :` told a business a feature
                they pay for was switched off.
              */}
              <td>
                <Badge
                  label={
                    // `== null`, like `limit_value` below: the API leaves the
                    // key out altogether rather than sending null, so a strict
                    // check would put the row straight back on "Inativo".
                    entitlement.is_enabled == null
                      ? null
                      : entitlement.is_enabled
                        ? 'Ativo'
                        : 'Inativo'
                  }
                  tone={entitlement.is_enabled ? 'ACTIVE' : 'INACTIVE'}
                />
              </td>
              {temLimite ? (
                <td>
                  {entitlement.limit_value == null
                    ? 'Sem limite'
                    : `${entitlement.limit_value}${entitlement.unit ? ` ${entitlement.unit}` : ''}`}
                </td>
              ) : null}
              <td>{formatDateTime(entitlement.updated_at)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/**
 * What the plan has actually consumed, against what it allows.
 *
 * The entitlements table says the ceiling — `5 per_month` — and said nothing
 * about how much of it was gone. A limit without a count is the less useful
 * half: nobody plans around a number they cannot watch themselves approach.
 */
async function UsagePanel() {
  const result = await load(fetchMyUsage);
  if (result.error !== null) return <ErrorState message={result.error} />;

  const balances = result.data;
  if (balances.length === 0) {
    return <EmptyState message="Ainda não há consumo medido neste período." />;
  }

  return (
    <div className="card card--flush scroll-x">
      <table>
        <thead>
          <tr>
            <th scope="col">Medida</th>
            <th scope="col" style={{ textAlign: 'right' }}>
              Usado
            </th>
            <th scope="col" style={{ textAlign: 'right' }}>
              Limite
            </th>
            <th scope="col">Período termina</th>
          </tr>
        </thead>
        <tbody>
          {balances.map((balance) => {
            const limit = balance.limit_value;
            // A null limit is "no ceiling", which is not zero, and must not
            // be drawn as a share that is permanently full.
            const share =
              limit !== null && limit > 0
                ? Math.min(1, balance.used / limit)
                : null;
            return (
              <tr key={balance.id}>
                <td>{metricLabel(balance.metric_key) ?? '—'}</td>
                <td style={{ textAlign: 'right' }}>
                  {balance.used.toLocaleString('pt-PT')}
                  {share !== null ? (
                    <span className="micro"> ({Math.round(share * 100)}%)</span>
                  ) : null}
                </td>
                <td style={{ textAlign: 'right' }}>
                  {limit === null ? (
                    <span className="muted">Sem limite</span>
                  ) : (
                    limit.toLocaleString('pt-PT')
                  )}
                </td>
                <td>{formatDateTime(balance.window_end)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}

export default function MerchantPlanPage() {
  return (
    <>
      <PageHeader
        title="Plano"
        subtitle="O que o seu plano concede e onde estão os limites."
      />

      <Panel>
        <Suspense fallback={<Skeleton lines={4} />}>
          <PlanPanel />
        </Suspense>
      </Panel>

      <Panel title="Consumo">
        <Suspense fallback={<TableSkeleton rows={3} />}>
          <UsagePanel />
        </Suspense>
      </Panel>

      <Panel title="Funcionalidades">
        <Suspense fallback={<TableSkeleton rows={4} />}>
          <EntitlementsPanel />
        </Suspense>
      </Panel>
    </>
  );
}
