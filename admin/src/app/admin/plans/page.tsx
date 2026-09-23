import { Suspense } from 'react';

import {
  savePlanAction,
  savePlanFeatureAction,
  savePriceAction,
} from '@/lib/actions';
import { fetchPlans } from '@/lib/admin-api';
import { ActionForm, Check, Field, Select } from '../forms';
import {
  Badge,
  Card,
  EmptyState,
  ErrorState,
  formatAmount,
  formatDateTime,
  load,
  PageHeader,
  Panel,
  Skeleton,
} from '../ui';

export const metadata = { title: 'Planos | Portal MaisUm' };
export const dynamic = 'force-dynamic';

async function Catalogue() {
  const result = await load(fetchPlans);
  if (result.error !== null) return <ErrorState message={result.error} />;
  if (result.data.length === 0) {
    return <EmptyState message="Nenhum plano no catálogo." />;
  }

  return (
    <div className="stack">
      {result.data.map((plan) => {
        const enabled = plan.features.filter((f) => f.is_enabled);
        return (
          <div className="card" key={`${plan.plan_code}-${plan.version}`}>
            <div
              style={{
                display: 'flex',
                alignItems: 'baseline',
                gap: 8,
                flexWrap: 'wrap',
              }}
            >
              <h3 style={{ margin: 0, fontSize: '1rem' }}>
                {plan.name ?? plan.plan_code}
              </h3>
              <code className="inline">
                {plan.plan_code} · v{plan.version ?? '—'}
              </code>
              <Badge label={plan.is_active ? 'ACTIVE' : 'INATIVO'} />
              <span
                style={{
                  marginLeft: 'auto',
                  color: 'var(--g500)',
                  fontSize: '0.75rem',
                }}
              >
                Atualizado {formatDateTime(plan.updated_at)}
              </span>
            </div>

            <div className="split" style={{ marginTop: 14 }}>
              <div>
                <p className="section-label">Preços</p>
                {plan.prices.length === 0 ? (
                  <p className="muted" style={{ fontSize: '0.86rem' }}>
                    Sem preços definidos.
                  </p>
                ) : (
                  <ul style={{ margin: 0, paddingLeft: 16, fontSize: '0.86rem' }}>
                    {plan.prices.map((price, index) => (
                      <li key={`${price.pricing_version}-${index}`}>
                        {formatAmount(price.amount, price.currency)}
                        {price.billing_period ? ` / ${price.billing_period}` : ''}
                        {price.is_active ? '' : ' (inativo)'}
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              <div>
                <p className="section-label">
                  Funcionalidades ({enabled.length}/{plan.features.length})
                </p>
                {plan.features.length === 0 ? (
                  <p className="muted" style={{ fontSize: '0.86rem' }}>
                    Sem funcionalidades configuradas.
                  </p>
                ) : (
                  <ul
                    style={{
                      margin: 0,
                      padding: 0,
                      listStyle: 'none',
                      fontSize: '0.86rem',
                      display: 'grid',
                      gap: 4,
                    }}
                  >
                    {plan.features.map((feature) => (
                      <li key={feature.feature_key}>
                        <span
                          aria-hidden
                          style={{
                            color: feature.is_enabled
                              ? 'var(--green)'
                              : 'var(--g500)',
                          }}
                        >
                          {feature.is_enabled ? '✔' : '✕'}
                        </span>{' '}
                        <span
                          style={{
                            color: feature.is_enabled ? 'inherit' : 'var(--g500)',
                          }}
                        >
                          {feature.feature_key}
                        </span>
                        {feature.limit_value != null ? (
                          <span className="muted">
                            {' '}
                            · limite {feature.limit_value}
                            {feature.unit ? ` ${feature.unit}` : ''}
                          </span>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default function PlansPage() {
  return (
    <>
      <PageHeader
        title="Catálogo de planos"
        subtitle="Planos, preços e funcionalidades provisionadas."
      />

      <Panel>
        <Suspense fallback={<Skeleton lines={8} />}>
          <Catalogue />
        </Suspense>
      </Panel>

      <Panel title="Editar catálogo">
        <div className="stack">
          <Card
            title="Plano"
            hint={
              <>
                Gravar uma versão como ativa desativa as outras versões do mesmo
                código. Um código e versão que já existam são atualizados, não
                duplicados.
              </>
            }
          >
            <ActionForm
              action={savePlanAction}
              submitLabel="Gravar plano"
              pendingLabel="A gravar…"
            >
              <div className="form-grid">
                <Field
                  name="plan_code"
                  label="Código"
                  placeholder="pro"
                  required
                  autoComplete="off"
                />
                <Field
                  name="version"
                  label="Versão"
                  type="number"
                  step="1"
                  min="1"
                  defaultValue="1"
                  required
                />
                <Field
                  name="name"
                  label="Nome público"
                  placeholder="Pro"
                  required
                />
                <Check
                  name="is_active"
                  label="Ativo"
                  hint="Desativa as outras versões deste código."
                  defaultChecked
                />
              </div>
            </ActionForm>
          </Card>

          <Card
            title="Preço"
            hint="Valores em unidades inteiras da moeda, não em cêntimos."
          >
            <ActionForm
              action={savePriceAction}
              submitLabel="Gravar preço"
              pendingLabel="A gravar…"
            >
              <div className="form-grid">
                <Field
                  name="plan_code"
                  label="Código do plano"
                  placeholder="pro"
                  required
                  autoComplete="off"
                />
                <Field
                  name="pricing_version"
                  label="Versão de preço"
                  type="number"
                  step="1"
                  min="1"
                  defaultValue="1"
                  required
                />
                <Field
                  name="amount"
                  label="Valor"
                  type="number"
                  step="1"
                  min="0"
                  required
                />
                <Field
                  name="currency"
                  label="Moeda"
                  defaultValue="MZN"
                  required
                />
                <Select
                  name="billing_period"
                  label="Periodicidade"
                  defaultValue="monthly"
                  options={[
                    { value: 'monthly', label: 'Mensal' },
                    { value: 'yearly', label: 'Anual' },
                  ]}
                />
                <Check name="is_active" label="Ativo" defaultChecked />
              </div>
            </ActionForm>
          </Card>

          <Card
            title="Funcionalidade do plano"
            hint="A versão do plano tem de existir. Isto define o que o plano concede; para abrir uma exceção a um só negócio use o separador Entitlements desse negócio."
          >
            <ActionForm
              action={savePlanFeatureAction}
              submitLabel="Gravar funcionalidade"
              pendingLabel="A gravar…"
            >
              <div className="form-grid">
                <Field
                  name="plan_code"
                  label="Código do plano"
                  placeholder="pro"
                  required
                  autoComplete="off"
                />
                <Field
                  name="plan_version"
                  label="Versão do plano"
                  type="number"
                  step="1"
                  min="1"
                  defaultValue="1"
                  required
                />
                <Field
                  name="feature_key"
                  label="Funcionalidade"
                  placeholder="engage_view_risk"
                  required
                  autoComplete="off"
                />
                <Field
                  name="limit_value"
                  label="Limite"
                  type="number"
                  step="1"
                  placeholder="em branco = sem limite"
                />
                <Field name="unit" label="Unidade" placeholder="por mês" />
                <Check name="is_enabled" label="Ativa" defaultChecked />
              </div>
            </ActionForm>
          </Card>
        </div>
      </Panel>
    </>
  );
}
