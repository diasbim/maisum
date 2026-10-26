import { setSubscriptionStatusAction } from '@/lib/actions';
import { ActionForm, Check, Select, TextArea } from '../../forms';
import { Badge, Card, DefinitionList, formatDateTime, load } from '../../ui';
import { getMerchant } from './data';

export const metadata = { title: 'Negócio | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const SUBSCRIPTION_STATUS_OPTIONS = [
  { value: 'ACTIVE', label: 'Ativa' },
  { value: 'TRIAL', label: 'Em avaliação' },
  { value: 'PAST_DUE', label: 'Em atraso' },
  { value: 'CANCELLED', label: 'Cancelada' },
];

export default async function MerchantOverviewPage({
  params,
}: {
  params: Promise<{ merchantId: string }>;
}) {
  const { merchantId } = await params;
  const result = await load(() => getMerchant(merchantId));

  // The layout already reported the error and the 404; reaching here without a
  // record means the layout is rendering its own error branch instead.
  const merchant = result.data;
  if (!merchant) return null;

  return (
    <>
      <div className="split">
        <Card title="Negócio">
          <DefinitionList
            entries={[
              ['Nome', merchant.name || '—'],
              ['Telefone', merchant.phone ?? '—'],
              ['Criado', formatDateTime(merchant.created_at)],
              ['Atualizado', formatDateTime(merchant.updated_at)],
              [
                'Última operação',
                formatDateTime(merchant.last_operational_update_at),
              ],
            ]}
          />
        </Card>

        <Card title="Subscrição">
          <DefinitionList
            entries={[
              ['Estado', <Badge key="s" label={merchant.subscription_status} />],
              ['Plano', merchant.plan_name ?? merchant.plan_code ?? '—'],
              ['Versão do plano', merchant.plan_version ?? '—'],
              ['Versão de preço', merchant.pricing_version ?? '—'],
              ['Fim da avaliação', formatDateTime(merchant.trial_ends_at)],
              ['Fim da tolerância', formatDateTime(merchant.grace_ends_at)],
              [
                'Período',
                merchant.period_start || merchant.period_end
                  ? `${formatDateTime(merchant.period_start)} → ${formatDateTime(merchant.period_end)}`
                  : '—',
              ],
              [
                'Atualizada',
                formatDateTime(merchant.subscription_updated_at),
              ],
            ]}
          />
        </Card>

        <Card title="Equipa">
          <DefinitionList
            entries={[
              [
                'Contas',
                `${merchant.active_staff_count} ativas de ${merchant.staff_count}`,
              ],
              [
                'Último início de sessão',
                formatDateTime(merchant.last_staff_login_at),
              ],
            ]}
          />
        </Card>

        <Card title="Uso">
          <DefinitionList
            entries={[
              ['Saldos', merchant.usage_balance_count],
              ['Acumulado', merchant.usage_used_total],
              ['Eventos', merchant.usage_event_count],
              ['Último evento', formatDateTime(merchant.last_usage_event_at)],
              ['Atualizado', formatDateTime(merchant.usage_updated_at)],
            ]}
          />
        </Card>

        <Card title="Configuração">
          <DefinitionList
            entries={[
              ['Entitlements', merchant.entitlement_count],
              ['Feature flags', merchant.feature_flag_count],
              ['Remote config', merchant.remote_config_count],
            ]}
          />
        </Card>
      </div>

      <div style={{ marginTop: 24 }}>
        <Card
          title="Substituir estado da subscrição"
          hint="Para o que a faturação ainda não cobre: um pagamento confirmado fora da app, uma pausa enquanto um caso é resolvido, um engano corrigido. O motivo fica só na auditoria — não é guardado no registo que a app do negócio lê."
        >
          <ActionForm
            action={setSubscriptionStatusAction}
            submitLabel="Substituir estado"
            pendingLabel="A gravar…"
            variant="btn-outline"
          >
            <input type="hidden" name="merchant_id" value={merchant.id} />
            <div className="form-grid">
              <Select
                name="status"
                label="Novo estado"
                defaultValue={merchant.subscription_status ?? undefined}
                options={SUBSCRIPTION_STATUS_OPTIONS}
              />
              <TextArea
                name="reason"
                label="Motivo"
                required
                placeholder="Ex.: pagamento confirmado por transferência em 12/09, referência 4471."
              />
              <Check
                name="confirm"
                label="Confirmo a substituição"
                hint="Isto substitui o estado atual, seja qual for."
                danger
              />
            </div>
          </ActionForm>
        </Card>
      </div>
    </>
  );
}
