import Link from 'next/link';
import { Suspense } from 'react';

import {
  fetchEstimate,
  fetchLeads,
  fetchProspectingConfig,
  fetchUsage,
} from '@/lib/prospecting-api';
import { LEAD_PAGE_SIZE, formatUsd, formatUsdRange, leadListHref } from '@/lib/prospecting-form';
import {
  bandTone,
  budgetUsedPercent,
  emptyLeadsMessage,
  enrichmentTone,
  relativeTime,
  statusTone,
} from '@/lib/prospecting-labels';
import {
  Badge,
  Card,
  ChipFilter,
  ClearFilters,
  EmptyState,
  ErrorState,
  MetricsSkeleton,
  PageHeader,
  Pagination,
  Panel,
  TableSkeleton,
  load,
  parseOffset,
  parseSearch,
} from '../ui';
import { SearchForm as TextSearch, TruncationNotice } from '../../negocio/records';
import { FindLeadsForm } from './FindLeadsForm';

export const metadata = { title: 'Prospeção | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const PROSPECTING = '/admin/prospecao';

/**
 * The acquisition funnel.
 *
 * The console has always known the businesses that finished onboarding and
 * nothing about the ones that did not — the whole top of the funnel lived in a
 * WhatsApp inbox. This is where it lives now: businesses MaisUm might sell to,
 * scored, with the evidence for the score and the message to send attached.
 *
 * Three panels, in the order the work happens: what a search would cost, the
 * search itself, and what it found. The cost comes first deliberately. Every
 * other control on this page is free; the one at the top is not, and an
 * operator should meet the number before the button.
 */

/* ----------------------------------------------------------------- budget */

async function BudgetPanel() {
  const result = await load(() => fetchUsage({ limit: 1 }));
  if (result.error !== null) return <ErrorState message={result.error} />;

  const { spend } = result.data;
  const used = budgetUsedPercent(spend.month_usd, spend.monthly_budget_usd);

  return (
    <>
      {spend.paused ? (
        // Not an error state: the cap did its job. But it is the first thing
        // an operator needs to know, because every paid control below will
        // refuse until the month turns over.
        <div className="notice notice--error" role="status">
          <span className="notice__mark" aria-hidden>
            ⚠
          </span>
          <span>
            O orçamento mensal foi atingido. O enriquecimento pago está em pausa
            até ao próximo mês, ou até o orçamento ser aumentado em{' '}
            <Link href={`${PROSPECTING}/definicoes`}>Definições</Link>.
          </span>
        </div>
      ) : null}

      <div className="grid">
        <Card title="Gasto este mês" hint={spend.month_key}>
          <p className="metric">{formatUsd(spend.month_usd, spend.estimated)}</p>
          <p className="micro">
            de {formatUsd(spend.monthly_budget_usd)} · {used}% usado
          </p>
        </Card>
        <Card title="Gasto hoje">
          <p className="metric">{formatUsd(spend.day_usd, spend.estimated)}</p>
          <p className="micro">de {formatUsd(spend.daily_budget_usd)}</p>
        </Card>
        <Card title="Disponível este mês">
          <p className="metric">{formatUsd(spend.remaining_month_usd)}</p>
          <p className="micro">
            {spend.estimated
              ? 'Estimado: nenhum fornecedor comunica o custo real por chamada.'
              : 'Custo comunicado pelos fornecedores.'}
          </p>
        </Card>
      </div>
    </>
  );
}

/* ----------------------------------------------------------------- search */

async function FindLeadsPanel() {
  const [config, estimate] = await Promise.all([
    load(() => fetchProspectingConfig()),
    load(() => fetchEstimate({ maxLeads: 100, minScore: 60 })),
  ]);

  if (config.error !== null) return <ErrorState message={config.error} />;

  return (
    <FindLeadsForm
      industries={config.data.industries}
      sizes={config.data.sizes}
      maxLeadsOptions={config.data.max_leads_options}
      minScoreOptions={config.data.min_score_options}
      cities={config.data.cities}
      estimate={
        estimate.error !== null
          ? null
          : {
              range: formatUsdRange(estimate.data.min_usd, estimate.data.max_usd),
              likely: formatUsd(estimate.data.likely_usd),
              verified: estimate.data.verified,
              budget: formatUsd(estimate.data.monthly_budget_usd),
              remaining: formatUsd(estimate.data.remaining_this_month_usd),
            }
      }
    />
  );
}

/* ------------------------------------------------------------------ leads */

const STATUS_CHIPS = [
  { value: '', label: 'Todos' },
  { value: 'SCORED', label: 'Pontuados' },
  { value: 'READY_TO_CONTACT', label: 'Prontos' },
  { value: 'CONTACTED', label: 'Contactados' },
  { value: 'INTERESTED', label: 'Interessados' },
  { value: 'CUSTOMER', label: 'Clientes' },
  { value: 'NOT_A_FIT', label: 'Não encaixam' },
];

const BAND_CHIPS = [
  { value: '', label: 'Todas' },
  { value: 'PRIORITY', label: 'Prioritários' },
  { value: 'GOOD', label: 'Bons' },
  { value: 'NURTURE', label: 'A cultivar' },
  { value: 'LOW_FIT', label: 'Fraco encaixe' },
];

const SORTS = [
  { value: '', label: 'Maior pontuação' },
  { value: 'newest', label: 'Mais recentes' },
  { value: 'enriched', label: 'Enriquecidos há pouco' },
  { value: 'contacted', label: 'Atividade recente' },
];

type LeadFilters = {
  status: string;
  band: string;
  contact: string;
  sort: string;
  search: string;
  offset: number;
};

async function LeadsTable({ filters }: { filters: LeadFilters }) {
  const result = await load(() =>
    fetchLeads({
      status: filters.status || undefined,
      band: filters.band || undefined,
      contact: filters.contact || undefined,
      sort: filters.sort || undefined,
      search: filters.search || undefined,
      offset: filters.offset,
    }),
  );

  if (result.error !== null) return <ErrorState message={result.error} />;

  const filtered = Boolean(
    filters.status || filters.band || filters.contact || filters.search,
  );

  if (result.data.items.length === 0) {
    return (
      <EmptyState
        action={filtered ? <ClearFilters href={PROSPECTING} /> : undefined}
        message={emptyLeadsMessage({ filtered, jobRunning: false })}
      />
    );
  }

  const now = Date.now();

  return (
    <>
      <TruncationNotice truncated={result.data.paging?.truncated ?? false} />

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Negócio</th>
              <th scope="col">Setor</th>
              <th scope="col">Local</th>
              <th className="num" scope="col">
                Pontuação
              </th>
              <th className="num" scope="col">
                Retenção
              </th>
              <th scope="col">Decisor</th>
              <th scope="col">Estado</th>
              <th scope="col">Enriquecimento</th>
              <th scope="col">Origem</th>
              <th scope="col">Atividade</th>
            </tr>
          </thead>
          <tbody>
            {result.data.items.map((lead) => (
              <tr key={lead.id}>
                <td>
                  <Link href={`${PROSPECTING}/${encodeURIComponent(lead.id)}`}>
                    {lead.name}
                  </Link>
                  {lead.suspected_merchant_id !== null &&
                  lead.status !== 'EXISTING_CUSTOMER' ? (
                    <div className="micro" style={{ color: 'var(--amber)' }}>
                      Nome coincide com um cliente
                    </div>
                  ) : null}
                </td>
                <td>{lead.industry_label ?? <span className="muted">—</span>}</td>
                <td>{lead.city ?? <span className="muted">—</span>}</td>
                <td className="num">
                  {lead.lead_score === null ? (
                    <span className="muted">—</span>
                  ) : (
                    <Badge
                      label={`${lead.lead_score}`}
                      tone={bandTone(lead.band).toUpperCase()}
                    />
                  )}
                </td>
                <td className="num">
                  {lead.retention_potential_score ?? <span className="muted">—</span>}
                </td>
                <td>
                  {lead.decision_maker_count > 0 ? (
                    `${lead.decision_maker_count}`
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
                <td>
                  <Badge
                    label={lead.status_label}
                    tone={statusTone(lead.status).toUpperCase()}
                  />
                </td>
                <td>
                  <Badge
                    label={lead.enrichment_status_label}
                    tone={enrichmentTone(lead.enrichment_status).toUpperCase()}
                  />
                </td>
                <td>{lead.source}</td>
                <td title={new Date(lead.last_activity_at ?? 0).toISOString()}>
                  {relativeTime(lead.last_activity_at, now)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <Pagination
        basePath={PROSPECTING}
        query={{
          status: filters.status || undefined,
          band: filters.band || undefined,
          contact: filters.contact || undefined,
          sort: filters.sort || undefined,
          search: filters.search || undefined,
        }}
        limit={LEAD_PAGE_SIZE}
        offset={filters.offset}
        hasMore={result.data.paging?.has_more ?? false}
        returned={result.data.items.length}
      />
    </>
  );
}

/* ------------------------------------------------------------------- page */

export default async function ProspectingPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const filters: LeadFilters = {
    status: parseSearch(params.status).toUpperCase(),
    band: parseSearch(params.band).toUpperCase(),
    contact: parseSearch(params.contact),
    sort: parseSearch(params.sort),
    search: parseSearch(params.search),
    offset: parseOffset(params.offset),
  };

  const keep = {
    status: filters.status || undefined,
    band: filters.band || undefined,
    contact: filters.contact || undefined,
    sort: filters.sort || undefined,
    search: filters.search || undefined,
  };

  return (
    <>
      <PageHeader
        title="Prospeção"
        subtitle="Negócios que a MaisUm pode vir a servir, com a pontuação e as evidências que a sustentam."
        action={
          <>
            <Link className="btn btn-outline btn-sm" href={`${PROSPECTING}/funil`}>
              Funil
            </Link>
            <Link className="btn btn-outline btn-sm" href={`${PROSPECTING}/definicoes`}>
              Definições
            </Link>
          </>
        }
      />

      {/* The cost panel streams first and on its own boundary: it is the one
          thing on this page an operator must see before they press anything. */}
      <Panel title="Orçamento">
        <Suspense fallback={<MetricsSkeleton count={3} />}>
          <BudgetPanel />
        </Suspense>
      </Panel>

      <Panel title="Procurar negócios">
        <Suspense fallback={<TableSkeleton rows={4} />}>
          <FindLeadsPanel />
        </Suspense>
      </Panel>

      <Panel title="Leads">
        <TextSearch
          action={PROSPECTING}
          label="Procurar leads"
          placeholder="Nome do negócio"
          value={filters.search}
          keep={{ ...keep, search: undefined }}
        />

        <ChipFilter
          basePath={PROSPECTING}
          param="status"
          current={filters.status}
          options={STATUS_CHIPS}
          keep={{ ...keep, status: undefined }}
        />
        <ChipFilter
          basePath={PROSPECTING}
          param="band"
          current={filters.band}
          options={BAND_CHIPS}
          keep={{ ...keep, band: undefined }}
        />
        <ChipFilter
          basePath={PROSPECTING}
          param="contact"
          current={filters.contact}
          options={[
            { value: '', label: 'Com ou sem decisor' },
            { value: 'with', label: 'Com decisor' },
            { value: 'without', label: 'Sem decisor' },
          ]}
          keep={{ ...keep, contact: undefined }}
        />
        <ChipFilter
          basePath={PROSPECTING}
          param="sort"
          current={filters.sort}
          options={SORTS}
          keep={{ ...keep, sort: undefined }}
        />

        <Suspense
          key={leadListHref(filters)}
          fallback={<TableSkeleton rows={8} />}
        >
          <LeadsTable filters={filters} />
        </Suspense>
      </Panel>
    </>
  );
}
