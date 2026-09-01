import { runJobAction } from '@/lib/actions';
import { ActionForm, Check, Field, TextArea } from '../forms';
import { Card, PageHeader, Panel } from '../ui';

export const metadata = { title: 'Retenção | Portal MaisUm' };
export const dynamic = 'force-dynamic';

const EXAMPLE_POLICY = [
  '{',
  '  "version": 2,',
  '  "tiers": [',
  '    { "key": "active", "max_days_since_visit": 30 },',
  '    { "key": "cooling", "max_days_since_visit": 60 },',
  '    { "key": "at_risk", "max_days_since_visit": 90 },',
  '    { "key": "lapsed" }',
  '  ]',
  '}',
].join('\n');

/**
 * Retention policy and classification.
 *
 * Kept apart from the other maintenance jobs because these two decide which
 * customers a business is told are slipping away — the thing the Pro plan is
 * sold on. A wrong threshold here does not corrupt data; it quietly changes
 * who gets chased.
 */
export default function RetentionPage() {
  return (
    <>
      <PageHeader
        title="Retenção"
        subtitle="Política de classificação e varrimento de clientes."
      />

      <Panel>
        <div className="stack">
          <Card
            title="Publicar política"
            hint={
              <>
                Grava uma nova versão da política de retenção do negócio. Se
                indicar a versão que espera encontrar, a gravação é recusada
                caso outra pessoa a tenha alterado entretanto — é o que evita
                sobrepor em silêncio o trabalho de outro operador.
              </>
            }
          >
            <ActionForm
              action={runJobAction}
              submitLabel="Publicar política"
              pendingLabel="A publicar…"
              variant="btn-navy"
            >
              <input type="hidden" name="job" value="retentionPolicy" />
              <div className="form-grid">
                <Field
                  name="merchant_id"
                  label="Negócio"
                  placeholder="id do negócio"
                  required
                  autoComplete="off"
                />
                <Field
                  name="expected_current_version"
                  label="Versão esperada"
                  type="number"
                  step="1"
                  min="0"
                  placeholder="opcional"
                  hint="Em branco, grava sem verificar."
                />
                <TextArea
                  name="policy"
                  label="Política (JSON)"
                  required
                  rows={12}
                  defaultValue={EXAMPLE_POLICY}
                />
              </div>
            </ActionForm>
          </Card>

          <Card
            title="Varrer classificações"
            hint="Reavalia cada cliente do negócio contra a política ativa e atualiza o seu estado de retenção."
          >
            <ActionForm
              action={runJobAction}
              submitLabel="Executar varrimento"
              pendingLabel="A varrer…"
            >
              <input type="hidden" name="job" value="retentionScan" />
              <div className="form-grid">
                <Field
                  name="merchant_id"
                  label="Negócio"
                  placeholder="id do negócio"
                  required
                  autoComplete="off"
                />
                <Field
                  name="limit"
                  label="Limite"
                  type="number"
                  step="1"
                  min="1"
                  max="200"
                  defaultValue="50"
                />
                <Field
                  name="cursor"
                  label="Continuar a partir de"
                  placeholder="id do último cliente"
                  autoComplete="off"
                />
                <Check
                  name="apply"
                  label="Aplicar as classificações"
                  hint="Sem isto, apenas mostra o que mudaria."
                  danger
                />
              </div>
            </ActionForm>
          </Card>
        </div>
      </Panel>
    </>
  );
}
