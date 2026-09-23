import Link from 'next/link';
import { notFound } from 'next/navigation';

import { AdminApiError, fetchLead } from '@/lib/prospecting-api';
import { formatUsd } from '@/lib/prospecting-form';
import {
  bandTone,
  claimLabel,
  claimTone,
  customerWarning,
  enrichmentEmptyMessage,
  enrichmentTone,
  relativeTime,
  statusTone,
} from '@/lib/prospecting-labels';
import {
  Badge,
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  formatDateTime,
} from '../../ui';
import { LeadActions } from './LeadActions';
import { OutreachPanel } from './OutreachPanel';

export const dynamic = 'force-dynamic';

/**
 * One lead, and everything known about it.
 *
 * The panels are ordered by the question an operator is actually asking, which
 * is not the order the data was gathered in: *should I call this business*
 * before *what do we know about it* before *what do I say*.
 *
 * The rule the whole page is built around is that a fact, an inference and an
 * absence look different. A claim carries how it was arrived at; an unknown is
 * listed rather than omitted; a guessed email address is shown and marked
 * unusable rather than being presented as a way to reach somebody.
 */

export async function generateMetadata({
  params,
}: {
  params: Promise<{ prospectId: string }>;
}) {
  const { prospectId } = await params;
  try {
    const detail = await fetchLead(prospectId);
    return { title: `${detail.prospect.name} | Prospeção | Portal MaisUm` };
  } catch {
    return { title: 'Lead | Prospeção | Portal MaisUm' };
  }
}

export default async function LeadDetailPage({
  params,
}: {
  params: Promise<{ prospectId: string }>;
}) {
  const { prospectId } = await params;

  let detail;
  try {
    detail = await fetchLead(prospectId);
  } catch (caught) {
    if (caught instanceof AdminApiError && caught.status === 404) notFound();
    return (
      <>
        <PageHeader title="Lead" />
        <Panel>
          <ErrorState
            message={
              caught instanceof AdminApiError
                ? caught.message
                : 'Erro inesperado ao carregar o lead.'
            }
          />
        </Panel>
      </>
    );
  }

  const { prospect, company, contacts, activities, analysis } = detail;
  const now = Date.now();
  const warning = customerWarning({
    status: prospect.status,
    suspectedMerchantId: prospect.suspected_merchant_id,
  });

  const decisionMakers = contacts.filter((contact) => contact.is_decision_maker);
  const others = contacts.filter((contact) => !contact.is_decision_maker);

  return (
    <>
      <PageHeader
        title={prospect.name}
        subtitle={[company?.industry_label, company?.city]
          .filter(Boolean)
          .join(' · ')}
        action={
          <Link className="btn btn-outline btn-sm" href="/admin/prospecao">
            ← Leads
          </Link>
        }
      />

      {/* The one thing that changes what an operator should do next, so it is
          above everything else rather than inside a panel they might not open. */}
      {warning === null ? null : (
        <div
          className={`notice ${warning.tone === 'red' ? 'notice--error' : ''}`}
          role="alert"
        >
          <span className="notice__mark" aria-hidden>
            ⚠
          </span>
          <span>
            {warning.text}
            {prospect.suspected_merchant_id === null ? null : (
              <>
                {' '}
                <Link
                  href={`/admin/merchants/${encodeURIComponent(prospect.suspected_merchant_id)}`}
                >
                  Ver o negócio
                </Link>
              </>
            )}
          </span>
        </div>
      )}

      {detail.outreach_blocked ? (
        <div className="notice notice--error" role="alert">
          <span className="notice__mark" aria-hidden>
            ⛔
          </span>
          <span>
            Este negócio não pode ser contactado. Não é possível gerar nem
            registar mensagens, e este estado não é reversível.
          </span>
        </div>
      ) : null}

      {/* ------------------------------------------------------ overview */}

      <Panel title="Resumo">
        <div className="grid">
          <Card title="Pontuação">
            <p className="metric">
              {prospect.lead_score ?? '—'}
              <span className="micro"> / 100</span>
            </p>
            {prospect.band_label === null ? null : (
              <Badge
                label={prospect.band_label}
                tone={bandTone(prospect.band).toUpperCase()}
              />
            )}
          </Card>
          <Card title="Estado">
            <Badge
              label={prospect.status_label}
              tone={statusTone(prospect.status).toUpperCase()}
            />
            <p className="micro">Origem: {prospect.source}</p>
          </Card>
          <Card title="Enriquecimento">
            <Badge
              label={prospect.enrichment_status_label}
              tone={enrichmentTone(prospect.enrichment_status).toUpperCase()}
            />
            <p className="micro">Custo deste lead: {formatUsd(prospect.spend_usd)}</p>
          </Card>
          <Card title="Última atividade">
            <p className="metric">{relativeTime(prospect.last_activity_at, now)}</p>
            <p className="micro">{formatDateTime(prospect.last_activity_at)}</p>
          </Card>
        </div>
      </Panel>

      {/* -------------------------------------------------- why MaisUm? */}

      <Panel title="Porquê a MaisUm?">
        {analysis === null ? (
          <EmptyState message="Este lead ainda não foi analisado. A análise usa o modelo e é cobrada uma vez por conjunto de dados — reabrir esta página não custa nada." />
        ) : (
          <>
            <Card title="Leitura">
              <p>{analysis.summary}</p>
            </Card>

            <Card title="Oportunidade de retenção">
              <p>{analysis.retention_opportunity || '—'}</p>
              <p className="micro">
                Funcionalidade a destacar: {analysis.recommended_product || '—'} ·
                Canal sugerido: {analysis.recommended_channel}
              </p>
            </Card>

            <Card
              title="Evidências"
              hint="Cada afirmação diz de onde veio e se foi observada ou deduzida. Uma dedução não é um facto sobre este negócio."
            >
              {analysis.evidence.length === 0 ? (
                <p className="muted">
                  Nenhuma afirmação com fonte verificável. Não é o mesmo que não
                  haver nada a dizer — é que nada do que foi dito podia ser
                  confirmado.
                </p>
              ) : (
                <ul className="list">
                  {analysis.evidence.map((item, index) => (
                    <li key={`${item.claim}-${index}`}>
                      <Badge
                        label={claimLabel(item.type)}
                        tone={claimTone(item.type).toUpperCase()}
                      />{' '}
                      {item.claim}{' '}
                      <span className="micro">
                        (
                        {/^https?:\/\//.test(item.source) ? (
                          <a href={item.source} rel="noreferrer noopener" target="_blank">
                            fonte
                          </a>
                        ) : (
                          item.source
                        )}
                        )
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </Card>

            <Card
              title="O que não se sabe"
              hint="Listado em vez de omitido: um painel vazio aqui leria como se tudo fosse conhecido."
            >
              {analysis.unknowns.length === 0 ? (
                <p className="muted">Nada assinalado como desconhecido.</p>
              ) : (
                <ul className="list">
                  {analysis.unknowns.map((unknown, index) => (
                    <li key={`${unknown}-${index}`}>{unknown}</li>
                  ))}
                </ul>
              )}
            </Card>

            <Card title="O que dizer">
              <p style={{ whiteSpace: 'pre-wrap' }}>{analysis.recommended_pitch}</p>
            </Card>

            <p className="micro">
              Modelo {analysis.model}, prompt v{analysis.prompt_version},{' '}
              {formatDateTime(analysis.created_at)}. Pontuação do modelo:{' '}
              {analysis.ai_fit_score}; pontuação do motor: {analysis.engine_score ?? '—'}.
              {analysis.score_divergence !== null &&
              Math.abs(analysis.score_divergence) >= 15
                ? ' As duas divergem bastante — a do motor é a que ordena a lista, e os critérios estão à vista.'
                : null}
            </p>
          </>
        )}
      </Panel>

      {/* ------------------------------------------------ decision makers */}

      <Panel title="Decisores">
        {decisionMakers.length === 0 ? (
          <EmptyState message={enrichmentEmptyMessage(prospect.enrichment_status)} />
        ) : (
          <div className="card card--flush scroll-x">
            <table>
              <thead>
                <tr>
                  <th scope="col">Pessoa</th>
                  <th scope="col">Cargo</th>
                  <th scope="col">Email</th>
                  <th scope="col">Telefone</th>
                  <th className="num" scope="col">
                    Confiança
                  </th>
                </tr>
              </thead>
              <tbody>
                {decisionMakers.map((contact) => (
                  <tr key={contact.id}>
                    <td>
                      {[contact.first_name, contact.last_name]
                        .filter(Boolean)
                        .join(' ') || <span className="muted">Nome desconhecido</span>}
                    </td>
                    <td>{contact.job_title ?? <span className="muted">—</span>}</td>
                    <td>
                      {contact.email === null ? (
                        <span className="muted">—</span>
                      ) : (
                        <>
                          {/* A guessed address is shown and marked, never
                              presented as a way to reach somebody. */}
                          <span
                            style={{
                              textDecoration: contact.email_usable
                                ? undefined
                                : 'line-through',
                            }}
                          >
                            {contact.email}
                          </span>{' '}
                          <Badge
                            label={contact.email_status_label}
                            tone={contact.email_usable ? 'ACTIVE' : 'PENDING'}
                          />
                        </>
                      )}
                    </td>
                    <td>{contact.phone ?? <span className="muted">—</span>}</td>
                    <td className="num">
                      {contact.confidence_score === null
                        ? '—'
                        : `${Math.round(contact.confidence_score * 100)}%`}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {others.length === 0 ? null : (
          <Card
            title="Outros contactos"
            hint="Guardados porque atendem o telefone, mas não são quem decide — não são estes a quem apresentar a MaisUm."
          >
            <ul className="list">
              {others.map((contact) => (
                <li key={contact.id}>
                  {contact.first_name ?? 'Sem nome'} — {contact.job_title ?? 'cargo desconhecido'}
                </li>
              ))}
            </ul>
          </Card>
        )}
      </Panel>

      {/* ------------------------------------------------------- company */}

      <Panel title="Negócio">
        {company === null ? (
          <EmptyState message="O registo do negócio não foi encontrado." />
        ) : (
          <DefinitionList
            entries={[
              ['Nome', company.name],
              ['Nome legal', company.legal_name ?? <span className="muted">—</span>],
              ['Setor', company.industry_label ?? company.industry ?? <span className="muted">desconhecido</span>],
              [
                'Pessoas',
                company.employee_count === null ? (
                  <span className="muted">desconhecido</span>
                ) : (
                  String(company.employee_count)
                ),
              ],
              ['Morada', company.address ?? <span className="muted">—</span>],
              [
                'Local',
                [company.city, company.province, company.country]
                  .filter(Boolean)
                  .join(', ') || <span className="muted">—</span>,
              ],
              ['Telefone', company.phone ?? <span className="muted">—</span>],
              ['WhatsApp', company.whatsapp ?? <span className="muted">—</span>],
              [
                'Site',
                company.website === null ? (
                  <span className="muted">—</span>
                ) : (
                  <a href={company.website} rel="noreferrer noopener" target="_blank">
                    {company.domain ?? company.website}
                  </a>
                ),
              ],
              [
                'Redes',
                [company.instagram_url, company.facebook_url, company.linkedin_url].filter(
                  Boolean,
                ).length === 0 ? (
                  <span className="muted">nenhuma encontrada</span>
                ) : (
                  <>
                    {[
                      ['Instagram', company.instagram_url],
                      ['Facebook', company.facebook_url],
                      ['LinkedIn', company.linkedin_url],
                    ]
                      .filter(([, url]) => url)
                      .map(([label, url]) => (
                        <a
                          key={label as string}
                          href={url as string}
                          rel="noreferrer noopener"
                          style={{ marginRight: 12 }}
                          target="_blank"
                        >
                          {label as string}
                        </a>
                      ))}
                  </>
                ),
              ],
              ['Descoberto via', company.source],
            ]}
          />
        )}
      </Panel>

      {/* ------------------------------------------------------ outreach */}

      <OutreachPanel
        prospectId={prospect.id}
        channels={detail.available_channels}
        blocked={detail.outreach_blocked}
      />

      {/* ------------------------------------------------------- actions */}

      <LeadActions
        prospectId={prospect.id}
        status={prospect.status}
        blocked={detail.outreach_blocked}
        hasAnalysis={analysis !== null}
      />

      {/* ------------------------------------------------------ timeline */}

      <Panel title="Histórico">
        {activities.length === 0 ? (
          <EmptyState message="Ainda não há atividade registada." />
        ) : (
          <ul className="timeline">
            {activities.map((activity) => (
              <li key={activity.id}>
                <span className="micro">{formatDateTime(activity.created_at)}</span>{' '}
                <strong>{activity.type}</strong> — {activity.description}
                {activity.created_by === null ? null : (
                  <span className="micro"> ({activity.created_by})</span>
                )}
              </li>
            ))}
          </ul>
        )}
      </Panel>
    </>
  );
}
