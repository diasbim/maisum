'use client';

import { useActionState, useEffect, useState } from 'react';

import { IDLE } from '@/lib/action-state';
import { generateOutreachAction, markContactedAction } from '@/lib/prospecting-actions';
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
 * Generate → review → copy. A person sends.
 *
 * The panel has no send control and never will: the server generates a draft
 * and records that it generated one, and the only thing that can record a
 * message as sent is a person saying they sent it. That is a product decision,
 * and the shape of this component is where it is visible.
 *
 * The draft is held in component state rather than written to the lead,
 * because a draft is not a fact about the business — regenerating gives a
 * different message, and storing each one would turn the timeline into a
 * transcript of the model rather than a record of what was done.
 */

const CHANNEL_LABELS: Record<string, string> = {
  WHATSAPP: 'WhatsApp',
  EMAIL: 'Email',
  SMS: 'SMS',
  LINKEDIN: 'LinkedIn',
};

type Draft = {
  channel: string;
  subject: string | null;
  body: string;
  truncated: boolean;
  addressedTo: string | null;
  /** Which template wrote it. Reply rates are grouped by this. */
  templateId: string;
};

export function OutreachPanel({
  prospectId,
  channels,
  blocked,
}: {
  prospectId: string;
  channels: string[];
  blocked: boolean;
}) {
  const [state, action] = useActionState(generateOutreachAction, IDLE);
  const [contactState, contactAction] = useActionState(markContactedAction, IDLE);
  const [copied, setCopied] = useState(false);

  const draft =
    state.status === 'ok' && state.result !== undefined
      ? (state.result as unknown as Draft)
      : null;

  // The confirmation is transient; it should not still be on screen when the
  // operator comes back to the tab ten minutes later.
  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 4000);
    return () => clearTimeout(timer);
  }, [copied]);

  if (blocked) {
    return (
      <Panel title="Mensagem">
        <EmptyState message="Este negócio pediu para não ser contactado. Não há aqui nada a gerar." />
      </Panel>
    );
  }

  // There is deliberately no analysis gate here any more. The message comes
  // from a template over the business's own data, not from a model's reading
  // of it — and while the module runs without a model, `analysis` is always
  // null, so gating on it made this panel permanently unreachable.
  if (channels.length === 0) {
    return (
      <Panel title="Mensagem">
        <EmptyState message="Este negócio ainda não tem um contacto utilizável, ou não há modelo de mensagem para os canais em que ele é alcançável. Enriqueça o lead para procurar o telefone e o site." />
      </Panel>
    );
  }

  return (
    <Panel title="Mensagem">
      <Card hint="A mensagem é gerada, nunca enviada. Reveja-a, copie-a e envie-a você mesmo — e só depois registe o envio aqui.">
        <form action={action}>
          <input name="prospectId" type="hidden" value={prospectId} />

          <div className="field">
            <label htmlFor="outreach-channel">Canal</label>
            <select
              className="input"
              defaultValue={channels[0]}
              id="outreach-channel"
              name="channel"
            >
              {channels.map((channel) => (
                <option key={channel} value={channel}>
                  {CHANNEL_LABELS[channel] ?? channel}
                </option>
              ))}
            </select>
            <p className="field__hint">
              Só aparecem os canais para os quais existe um endereço. Nada é
              inventado para preencher um canal sem contacto.
            </p>
          </div>

          <div className="form-actions">
            <SubmitButton
              label="Gerar mensagem"
              pendingLabel="A gerar…"
              variant="btn-navy"
            />
            <span className="micro">
              A mensagem vem de um modelo de texto. Gerar não custa nada, pode
              repetir.
            </span>
          </div>
        </form>

        <Notice state={state} />
      </Card>

      {draft === null ? null : (
        <Card
          title={`Rascunho — ${CHANNEL_LABELS[draft.channel] ?? draft.channel}`}
          hint={
            // The template id is shown because it is what the reply rate is
            // grouped by: an operator comparing two versions needs to know
            // which one they are reading.
            draft.addressedTo === null
              ? `Modelo ${draft.templateId}. Sem tratamento pessoal: o nome de quem decide não é conhecido, e não foi inventado.`
              : `Modelo ${draft.templateId}. Dirigida a ${draft.addressedTo}.`
          }
        >
          {draft.truncated ? (
            <div className="notice notice--error" role="alert">
              <span className="notice__mark" aria-hidden>
                ⚠
              </span>
              <span>
                A mensagem atingiu o limite do canal e foi cortada. Leia o fim
                antes de a enviar.
              </span>
            </div>
          ) : null}

          {draft.subject === null ? null : (
            <p>
              <strong>Assunto:</strong> {draft.subject}
            </p>
          )}

          <pre className="output" tabIndex={0} style={{ whiteSpace: 'pre-wrap' }}>
            {draft.body}
          </pre>

          <div className="form-actions">
            <button
              className="btn btn-outline btn-sm"
              onClick={() => {
                const text =
                  draft.subject === null
                    ? draft.body
                    : `${draft.subject}\n\n${draft.body}`;
                // The clipboard API is unavailable over plain HTTP and in some
                // embedded browsers. Failing silently would leave an operator
                // pasting nothing, so the state only flips on success.
                navigator.clipboard
                  ?.writeText(text)
                  .then(() => setCopied(true))
                  .catch(() => setCopied(false));
              }}
              type="button"
            >
              Copiar
            </button>
            <span className="micro" role="status">
              {copied ? 'Copiado.' : 'Selecione e copie se o botão não funcionar.'}
            </span>
          </div>
        </Card>
      )}

      <Card
        title="Registar envio"
        hint="Só depois de a ter enviado. Isto move o lead para Contactado e escreve a entrada no histórico — o servidor não envia nada."
      >
        <form action={contactAction}>
          <input name="prospectId" type="hidden" value={prospectId} />
          {/* Which template actually went out — the A/B is grouped by this,
              and only a message that was sent can have earned a reply. Absent
              when nothing was generated in this session, in which case the
              lead simply is not attributed to an arm. */}
          {draft === null ? null : (
            <input name="template_id" type="hidden" value={draft.templateId} />
          )}

          <div className="form-grid">
            <div className="field">
              <label htmlFor="sent-channel">Canal usado</label>
              <select
                className="input"
                defaultValue={draft?.channel ?? channels[0]}
                id="sent-channel"
                name="channel"
              >
                {channels.map((channel) => (
                  <option key={channel} value={channel}>
                    {CHANNEL_LABELS[channel] ?? channel}
                  </option>
                ))}
              </select>
            </div>

            <div className="field">
              <label htmlFor="sent-note">Nota</label>
              <input
                className="input"
                id="sent-note"
                maxLength={500}
                name="note"
                placeholder="Opcional — o que ficou combinado"
                type="text"
              />
            </div>
          </div>

          <div className="form-actions">
            <SubmitButton
              label="Registar como contactado"
              pendingLabel="A registar…"
              variant="btn-outline"
            />
          </div>
        </form>

        <Notice state={contactState} />
      </Card>
    </Panel>
  );
}
