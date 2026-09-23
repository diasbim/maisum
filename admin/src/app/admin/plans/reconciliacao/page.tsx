import { Suspense } from 'react';

import { savePlanFeatureAction } from '@/lib/actions';
import { fetchPlans, type AdminPlanDto } from '@/lib/admin-api';
import {
  promisedKeys,
  readCatalog,
  type Catalog,
  type DeclaredPlan,
} from '@/lib/plan-catalog';
import { ActionForm } from '../../forms';
import {
  Card,
  ErrorState,
  PageHeader,
  Panel,
  Skeleton,
  Verdict,
  load,
  type VerdictTone,
} from '../../ui';

export const metadata = { title: 'Reconciliação | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * What the landing page promises, against what the database provisions.
 *
 * Two sources that drift silently: `docs/index.html` sells a plan, and
 * `plan_features` decides what that plan actually unlocks. Nothing joins them
 * at runtime, so a promise can outlive the entitlement behind it and only a
 * customer complaint would surface it. `docs/plans.json` is the declared
 * bridge; this page checks it against the live catalogue.
 */

type Row = {
  text: string;
  tone: VerdictTone;
  label: string;
  title: string;
  /**
   * Present only when the gap can be closed with one click: the plan already
   * exists in the database and is only missing this feature key. A promise
   * whose plan does not exist yet has nothing here — that gap needs a plan
   * created on `/admin/plans` first, not a feature toggled on one.
   */
  fixable?: {
    planCode: string;
    planVersion: number;
    featureKey: string;
  };
};

function provisionedKeys(plan: AdminPlanDto | undefined): Set<string> {
  if (!plan) return new Set();
  return new Set(
    plan.features.filter((f) => f.is_enabled).map((f) => f.feature_key),
  );
}

function evaluate(
  catalog: Catalog,
  declared: DeclaredPlan,
  live: AdminPlanDto | undefined,
): Row[] {
  const provisioned = provisionedKeys(live);

  return declared.promises.map((promise): Row => {
    switch (promise.backing) {
      case 'core':
        return {
          text: promise.text,
          tone: 'ok',
          label: 'Base',
          title: 'Capacidade base, disponível em todos os planos por desenho.',
        };

      case 'inherits': {
        const from = promise.inheritsFrom ?? '?';
        // An inherited promise is only as sound as the plan it points at. If
        // that plan is not in the catalogue the claim rests on nothing.
        const exists = catalog.plans.some((plan) => plan.code === from);
        return exists
          ? {
              text: promise.text,
              tone: 'ok',
              label: `Herda ${from}`,
              title: `Reafirma o plano ${from}. Não é capacidade nova.`,
            }
          : {
              text: promise.text,
              tone: 'gap',
              label: `Herda ${from} (inexistente)`,
              title: `O plano ${from} não existe no catálogo declarado.`,
            };
      }

      case 'feature_key': {
        const key = promise.featureKey ?? '';
        if (provisioned.has(key)) {
          return {
            text: promise.text,
            tone: 'ok',
            label: key,
            title: `Provisionada: ${key} está ativa neste plano.`,
          };
        }
        return {
          text: promise.text,
          tone: 'gap',
          label: key || 'sem chave',
          title: live
            ? `Prometida mas não provisionada: ${key} não está ativa em ${declared.code}.`
            : `O plano ${declared.code} não existe na base de dados.`,
          fixable:
            live && key && live.version != null
              ? { planCode: declared.code, planVersion: live.version, featureKey: key }
              : undefined,
        };
      }

      case 'none':
        return {
          text: promise.text,
          tone: 'open',
          label: promise.decision ?? 'em aberto',
          title:
            'Sem contrapartida técnica. Depende de uma decisão comercial ainda por tomar.',
        };
    }
  });
}

/**
 * Closes one gap in place: turns the feature on, unlimited, on the plan that
 * already exists. Nothing here is typed by the operator — every value is
 * already known from the row it appears on — so the form carries only hidden
 * fields and a submit button.
 */
function ProvisionButton({
  fixable,
}: {
  fixable: { planCode: string; planVersion: number; featureKey: string };
}) {
  return (
    <ActionForm
      action={savePlanFeatureAction}
      submitLabel="Provisionar agora"
      pendingLabel="A provisionar…"
      variant="btn-outline btn-sm"
      hint="Ativa sem limite. Pode ajustar o limite depois em Planos."
    >
      <input type="hidden" name="plan_code" value={fixable.planCode} />
      <input type="hidden" name="plan_version" value={fixable.planVersion} />
      <input type="hidden" name="feature_key" value={fixable.featureKey} />
      <input type="hidden" name="is_enabled" value="true" />
    </ActionForm>
  );
}

async function Matrix() {
  const [catalogResult, liveResult] = await Promise.all([
    readCatalog(),
    load(fetchPlans),
  ]);

  if (catalogResult.error !== null) return <ErrorState message={catalogResult.error} />;
  if (liveResult.error !== null) return <ErrorState message={liveResult.error} />;

  const catalog = catalogResult.catalog;
  const live = liveResult.data;

  // Only the active version of each code: an old inactive version's features
  // are not what a new customer gets.
  const liveByCode = new Map<string, AdminPlanDto>();
  for (const plan of live) {
    if (plan.is_active) liveByCode.set(plan.plan_code, plan);
  }

  const advertised = catalog.plans.filter((plan) => plan.advertised);
  const gaps: string[] = [];

  const sections = advertised.map((declared) => {
    const rows = evaluate(catalog, declared, liveByCode.get(declared.code));
    for (const row of rows) {
      if (row.tone === 'gap') gaps.push(`${declared.publicName}: ${row.text}`);
    }

    // The reverse direction: provisioned but never advertised. Not a defect —
    // it is capacity being given away without being sold, which is worth
    // seeing before a pricing conversation.
    const promised = promisedKeys(catalog, declared.code);
    const unadvertised = [...provisionedKeys(liveByCode.get(declared.code))]
      .filter((key) => !promised.has(key))
      .sort();

    return { declared, rows, unadvertised };
  });

  return (
    <>
      {gaps.length > 0 ? (
        <div className="notice notice--error" style={{ marginBottom: 20 }}>
          <span className="notice__mark" aria-hidden>
            ⚠
          </span>
          <span>
            {gaps.length} promessa{gaps.length === 1 ? '' : 's'} sem
            provisionamento: {gaps.join(' · ')}
          </span>
        </div>
      ) : (
        <div className="notice notice--ok" style={{ marginBottom: 20 }}>
          <span className="notice__mark" aria-hidden>
            ✓
          </span>
          <span>
            Tudo o que os planos anunciados prometem tem contrapartida na base
            de dados ou está registado como decisão em aberto.
          </span>
        </div>
      )}

      <div className="stack">
        {sections.map(({ declared, rows, unadvertised }) => (
          <Card
            key={declared.code}
            title={`${declared.publicName} (${declared.code})`}
            hint={declared.tagline}
          >
            <div className="card card--flush scroll-x">
              <table className="matrix">
                <thead>
                  <tr>
                    <th scope="col">Promessa pública</th>
                    <th scope="col">Contrapartida</th>
                    <th scope="col">Ação</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row) => (
                    <tr key={row.text}>
                      <td>{row.text}</td>
                      <td>
                        <Verdict
                          tone={row.tone}
                          label={row.label}
                          title={row.title}
                        />
                      </td>
                      <td>
                        {row.fixable ? (
                          <ProvisionButton fixable={row.fixable} />
                        ) : (
                          <span className="muted">—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {unadvertised.length > 0 ? (
              <p className="micro" style={{ marginTop: 10 }}>
                Provisionadas mas não anunciadas:{' '}
                {unadvertised.map((key) => (
                  <code className="inline" key={key} style={{ marginRight: 4 }}>
                    {key}
                  </code>
                ))}
              </p>
            ) : null}
          </Card>
        ))}
      </div>

      {catalog.openDecisions.length > 0 ? (
        <Panel title="Decisões em aberto">
          <div className="stack">
            {catalog.openDecisions.map((decision) => (
              <Card
                key={decision.id}
                title={`${decision.id} · afeta ${decision.affects.join(', ')}`}
              >
                <p style={{ margin: '0 0 10px', fontSize: '0.86rem' }}>
                  {decision.summary}
                </p>
                <ul style={{ margin: 0, paddingLeft: 16, fontSize: '0.82rem' }}>
                  {decision.options.map((option) => (
                    <li key={option}>{option}</li>
                  ))}
                </ul>
              </Card>
            ))}
          </div>
        </Panel>
      ) : null}

      <p className="micro" style={{ marginTop: 24 }}>
        Fonte declarada: <code className="inline">docs/plans.json</code> ·
        validada em CI por{' '}
        <code className="inline">tool/check_plan_catalog.dart</code>
      </p>
    </>
  );
}

export default function ReconciliationPage() {
  return (
    <>
      <PageHeader
        title="Reconciliação comercial"
        subtitle="O que a landing page promete, contra o que a base de dados provisiona."
      />

      <Panel>
        <Suspense fallback={<Skeleton lines={10} />}>
          <Matrix />
        </Suspense>
      </Panel>
    </>
  );
}
