import { saveEntitlementAction } from '@/lib/actions';
import { fetchMerchantEntitlements, fetchPlans } from '@/lib/admin-api';
import { ActionForm, Check, Field } from '../../../forms';
import { Card, EmptyState, formatDateTime, load } from '../../../ui';
import { getMerchant } from '../data';

export const metadata = { title: 'Entitlements | Portal MaisUm' };
export const dynamic = 'force-dynamic';

export default async function EntitlementsPage({
  params,
}: {
  params: Promise<{ merchantId: string }>;
}) {
  const { merchantId } = await params;

  const [merchantResult, plansResult, entitlementsResult] = await Promise.all([
    load(() => getMerchant(merchantId)),
    load(fetchPlans),
    load(() => fetchMerchantEntitlements(merchantId)),
  ]);

  const merchant = merchantResult.data;
  if (!merchant) return null;

  // Every feature key the catalogue knows about, so the operator picks from
  // what exists instead of typing a key that silently grants nothing. It stays
  // a free-text input: an override for a key not yet in any plan is legitimate.
  const featureKeys = Array.from(
    new Set(
      (plansResult.data ?? []).flatMap((plan) =>
        plan.features.map((feature) => feature.feature_key),
      ),
    ),
  ).sort();

  return (
    <div className="stack">
      <Card
        title="Overrides em vigor"
        hint="O que este negócio tem, independentemente do que o plano concede."
      >
        {entitlementsResult.error !== null ? (
          <p className="error">{entitlementsResult.error}</p>
        ) : entitlementsResult.data.length === 0 ? (
          <EmptyState message="Sem overrides. Este negócio recebe exatamente o que o plano concede." />
        ) : (
          <div className="card card--flush scroll-x">
            <table>
              <thead>
                <tr>
                  <th>Funcionalidade</th>
                  <th>Estado</th>
                  <th>Limite</th>
                  <th>Atualizado</th>
                </tr>
              </thead>
              <tbody>
                {entitlementsResult.data.map((entitlement) => (
                  <tr key={entitlement.feature_key}>
                    <td>
                      <code className="inline">{entitlement.feature_key}</code>
                    </td>
                    <td>
                      <span
                        className={`badge ${entitlement.is_enabled ? 'badge-green' : 'badge-red'}`}
                      >
                        {entitlement.is_enabled ? 'ATIVA' : 'NEGADA'}
                      </span>
                    </td>
                    <td>
                      {/* Null and zero mean opposite things, so they are shown
                          as words rather than as a blank cell and a "0". */}
                      {entitlement.limit_value == null ? (
                        <span className="muted">sem limite</span>
                      ) : (
                        <>
                          {entitlement.limit_value}
                          {entitlement.unit ? ` ${entitlement.unit}` : ''}
                        </>
                      )}
                    </td>
                    <td>{formatDateTime(entitlement.updated_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>

      <Card
        title="Gravar override"
        hint={
          <>
            Substitui o que o plano concede, só para este negócio. A gravação
            fica no registo de auditoria com o estado anterior e o novo, em seu
            nome.
          </>
        }
      >
        <ActionForm
          action={saveEntitlementAction}
          submitLabel="Gravar override"
          pendingLabel="A gravar…"
          variant="btn-navy"
        >
          <input type="hidden" name="merchant_id" value={merchant.id} />

          <div className="form-grid">
            <Field
              name="feature_key"
              label="Funcionalidade"
              placeholder="engage_view_risk"
              list="feature-keys"
              required
              autoComplete="off"
            />
            <Field
              name="limit_value"
              label="Limite"
              type="number"
              step="1"
              placeholder="em branco = sem limite"
              hint="Vazio não é o mesmo que 0: vazio deixa sem limite, 0 nega."
            />
            <Field name="unit" label="Unidade" placeholder="por mês" />
            <Check
              name="is_enabled"
              label="Ativa"
              hint="Desmarcada, nega a funcionalidade mesmo que o plano a inclua."
              defaultChecked
            />
          </div>

          <datalist id="feature-keys">
            {featureKeys.map((key) => (
              <option key={key} value={key} />
            ))}
          </datalist>
        </ActionForm>
      </Card>
    </div>
  );
}
