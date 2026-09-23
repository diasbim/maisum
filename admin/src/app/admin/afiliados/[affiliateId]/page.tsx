import Link from 'next/link';
import { notFound } from 'next/navigation';

import { fetchAffiliate } from '@/lib/admin-api';
import {
  linkAffiliateAction,
  renameAffiliateAction,
  setGlobalAffiliateStatusAction,
  unlinkAffiliateAction,
} from '@/lib/actions';
import {
  CODE_VALIDITY_DAY_OPTIONS,
  DEFAULT_CODE_VALIDITY_DAYS,
  PERCENTAGE_RANGE,
} from '@/lib/affiliate-form';
import { ActionForm, Check, Field, Select } from '../../forms';
import {
  Badge,
  Card,
  DefinitionList,
  EmptyState,
  ErrorState,
  PageHeader,
  Panel,
  formatDateTime,
  load,
} from '../../ui';

export const metadata = { title: 'Afiliado | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * One identity, and its reach.
 *
 * Three decisions live here and nowhere else: what this person is called on
 * the platform, whether they may refer at all, and which businesses they are
 * attached to. What a code is worth inside a business is that owner's call and
 * is made in `/negocio/afiliados` — the exception is the benefit a new link is
 * created with, which has to be stated because a link without a code is not a
 * link: the code is what a customer says at the counter.
 *
 * Every write on this page is recorded by the API in the audit trail, with the
 * state before and after and the name of the operator who asked, because the
 * portal forwards their own token rather than holding a credential of its own.
 * Nothing here is deleted: unlinking disables, suspension is reversible, and
 * the history of what a person referred stays with the business it happened in.
 */
export default async function AdminAffiliatePage({
  params,
}: {
  params: Promise<{ affiliateId: string }>;
}) {
  const { affiliateId } = await params;
  const result = await load(() => fetchAffiliate(affiliateId));

  const back = (
    <Link className="btn btn-outline btn-sm" href="/admin/afiliados">
      ← Todos os afiliados
    </Link>
  );

  if (result.error !== null) {
    return (
      <>
        <PageHeader title="Afiliado" subtitle={affiliateId} action={back} />
        <Panel>
          <ErrorState message={result.error} />
        </Panel>
      </>
    );
  }
  if (result.data === null) notFound();

  const affiliate = result.data;
  const suspended = affiliate.status === 'SUSPENDED';

  return (
    <>
      <PageHeader
        title={affiliate.name || affiliate.id}
        subtitle={affiliate.id}
        action={back}
      />

      <Panel>
        <div className="split">
          <Card title="Identidade">
            <DefinitionList
              entries={[
                ['Estado', <Badge key="status" label={affiliate.status} />],
                // The mask is all the console gets. Recognising somebody in a
                // support call needs four digits; contacting them is the
                // business's job, not ours.
                ['Telefone', affiliate.phone_masked],
                ['Últimos 4 dígitos', affiliate.phone_last4 ?? '—'],
                ['Negócios ligados', String(affiliate.merchant_count)],
                ['Criado', formatDateTime(affiliate.created_at)],
                ['Atualizado', formatDateTime(affiliate.updated_at)],
              ]}
            />
          </Card>

          <Card
            title="Nome na plataforma"
            hint="Os códigos já emitidos foram criados a partir do nome de então e não mudam: estão impressos, partilhados e são escritos por clientes."
          >
            <ActionForm
              action={renameAffiliateAction}
              submitLabel="Gravar nome"
              pendingLabel="A gravar…"
              variant="btn-navy"
            >
              <input type="hidden" name="affiliate_id" value={affiliate.id} />
              <div className="form-grid">
                <Field
                  name="name"
                  label="Nome"
                  defaultValue={affiliate.name}
                  autoComplete="off"
                  maxLength={60}
                  required
                />
              </div>
            </ActionForm>
          </Card>
        </div>
      </Panel>

      <Panel title="Negócios ligados">
        {affiliate.merchant_ids.length === 0 ? (
          <EmptyState message="Este afiliado ainda não está ligado a nenhum negócio." />
        ) : (
          <div className="card card--flush scroll-x">
            <table>
              <thead>
                <tr>
                  <th scope="col">Negócio</th>
                  <th scope="col">Afiliados do negócio</th>
                </tr>
              </thead>
              <tbody>
                {affiliate.merchant_ids.map((merchantId) => (
                  <tr key={merchantId}>
                    <td>
                      <Link
                        href={`/admin/merchants/${encodeURIComponent(merchantId)}`}
                      >
                        <code className="inline">{merchantId}</code>
                      </Link>
                    </td>
                    <td>
                      <Link
                        href={`/admin/merchants/${encodeURIComponent(merchantId)}/afiliados`}
                      >
                        Ver programa deste negócio
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <p className="micro">
          A lista é a que o registo do afiliado guarda. Uma ligação desativada
          continua a constar aqui: o histórico não é apagado.
        </p>
      </Panel>

      <Panel>
        <div className="split">
          <Card
            title="Ligar a um negócio"
            hint="Cria a ligação e, se ainda não existir, o código desse negócio. Um afiliado suspenso não pode ser ligado."
          >
            <ActionForm
              action={linkAffiliateAction}
              submitLabel="Ligar ao negócio"
              pendingLabel="A ligar…"
              variant="btn-navy"
            >
              <input type="hidden" name="affiliate_id" value={affiliate.id} />
              <div className="form-grid">
                <Field
                  name="merchant_id"
                  label="ID do negócio"
                  placeholder="biz_..."
                  hint="Copie o id da ficha do negócio."
                  autoComplete="off"
                  required
                />
                <Select
                  name="benefit_type"
                  label="Benefício do código"
                  defaultValue="PERCENTAGE"
                  options={[
                    { value: 'PERCENTAGE', label: 'Percentagem de desconto' },
                    { value: 'FIXED_AMOUNT', label: 'Desconto fixo em MT' },
                    { value: 'POINTS', label: 'Pontos de fidelidade' },
                  ]}
                />
                <Field
                  name="benefit_value"
                  label="Valor do benefício"
                  type="number"
                  inputMode="decimal"
                  step="0.01"
                  min="0"
                  defaultValue="10"
                  hint={`Percentagem entre ${PERCENTAGE_RANGE.min} e ${PERCENTAGE_RANGE.max}.`}
                  required
                />
                <Select
                  name="validity_days"
                  label="Validade do código"
                  defaultValue={String(DEFAULT_CODE_VALIDITY_DAYS)}
                  options={CODE_VALIDITY_DAY_OPTIONS.map((days) => ({
                    value: String(days),
                    label: `${days} dias`,
                  }))}
                />
                <Field
                  name="usage_limit"
                  label="Limite de utilizações"
                  type="number"
                  inputMode="numeric"
                  step="1"
                  min="1"
                  placeholder="em branco = sem limite"
                />
                <Check
                  name="first_visit_only"
                  label="Só para clientes novos"
                  defaultChecked
                />
              </div>
            </ActionForm>
          </Card>

          <Card
            title="Desligar de um negócio"
            hint="A ligação fica inativa e o código desativado. Nada é apagado, e voltar a ligar devolve o mesmo histórico."
          >
            <ActionForm
              action={unlinkAffiliateAction}
              submitLabel="Desligar do negócio"
              pendingLabel="A desligar…"
              variant="btn-outline"
            >
              <input type="hidden" name="affiliate_id" value={affiliate.id} />
              <div className="form-grid">
                <Field
                  name="merchant_id"
                  label="ID do negócio"
                  placeholder="biz_..."
                  autoComplete="off"
                  required
                />
                <Check
                  name="confirm"
                  label="Confirmo"
                  hint="O código deixa de ser aceite nesse negócio."
                  danger
                />
              </div>
            </ActionForm>
          </Card>
        </div>
      </Panel>

      <Panel title="Estado na plataforma">
        <div className="split">
          <Card
            title={suspended ? 'Reativar' : 'Suspender'}
            hint={
              suspended
                ? 'Reativar devolve a capacidade de indicar em todos os negócios onde a ligação esteja ativa.'
                : 'A suspensão vale em toda a plataforma: o código deixa de ser aceite em qualquer negócio e ninguém o pode voltar a ligar.'
            }
          >
            <ActionForm
              action={setGlobalAffiliateStatusAction}
              submitLabel={suspended ? 'Reativar afiliado' : 'Suspender afiliado'}
              pendingLabel="A gravar…"
              variant={suspended ? 'btn-navy' : 'btn-outline'}
            >
              <input type="hidden" name="affiliate_id" value={affiliate.id} />
              <input
                type="hidden"
                name="status"
                value={suspended ? 'ACTIVE' : 'SUSPENDED'}
              />
              {suspended ? null : (
                <div className="form-grid">
                  <Check
                    name="confirm"
                    label="Confirmo a suspensão"
                    hint="Afeta todos os negócios em que esta pessoa indica."
                    danger
                  />
                </div>
              )}
            </ActionForm>
          </Card>

          <Card
            title="Marcar como inativo"
            hint="Menos forte que uma suspensão: a pessoa deixa de estar ativa, mas o estado não foi imposto por uma decisão de abuso."
          >
            <ActionForm
              action={setGlobalAffiliateStatusAction}
              submitLabel={
                affiliate.status === 'INACTIVE' ? 'Marcar como ativo' : 'Marcar como inativo'
              }
              pendingLabel="A gravar…"
              variant="btn-outline"
            >
              <input type="hidden" name="affiliate_id" value={affiliate.id} />
              <input
                type="hidden"
                name="status"
                value={affiliate.status === 'INACTIVE' ? 'ACTIVE' : 'INACTIVE'}
              />
            </ActionForm>
          </Card>
        </div>
      </Panel>
    </>
  );
}
