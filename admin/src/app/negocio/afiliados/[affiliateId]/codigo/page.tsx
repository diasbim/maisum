import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';

import { fetchMyAffiliate } from '@/lib/merchant-api';
import { getMerchantPermissions } from '@/lib/merchant-session';
import {
  saveAffiliateCodeAction,
  setAffiliateCodeEnabledAction,
} from '@/lib/merchant-actions';
import {
  CODE_VALIDITY_DAY_OPTIONS,
  PERCENTAGE_RANGE,
  formatBenefitNumber,
} from '@/lib/affiliate-form';
import { ActionForm, Check, Field, Select } from '../../../../admin/forms';
import {
  Card,
  ErrorState,
  PageHeader,
  Panel,
  formatDateTime,
  load,
} from '../../../../admin/ui';
import { AFFILIATES_PATH, CodeBadge, benefitText } from '../../afiliados';

export const metadata = { title: 'Definições do código | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * What one code is worth, and whether it is live.
 *
 * Its own page under the affiliate rather than a form on the detail: this is
 * the only screen in the business area that changes what a customer is given
 * at the counter, and it should be somewhere an owner arrives on purpose.
 *
 * The code itself is not editable and no field here offers to change it. It is
 * printed, forwarded and typed by customers, so renaming it would silently
 * invalidate every copy already in circulation — the API does not accept a new
 * one either.
 *
 * Every rule the inputs express is applied again in the server action and a
 * third time by the API. The `min`, `step` and `required` attributes are there
 * to catch a typo before it costs a round trip, and are worth nothing on their
 * own: a form can be submitted without any of them.
 */
export default async function AffiliateCodePage({
  params,
}: {
  params: Promise<{ affiliateId: string }>;
}) {
  const { affiliateId } = await params;
  const permissions = await getMerchantPermissions();
  const detailPath = `${AFFILIATES_PATH}/${encodeURIComponent(affiliateId)}`;

  // Read-only visitors have nothing to do on a page that is only a form.
  if (!permissions.canManage) redirect(detailPath);

  const result = await load(() => fetchMyAffiliate(affiliateId));

  if (result.error !== null) {
    return (
      <>
        <PageHeader title="Definições do código" />
        <Panel>
          <ErrorState message={result.error} />
        </Panel>
      </>
    );
  }
  if (result.data === null) notFound();

  const affiliate = result.data;
  const code = affiliate.code;

  const back = (
    <Link className="btn btn-outline btn-sm" href={detailPath}>
      ← Voltar ao afiliado
    </Link>
  );

  if (code === null) {
    return (
      <>
        <PageHeader
          title="Definições do código"
          subtitle={affiliate.name}
          action={back}
        />
        <Panel>
          <Card title="Sem código">
            <p className="micro">
              Este afiliado ainda não tem código neste negócio, por isso não há
              nada para configurar.
            </p>
          </Card>
        </Panel>
      </>
    );
  }

  const enabled = code.status.trim().toUpperCase() === 'ACTIVE';

  return (
    <>
      <PageHeader
        title="Definições do código"
        subtitle={`${affiliate.name} · ${code.code}`}
        action={back}
      />

      <Panel>
        <div className="split">
          <Card title="Como está agora">
            <p className="micro">
              <code className="inline">{code.code}</code>{' '}
              <CodeBadge code={code} />
            </p>
            <p className="micro">
              {benefitText(code)} ·{' '}
              {code.usage_limit === null
                ? 'sem limite de utilizações'
                : `${code.usage_count} de ${code.usage_limit} utilizações`}
            </p>
            <p className="micro">
              {code.expires_at === null
                ? 'Sem fim definido.'
                : `Válido até ${formatDateTime(code.expires_at)}.`}
            </p>
          </Card>

          <Card
            title={enabled ? 'Desativar o código' : 'Ativar o código'}
            hint={
              enabled
                ? 'Desativado, o código deixa de ser aceite ao balcão. Nada do que já aconteceu é apagado.'
                : 'Ativado, o código volta a ser aceite ao balcão dentro da validade.'
            }
          >
            <ActionForm
              action={setAffiliateCodeEnabledAction}
              submitLabel={enabled ? 'Desativar código' : 'Ativar código'}
              pendingLabel="A gravar…"
              variant={enabled ? 'btn-outline' : 'btn-navy'}
            >
              <input type="hidden" name="code_id" value={code.id} />
              <input type="hidden" name="affiliate_id" value={affiliate.id} />
              <input
                type="hidden"
                name="enabled"
                value={enabled ? 'false' : 'true'}
              />
            </ActionForm>
          </Card>
        </div>
      </Panel>

      <Panel>
        <Card
          title="Benefício e validade"
          hint="Vale para as vendas a partir da gravação. As indicações já confirmadas mantêm o que foi prometido."
        >
          <ActionForm
            action={saveAffiliateCodeAction}
            submitLabel="Gravar código"
            pendingLabel="A gravar…"
            variant="btn-navy"
          >
            <input type="hidden" name="code_id" value={code.id} />
            <input type="hidden" name="affiliate_id" value={affiliate.id} />

            <div className="form-grid">
              <Select
                name="benefit_type"
                label="Tipo de benefício"
                defaultValue={code.benefit_type}
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
                defaultValue={formatBenefitNumber(code.benefit_value)}
                hint={`Percentagem entre ${PERCENTAGE_RANGE.min} e ${PERCENTAGE_RANGE.max}. Em MT ou pontos, o valor por venda.`}
                required
              />
              <Select
                name="validity_days"
                label="Nova validade"
                defaultValue=""
                hint="A contar de hoje. Deixe em «Manter» para não mexer nas datas."
                options={[
                  { value: '', label: 'Manter a validade atual' },
                  ...CODE_VALIDITY_DAY_OPTIONS.map((days) => ({
                    value: String(days),
                    label: `${days} dias a partir de hoje`,
                  })),
                ]}
              />
              <Field
                name="usage_limit"
                label="Limite de utilizações"
                type="number"
                inputMode="numeric"
                step="1"
                min="1"
                defaultValue={
                  code.usage_limit === null ? '' : String(code.usage_limit)
                }
                placeholder="em branco = sem limite"
                hint={`Já usado ${code.usage_count} vez(es). Vazio deixa sem limite.`}
              />
              <Check
                name="first_visit_only"
                label="Só para clientes novos"
                hint="Desmarcada, o código também vale para quem já é cliente."
                defaultChecked={code.first_visit_only}
              />
            </div>
          </ActionForm>
        </Card>
      </Panel>
    </>
  );
}
