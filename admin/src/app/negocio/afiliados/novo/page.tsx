import { redirect } from 'next/navigation';

import { createAffiliateAction } from '@/lib/merchant-actions';
import { getMerchantPermissions } from '@/lib/merchant-session';
import {
  CODE_VALIDITY_DAY_OPTIONS,
  DEFAULT_CODE_VALIDITY_DAYS,
  PERCENTAGE_RANGE,
} from '@/lib/affiliate-form';
import { ActionForm, Check, Field, Select } from '../../../admin/forms';
import { Card, PageHeader, Panel } from '../../../admin/ui';
import { AFFILIATES_PATH, BackToAffiliates } from '../afiliados';

export const metadata = { title: 'Adicionar afiliado | MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * Adding somebody who will refer customers.
 *
 * Its own route rather than a form on the list: the list is read on a phone at
 * the counter, and a create form permanently open above it is a form nobody
 * asked for. Everything the code needs is decided here, in one submit, because
 * an affiliate without a code cannot be handed anything and a second step is a
 * second chance to abandon it half done.
 *
 * Nothing is shared from this page. The code is minted by the server — it is
 * built from the first name and checked for uniqueness there — so until the
 * answer arrives there is no code, and a provisional one would be shared,
 * typed at a till, and refused. On success the action lands on the affiliate's
 * own page, where the real code and the share link are.
 */
export default async function NewAffiliatePage() {
  const permissions = await getMerchantPermissions();

  // A manager reaching this URL directly is sent back to the list rather than
  // shown a form whose submit the API would refuse.
  if (!permissions.canManage) redirect(AFFILIATES_PATH);

  return (
    <>
      <PageHeader
        title="Adicionar afiliado"
        subtitle="O código é criado automaticamente a partir do primeiro nome."
        action={<BackToAffiliates />}
      />

      <Panel>
        <Card
          title="Dados do afiliado"
          hint="O telefone é usado para partilhar o código por WhatsApp e para identificar a pessoa em todos os negócios da plataforma."
        >
          <ActionForm
            action={createAffiliateAction}
            submitLabel="Adicionar afiliado"
            pendingLabel="A adicionar…"
            variant="btn-navy"
            hint="O código aparece na página do afiliado, pronto a partilhar."
          >
            <div className="form-grid">
              <Field
                name="name"
                label="Nome"
                placeholder="Ana Matola"
                autoComplete="off"
                maxLength={60}
                required
              />
              <Field
                name="phone"
                label="Telemóvel"
                type="tel"
                inputMode="tel"
                placeholder="84 123 4567"
                hint="Número de Moçambique, com ou sem +258."
                autoComplete="off"
                required
              />
              <Select
                name="benefit_type"
                label="Benefício para o cliente indicado"
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
                hint={`Percentagem entre ${PERCENTAGE_RANGE.min} e ${PERCENTAGE_RANGE.max}. Em MT ou pontos, o valor por venda.`}
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
                hint="Vazio não é o mesmo que 0: vazio deixa o código sem limite."
              />
              <Check
                name="first_visit_only"
                label="Só para clientes novos"
                hint="Desmarcada, o código também vale para quem já é cliente."
                defaultChecked
              />
            </div>
          </ActionForm>
        </Card>
      </Panel>
    </>
  );
}
