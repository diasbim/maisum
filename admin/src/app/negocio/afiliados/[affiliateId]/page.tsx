import Link from 'next/link';
import { Suspense } from 'react';
import { notFound } from 'next/navigation';

import {
  fetchMyAffiliate,
  fetchMyAffiliateMetrics,
  fetchMyAffiliateRewards,
} from '@/lib/merchant-api';
import { getMerchantPermissions, getMerchantSession } from '@/lib/merchant-session';
import { setAffiliateActiveAction } from '@/lib/merchant-actions';
import { affiliateStanding, lastAffiliateActivityAt } from '@/lib/affiliate-form';
import {
  rewardStatusLabel,
  rewardStatusTone,
  rewardTypeLabel,
} from '@/lib/merchant-labels';
import { ActionForm } from '../../../admin/forms';
import {
  Badge,
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  MetricsSkeleton,
  PageHeader,
  Panel,
  TableSkeleton,
  formatDateTime,
  load,
} from '../../../admin/ui';
import {
  AFFILIATES_PATH,
  AffiliateMetrics,
  AffiliateStanding,
  BackToAffiliates,
  CodeBadge,
  READ_ONLY_REASON_ID,
  ReadOnlyNotice,
  ShareCode,
  benefitText,
} from '../afiliados';

export const metadata = { title: 'Afiliado | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * One affiliate: their code, what it is worth, and what it has produced.
 *
 * The record and the code arrive together — `/merchant/affiliates/:id` joins
 * them — so the head of the page is one read and renders whole. The numbers
 * and the rewards are separate reads on their own boundaries, because both
 * walk the business's events and neither should hold back the code the owner
 * came here to share.
 */
export default async function MerchantAffiliatePage({
  params,
  searchParams,
}: {
  params: Promise<{ affiliateId: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { affiliateId } = await params;
  const query = await searchParams;
  const [result, permissions, session] = await Promise.all([
    load(() => fetchMyAffiliate(affiliateId)),
    getMerchantPermissions(),
    load(() => getMerchantSession()),
  ]);

  if (result.error !== null) {
    return (
      <>
        <PageHeader title="Afiliado" action={<BackToAffiliates />} />
        <Panel>
          <ErrorState message={result.error} />
        </Panel>
      </>
    );
  }

  // An id from another business answers 404 as well, on purpose: the link is
  // the isolation boundary and probing an id tells you nothing.
  if (result.data === null) notFound();

  const affiliate = result.data;
  const code = affiliate.code;
  const standing = affiliateStanding(affiliate);
  const activity = lastAffiliateActivityAt(affiliate);
  const businessName =
    session.error === null && session.data !== null
      ? (session.data.active.name ?? '')
      : '';
  const justCreated = query.novo === '1';

  return (
    <>
      <PageHeader
        title={affiliate.name}
        subtitle={affiliate.phone ?? 'Sem telefone registado'}
        action={<BackToAffiliates />}
      />

      {justCreated ? (
        <p className="notice notice--ok" role="status">
          <span className="notice__mark" aria-hidden>
            ✓
          </span>
          <span>
            Afiliado adicionado. O código é{' '}
            <code className="inline">{code?.code ?? '—'}</code> — partilhe-o
            abaixo.
          </span>
        </p>
      ) : null}

      <ReadOnlyNotice reason={permissions.reason} />

      <Panel>
        <div className="split">
          <Card title="Código">
            <DefinitionList
              entries={[
                [
                  'Código',
                  code === null ? (
                    <span className="muted" key="code">
                      Sem código
                    </span>
                  ) : (
                    <code className="inline" key="code">
                      {code.code}
                    </code>
                  ),
                ],
                ['Benefício', benefitText(code)],
                ['Estado do código', <CodeBadge code={code} key="code-status" />],
                [
                  'Validade',
                  code?.expires_at == null
                    ? 'Sem fim definido'
                    : `Até ${formatDateTime(code.expires_at)}`,
                ],
                [
                  'Utilizações',
                  code === null
                    ? '—'
                    : `${code.usage_count.toLocaleString('pt-PT')}${
                        code.usage_limit === null
                          ? ' (sem limite)'
                          : ` de ${code.usage_limit.toLocaleString('pt-PT')}`
                      }`,
                ],
                [
                  'Clientes',
                  code?.first_visit_only === false
                    ? 'Qualquer cliente'
                    : 'Só clientes novos',
                ],
              ]}
            />
            <div className="form-actions">
              <ShareCode
                affiliate={affiliate}
                businessName={businessName}
                variant="btn-navy btn-sm"
              />
              {permissions.canManage && code !== null ? (
                <Link
                  className="btn btn-outline btn-sm"
                  href={`${AFFILIATES_PATH}/${encodeURIComponent(affiliate.id)}/codigo`}
                >
                  Definições do código
                </Link>
              ) : null}
            </div>
            {code === null ? (
              <p className="micro">
                Este afiliado ainda não tem código neste negócio. Fale com o
                suporte para o criar.
              </p>
            ) : standing !== 'ACTIVE' ? (
              <p className="micro">
                Enquanto o afiliado não estiver ativo, o código não é aceite ao
                balcão e não pode ser partilhado.
              </p>
            ) : null}
          </Card>

          <Card title="Afiliado">
            <DefinitionList
              entries={[
                ['Estado', <AffiliateStanding affiliate={affiliate} key="state" />],
                ['Telefone', affiliate.phone ?? '—'],
                [
                  'Ligado ao negócio em',
                  affiliate.linked_at === null
                    ? '—'
                    : formatDateTime(affiliate.linked_at),
                ],
                [
                  'Última atividade',
                  activity === null ? 'Sem atividade' : formatDateTime(activity),
                ],
              ]}
            />

            {permissions.canManage ? (
              affiliate.status === 'SUSPENDED' ? (
                <p className="micro">
                  Este afiliado está suspenso pela plataforma. Só o suporte
                  MaisUm pode levantar a suspensão.
                </p>
              ) : (
                <ActionForm
                  action={setAffiliateActiveAction}
                  submitLabel={
                    standing === 'ACTIVE' ? 'Desativar afiliado' : 'Reativar afiliado'
                  }
                  pendingLabel="A gravar…"
                  variant={standing === 'ACTIVE' ? 'btn-outline' : 'btn-navy'}
                  hint={
                    standing === 'ACTIVE'
                      ? 'O histórico mantém-se. O código deixa de ser aceite.'
                      : 'O código volta a ser aceite ao balcão.'
                  }
                >
                  <input type="hidden" name="affiliate_id" value={affiliate.id} />
                  <input
                    type="hidden"
                    name="active"
                    value={standing === 'ACTIVE' ? 'false' : 'true'}
                  />
                </ActionForm>
              )
            ) : (
              <div className="form-actions">
                <button
                  aria-describedby={READ_ONLY_REASON_ID}
                  className="btn btn-outline"
                  disabled
                  type="button"
                >
                  {standing === 'ACTIVE' ? 'Desativar afiliado' : 'Reativar afiliado'}
                </button>
              </div>
            )}
          </Card>
        </div>
      </Panel>

      <Panel>
        <Suspense fallback={<MetricsSkeleton count={6} />}>
          <AffiliateMetricsPanel affiliateId={affiliate.id} />
        </Suspense>
      </Panel>

      <Panel title="Recompensas deste afiliado">
        <Suspense fallback={<TableSkeleton rows={4} />}>
          <RewardsPanel affiliateId={affiliate.id} />
        </Suspense>
      </Panel>
    </>
  );
}

async function AffiliateMetricsPanel({ affiliateId }: { affiliateId: string }) {
  const result = await load(() => fetchMyAffiliateMetrics(affiliateId));
  if (result.error !== null) return <ErrorState message={result.error} />;
  if (result.data === null) {
    return <EmptyState message="Ainda não há números para este afiliado." />;
  }
  return <AffiliateMetrics metrics={result.data} heading="Desempenho" />;
}

/**
 * The rewards this affiliate has earned here.
 *
 * Read-only on this page, deliberately: approving is a decision about money
 * owed and is made on the rewards screen, where every pending one is in front
 * of the owner at once rather than one name at a time.
 */
async function RewardsPanel({ affiliateId }: { affiliateId: string }) {
  const result = await load(() =>
    fetchMyAffiliateRewards({ affiliateId, limit: 50 }),
  );
  if (result.error !== null) return <ErrorState message={result.error} />;

  const page = result.data;
  if (page.items.length === 0) {
    return (
      <EmptyState message="Ainda não há recompensas. Aparecem quando um cliente indicado compra pela primeira vez." />
    );
  }

  return (
    <>
      {page.items.some((reward) => reward.status === 'PENDING') ? (
        <p className="micro">
          <Link href={`${AFFILIATES_PATH}/recompensas`}>
            Aprovar ou cancelar recompensas pendentes
          </Link>
        </p>
      ) : null}

      <div className="card card--flush scroll-x">
        <table>
          <thead>
            <tr>
              <th scope="col">Criada</th>
              <th scope="col">Motivo</th>
              <th className="num" scope="col">
                Pontos
              </th>
              <th scope="col">Estado</th>
              <th scope="col">Decidida</th>
            </tr>
          </thead>
          <tbody>
            {page.items.map((reward) => (
              <tr key={reward.id}>
                <td>{formatDateTime(reward.created_at)}</td>
                <td>{rewardTypeLabel(reward.type) ?? reward.type}</td>
                <td className="num">{reward.value.toLocaleString('pt-PT')}</td>
                <td>
                  <Badge
                    label={rewardStatusLabel(reward.status)}
                    tone={rewardStatusTone(reward.status)}
                  />
                </td>
                <td>
                  {reward.approved_at !== null
                    ? formatDateTime(reward.approved_at)
                    : reward.cancelled_at !== null
                      ? formatDateTime(reward.cancelled_at)
                      : '—'}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
