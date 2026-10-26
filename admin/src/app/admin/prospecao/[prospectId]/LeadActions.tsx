'use client';

import { useActionState } from 'react';

import { IDLE } from '@/lib/action-state';
import {
  analyzeLeadAction,
  enrichLeadAction,
  findDecisionMakersAction,
  setLeadStatusAction,
} from '@/lib/prospecting-actions';
import { Notice, SubmitButton } from '../../forms';


/**
 * The design-system wrappers, as markup.
 *
 * A client component cannot import `ui.tsx`: that module reaches
 * `admin-api.ts` for its error type, which is `server-only` and drags
 * firebase-admin into the browser bundle. The classes are the design system —
 * the components in `ui.tsx` are a convenience over them, not the system
 * itself — so a client surface uses them directly.
 */
function Panel({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <section className="panel">
      {title ? <p className="section-label">{title}</p> : null}
      {children}
    </section>
  );
}

function Card({
  title,
  hint,
  children,
}: {
  title?: string;
  hint?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="card">
      {title ? <p className="card__title">{title}</p> : null}
      {hint ? <p className="card__hint">{hint}</p> : null}
      {children}
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="state state--empty">
      <p className="state__message">{message}</p>
    </div>
  );
}

/**
 * What an operator can do to a lead.
 *
 * Split into two cards on purpose: the paid actions and the free one. Moving a
 * lead through the pipeline costs nothing and is done constantly; enriching it
 * costs money and is done once. Putting them in one row of buttons would make
 * the expensive ones as easy to press by accident as the cheap one.
 *
 * Every paid control says so on its own label. "Cada clique é cobrado" is not
 * decoration — it is the difference between an operator who retries a slow
 * request three times and one who waits.
 */

/**
 * Which moves the pipeline actually admits from here.
 *
 * Forward only, stages skippable, and a terminal status admits nothing. The
 * server validates this again and answers 409 — this list exists so the
 * operator is not offered a move that will be refused.
 */
const PIPELINE = [
  'RAW',
  'QUALIFIED',
  'SCORED',
  'ENRICHED',
  'READY_TO_CONTACT',
  'CONTACTED',
  'REPLIED',
  'INTERESTED',
  'DEMO',
  'TRIAL',
  'CUSTOMER',
];

const TERMINAL: Array<{ value: string; label: string }> = [
  { value: 'NOT_A_FIT', label: 'Não encaixa' },
  { value: 'NO_CONTACT', label: 'Sem contacto' },
  { value: 'DO_NOT_CONTACT', label: 'Não contactar (definitivo)' },
  { value: 'OPTED_OUT', label: 'Pediu para sair (definitivo)' },
  { value: 'EXISTING_CUSTOMER', label: 'Já é cliente' },
  { value: 'LOST', label: 'Perdido' },
];

const LABELS: Record<string, string> = {
  RAW: 'Descoberto',
  QUALIFIED: 'Qualificado',
  SCORED: 'Pontuado',
  ENRICHED: 'Enriquecido',
  READY_TO_CONTACT: 'Pronto a contactar',
  CONTACTED: 'Contactado',
  REPLIED: 'Respondeu',
  INTERESTED: 'Interessado',
  DEMO: 'Demonstração',
  TRIAL: 'Em teste',
  CUSTOMER: 'Cliente',
};

function nextStatuses(current: string): Array<{ value: string; label: string }> {
  const index = PIPELINE.indexOf(current);
  // A terminal status is not in the pipeline, and admits nothing at all.
  if (index < 0) return [];

  return [
    ...PIPELINE.slice(index + 1).map((value) => ({
      value,
      label: LABELS[value] ?? value,
    })),
    ...TERMINAL,
  ];
}

export function LeadActions({
  prospectId,
  status,
  blocked,
  hasAnalysis,
}: {
  prospectId: string;
  status: string;
  blocked: boolean;
  hasAnalysis: boolean;
}) {
  const [findState, findAction] = useActionState(findDecisionMakersAction, IDLE);
  const [enrichState, enrichAction] = useActionState(enrichLeadAction, IDLE);
  const [analyzeState, analyzeAction] = useActionState(analyzeLeadAction, IDLE);
  const [statusState, statusFormAction] = useActionState(setLeadStatusAction, IDLE);

  const options = nextStatuses(status);

  return (
    <Panel title="Ações">
      <Card
        title="Enriquecer"
        hint="Estas três chamam fornecedores ou o modelo e são cobradas. Um lead abaixo da pontuação mínima é recusado antes de qualquer gasto."
      >
        <div className="form-grid">
          <form action={findAction}>
            <input name="prospectId" type="hidden" value={prospectId} />
            <SubmitButton
              label="Encontrar decisor"
              pendingLabel="A procurar…"
              variant="btn-outline"
            />
          </form>

          <form action={enrichAction}>
            <input name="prospectId" type="hidden" value={prospectId} />
            <SubmitButton
              label="Pesquisar o negócio"
              pendingLabel="A pesquisar…"
              variant="btn-outline"
            />
          </form>

          <form action={analyzeAction}>
            <input name="prospectId" type="hidden" value={prospectId} />
            {/* Re-running a valid analysis is deliberate and has to be asked
                for; without the box, reopening the page would be free and the
                button would look like it did nothing. */}
            {hasAnalysis ? (
              <label className="check">
                <input name="force" type="checkbox" />
                <span>
                  Refazer
                  <em>Ignora a análise guardada e volta a chamar o modelo.</em>
                </span>
              </label>
            ) : null}
            <SubmitButton
              label={hasAnalysis ? 'Analisar' : 'Analisar com IA'}
              pendingLabel="A analisar…"
              variant="btn-navy"
            />
          </form>
        </div>

        <Notice state={findState} />
        <Notice state={enrichState} />
        <Notice state={analyzeState} />
      </Card>

      <Card
        title="Mover no funil"
        hint="Um lead pode saltar etapas. Os estados finais não são reversíveis — em particular, «não contactar» e «pediu para sair» não podem ser desfeitos."
      >
        {options.length === 0 ? (
          <p className="muted">
            Este lead está num estado final. Para o reconsiderar, descubra-o de
            novo: a desduplicação liga-o ao mesmo negócio e cria um registo com
            o seu próprio histórico.
          </p>
        ) : (
          <form action={statusFormAction}>
            <input name="prospectId" type="hidden" value={prospectId} />

            <div className="form-grid">
              <div className="field">
                <label htmlFor="new-status">Novo estado</label>
                <select className="input" id="new-status" name="status">
                  {options.map((option) => (
                    <option key={option.value} value={option.value}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </div>

              <div className="field">
                <label htmlFor="status-note">Motivo</label>
                <input
                  className="input"
                  id="status-note"
                  maxLength={500}
                  name="note"
                  placeholder="Opcional"
                  type="text"
                />
              </div>
            </div>

            <div className="form-actions">
              <SubmitButton
                label="Mudar estado"
                pendingLabel="A mudar…"
                variant="btn-outline"
              />
              {blocked ? (
                <span className="micro">
                  Este lead já não pode ser contactado.
                </span>
              ) : null}
            </div>
          </form>
        )}

        <Notice state={statusState} />
      </Card>
    </Panel>
  );
}
