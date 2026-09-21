import Link from 'next/link';
import { Suspense } from 'react';

import { fetchProspectingSettings, fetchUsage } from '@/lib/prospecting-api';
import { saveProspectingSettingsAction } from '@/lib/prospecting-actions';
import { formatUsd } from '@/lib/prospecting-form';
import { budgetUsedPercent } from '@/lib/prospecting-labels';
import { ActionForm, Field } from '../../forms';
import {
  Badge,
  Card,
  DefinitionList,
  ErrorState,
  MetricsSkeleton,
  PageHeader,
  Panel,
  TableSkeleton,
  formatDateTime,
  load,
} from '../../ui';

export const metadata = { title: 'Definições de prospeção | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * What the prospecting module is allowed to spend, and on what.
 *
 * The budgets live here rather than in an environment variable because a cap
 * that takes a deploy to lower is not a control an operator has. The feature
 * flags below are the opposite case — they decide whether a surface exists at
 * all, which is a deployment question — so they are shown and not editable.
 */

async function SpendPanel() {
  const result = await load(() => fetchUsage({ limit: 25 }));
  if (result.error !== null) return <ErrorState message={result.error} />;

  const { spend, rows } = result.data;
  const used = budgetUsedPercent(spend.month_usd, spend.monthly_budget_usd);

  return (
    <>
      <div className="grid">
        <Card title="Este mês" hint={spend.month_key}>
          <p className="metric">{formatUsd(spend.month_usd, spend.estimated)}</p>
          <p className="micro">
            {used}% de {formatUsd(spend.monthly_budget_usd)}
          </p>
        </Card>
        <Card title="Hoje">
          <p className="metric">{formatUsd(spend.day_usd, spend.estimated)}</p>
          <p className="micro">de {formatUsd(spend.daily_budget_usd)}</p>
        </Card>
        <Card title="Estado">
          <Badge
            label={spend.paused ? 'Em pausa' : 'Ativo'}
            tone={spend.paused ? 'SUSPENDED' : 'ACTIVE'}
          />
          <p className="micro">
            {spend.estimated
              ? 'Os totais são estimados: nenhum fornecedor comunica o custo real por chamada, por isso somam-se as estimativas.'
              : 'Totais comunicados pelos fornecedores.'}
          </p>
        </Card>
      </div>

      <Card
        title="Últimas chamadas"
        hint="Todas as chamadas pagas, incluindo as que falharam — os fornecedores cobram por chamadas que não devolvem nada."
      >
        {rows.length === 0 ? (
          <p className="muted">Nenhuma chamada este mês.</p>
        ) : (
          <div className="card card--flush scroll-x">
            <table>
              <thead>
                <tr>
                  <th scope="col">Quando</th>
                  <th scope="col">Fornecedor</th>
                  <th scope="col">Operação</th>
                  <th className="num" scope="col">
                    Estimado
                  </th>
                  <th className="num" scope="col">
                    Real
                  </th>
                  <th scope="col">Resultado</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((row) => (
                  <tr key={row.id}>
                    <td>{formatDateTime(row.created_at)}</td>
                    <td>{row.provider}</td>
                    <td>{row.operation}</td>
                    <td className="num">{formatUsd(row.estimated_cost)}</td>
                    <td className="num">
                      {row.actual_cost === null ? (
                        <span className="muted">não comunicado</span>
                      ) : (
                        formatUsd(row.actual_cost)
                      )}
                    </td>
                    <td>
                      {row.success ? (
                        <Badge label="OK" tone="ACTIVE" />
                      ) : (
                        <Badge label={row.error_code ?? 'Falhou'} tone="FAILED" />
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  );
}

async function SettingsPanel() {
  const result = await load(() => fetchProspectingSettings());
  if (result.error !== null) return <ErrorState message={result.error} />;

  const settings = result.data;

  return (
    <>
      <ActionForm
        action={saveProspectingSettingsAction}
        submitLabel="Guardar definições"
        pendingLabel="A guardar…"
        variant="btn-navy"
        hint="Deixe em branco o que não quiser alterar."
      >
        <div className="form-grid">
          <Field
            name="monthlyBudgetUsd"
            label="Orçamento mensal (USD)"
            defaultValue={String(settings.monthly_budget_usd)}
            hint="Quando é atingido, o enriquecimento pago pára e a consola diz porquê."
            inputMode="decimal"
          />
          <Field
            name="dailyBudgetUsd"
            label="Orçamento diário (USD)"
            defaultValue={String(settings.daily_budget_usd)}
            hint="Conta-se ao dia de Maputo, não em UTC."
            inputMode="decimal"
          />
          <Field
            name="maxEnrichmentCostPerLeadUsd"
            label="Custo máximo por lead (USD)"
            defaultValue={String(settings.max_enrichment_cost_per_lead_usd)}
            hint="Zero desliga completamente o enriquecimento pago."
            inputMode="decimal"
          />
          <Field
            name="minScoreForEnrichment"
            label="Pontuação mínima para enriquecer"
            defaultValue={String(settings.min_score_for_enrichment)}
            hint="Entre 1 e 100. Abaixo disto, um lead nunca é pago."
            inputMode="numeric"
          />
          <Field
            name="maxProspectsPerSearch"
            label="Máximo de negócios por procura"
            defaultValue={String(settings.max_prospects_per_search)}
            inputMode="numeric"
          />
          <Field
            name="cities"
            label="Cidades-alvo"
            defaultValue={settings.cities.join(', ')}
            hint="Separadas por vírgulas. Acrescentar uma cidade é tudo o que é preciso para passar a vender lá — não há nada no código que conheça Maputo."
          />
        </div>
      </ActionForm>

      <Card
        title="Funcionalidades"
        hint="Decidem se a superfície existe, o que é uma questão de instalação — por isso vivem no ambiente e mudá-las exige um deploy."
      >
        <DefinitionList
          entries={[
            [
              'Prospeção',
              <Badge
                key="p"
                label={settings.flags.prospecting_enabled ? 'Ligada' : 'Desligada'}
                tone={settings.flags.prospecting_enabled ? 'ACTIVE' : 'SUSPENDED'}
              />,
            ],
            [
              'Enriquecimento automático',
              <Badge
                key="a"
                label={settings.flags.auto_enrichment_enabled ? 'Ligado' : 'Desligado'}
                tone={settings.flags.auto_enrichment_enabled ? 'ACTIVE' : 'SUSPENDED'}
              />,
            ],
            [
              'Geração de mensagens',
              <Badge
                key="o"
                label={settings.flags.outreach_enabled ? 'Ligada' : 'Desligada'}
                tone={settings.flags.outreach_enabled ? 'ACTIVE' : 'SUSPENDED'}
              />,
            ],
            [
              'Apollo',
              <Badge
                key="ap"
                label={settings.flags.apollo_enabled ? 'Ligada' : 'Desligada'}
                tone={settings.flags.apollo_enabled ? 'ACTIVE' : 'SUSPENDED'}
              />,
            ],
            [
              'AIsa (pesquisa web)',
              <span key="ai">
                <Badge
                  label={settings.flags.aisa_enabled ? 'Ligada' : 'Desligada'}
                  tone={settings.flags.aisa_enabled ? 'ACTIVE' : 'SUSPENDED'}
                />{' '}
                <span className="muted">
                  Só pesquisa web — não procura pessoas, por isso não entra nas
                  cadeias de descoberta nem de contactos. É o único fornecedor
                  que comunica o custo real de cada chamada.
                </span>
              </span>,
            ],
            ['Ordem dos fornecedores', settings.provider_priority.join(' → ')],
            ['País', settings.country],
          ]}
        />
      </Card>
    </>
  );
}

export default function ProspectingSettingsPage() {
  return (
    <>
      <PageHeader
        title="Definições de prospeção"
        subtitle="Quanto o módulo pode gastar, e onde procura."
        action={
          <Link className="btn btn-outline btn-sm" href="/admin/prospecao">
            ← Prospeção
          </Link>
        }
      />

      <Panel title="Consumo">
        <Suspense fallback={<MetricsSkeleton count={3} />}>
          <SpendPanel />
        </Suspense>
      </Panel>

      <Panel title="Limites">
        <Suspense fallback={<TableSkeleton rows={6} />}>
          <SettingsPanel />
        </Suspense>
      </Panel>
    </>
  );
}
