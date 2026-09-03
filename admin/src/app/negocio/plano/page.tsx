import { Suspense } from 'react';

import { fetchMyEntitlements, fetchMyProfile } from '@/lib/merchant-api';
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
            <Badge key="status" label={business.subscription_status} />,
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

  return (
    <div className="card card--flush scroll-x">
      <table>
        <thead>
          <tr>
            <th scope="col">Funcionalidade</th>
            <th scope="col">Estado</th>
            <th scope="col">Limite</th>
            <th scope="col">Atualizado</th>
          </tr>
        </thead>
        <tbody>
          {entitlements.map((entitlement, index) => (
            <tr key={entitlement.id ?? entitlement.feature_key ?? index}>
              <td>{entitlement.feature_key ?? '—'}</td>
              <td>
                <Badge label={entitlement.is_enabled ? 'ATIVO' : 'INATIVO'} />
              </td>
              <td>
                {entitlement.limit_value == null
                  ? 'Sem limite'
                  : `${entitlement.limit_value}${entitlement.unit ? ` ${entitlement.unit}` : ''}`}
              </td>
              <td>{formatDateTime(entitlement.updated_at)}</td>
            </tr>
          ))}
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

      <Panel title="Funcionalidades">
        <Suspense fallback={<TableSkeleton rows={4} />}>
          <EntitlementsPanel />
        </Suspense>
      </Panel>
    </>
  );
}
