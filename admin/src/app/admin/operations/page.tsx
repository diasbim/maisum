import { runJobAction } from '@/lib/actions';
import { ActionForm, Check, Field, Select, TextArea } from '../forms';
import { Card, PageHeader, Panel } from '../ui';

export const metadata = { title: 'Operações | Portal MaisUm' };
export const dynamic = 'force-dynamic';

/**
 * The maintenance jobs.
 *
 * Every one of these was reachable only by curl with an admin key. They walk
 * Firestore in pages and return a cursor, so a large business takes several
 * runs; the cursor field is how the operator continues rather than restarting.
 *
 * All four default to a dry run. Applying is a deliberate second act: the
 * toggle is styled as the one control on the page that changes production
 * data, and the result banner says which mode actually ran.
 */
export default function OperationsPage() {
  return (
    <>
      <PageHeader
        title="Operações de manutenção"
        subtitle="Migrações e reconciliações sobre os dados em Firestore."
      />

      <div className="info-box" style={{ marginBottom: 24 }}>
        <strong>Estas operações correm por páginas.</strong>
        <p style={{ margin: '6px 0 0' }}>
          Cada execução processa até ao limite indicado e devolve um cursor.
          Para continuar, copie o cursor da resposta para o campo{' '}
          <em>Continuar a partir de</em> e volte a executar. Sem a caixa{' '}
          <em>Aplicar</em> marcada, nada é alterado.
        </p>
      </div>

      <Panel title="Clientes">
        <div className="stack">
          <Card
            title="Ligar clientes de um negócio à identidade canónica"
            hint="Percorre os clientes de um negócio e liga-os ao registo canónico por telefone. Não cria clientes que ainda não existam."
          >
            <ActionForm
              action={runJobAction}
              submitLabel="Executar"
              pendingLabel="A executar…"
            >
              <input type="hidden" name="job" value="businessCustomers" />
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
                  hint="Máximo 200."
                />
                <Field
                  name="cursor"
                  label="Continuar a partir de"
                  placeholder="id do último cliente"
                  autoComplete="off"
                />
                <Check
                  name="apply"
                  label="Aplicar"
                  hint="Sem isto, apenas simula."
                  danger
                />
              </div>
            </ActionForm>
          </Card>

          <Card
            title="Associar cartões NFC"
            hint="Recebe uma lista de cartões e liga cada um ao cliente com aquele telefone. Até 200 por pedido."
          >
            <ActionForm
              action={runJobAction}
              submitLabel="Executar"
              pendingLabel="A executar…"
            >
              <input type="hidden" name="job" value="nfcCards" />
              <div className="form-grid">
                <TextArea
                  name="items"
                  label="Cartões (JSON)"
                  required
                  defaultValue={
                    '[\n  {\n    "card_uid": "04A224B2C15E80",\n    "phone": "+258840000000",\n    "merchant_id": "",\n    "customer_name": "Cliente"\n  }\n]'
                  }
                  hint="Array de objetos com card_uid e phone. merchant_id e customer_name são opcionais."
                />
                <Check
                  name="apply"
                  label="Aplicar"
                  hint="Sem isto, apenas simula."
                  danger
                />
              </div>
            </ActionForm>
          </Card>
        </div>
      </Panel>

      <Panel title="Pontos de fidelização">
        <div className="stack">
          <Card
            title="Reconstruir o livro de pontos"
            hint="Reescreve as entradas do livro a partir das vendas e dos resgates. Percorre uma origem de cada vez."
          >
            <ActionForm
              action={runJobAction}
              submitLabel="Executar"
              pendingLabel="A executar…"
            >
              <input type="hidden" name="job" value="loyaltyBackfill" />
              <div className="form-grid">
                <Field
                  name="merchant_id"
                  label="Negócio"
                  placeholder="id do negócio"
                  required
                  autoComplete="off"
                />
                <Select
                  name="source_type"
                  label="Origem"
                  defaultValue="all"
                  options={[
                    { value: 'all', label: 'Vendas e resgates' },
                    { value: 'sales', label: 'Apenas vendas' },
                    { value: 'redemptions', label: 'Apenas resgates' },
                  ]}
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
                  placeholder="id do último documento"
                  autoComplete="off"
                />
                <Check
                  name="apply"
                  label="Aplicar"
                  hint="Sem isto, apenas simula."
                  danger
                />
              </div>
            </ActionForm>
          </Card>

          <Card
            title="Reconciliar saldos"
            hint="Compara o total de pontos guardado em cada cliente com a soma do livro e assinala as divergências."
          >
            <ActionForm
              action={runJobAction}
              submitLabel="Executar"
              pendingLabel="A executar…"
            >
              <input type="hidden" name="job" value="loyaltyReconcile" />
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
                  label="Corrigir as divergências"
                  hint="Sem isto, apenas lista."
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
