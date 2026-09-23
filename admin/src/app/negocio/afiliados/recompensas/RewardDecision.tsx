'use client';

import { useActionState, useState } from 'react';
import { useFormStatus } from 'react-dom';

import { IDLE } from '@/lib/action-state';
import {
  approveAffiliateRewardAction,
  cancelAffiliateRewardAction,
} from '@/lib/merchant-actions';

/**
 * Deciding one reward, from the row it belongs to.
 *
 * Row-level rather than a form at the foot of the page: "aprovar" only means
 * something next to the name of the person it pays and the sale it came from.
 *
 * Approving is one click, because it is the expected outcome and is reversible
 * by cancelling afterwards. Cancelling is two, because `CANCELLED` is terminal
 * — the engine offers no transition out of it — and a mis-click in a column of
 * identical buttons would end a payment somebody is owed. The second click is
 * what sends the confirmation; the server refuses a cancel that arrives
 * without it, so this is a way of asking rather than the check itself.
 *
 * Nothing here is paid. The portal has no such action and the API has no
 * transition to `PAID` from it: handing the points over is a person's job, and
 * a button that claimed otherwise would put the ledger and reality out of step.
 */

function Submit({
  label,
  pendingLabel,
  variant,
  describedAs,
}: {
  label: string;
  pendingLabel: string;
  variant: string;
  describedAs: string;
}) {
  // useFormStatus reads the enclosing form, so this has to be its own
  // component — the same reason SubmitButton exists in the console's forms.
  const { pending } = useFormStatus();
  return (
    <button
      aria-busy={pending}
      // A column of identical "Aprovar" buttons tells a screen reader nothing
      // about which row it is on.
      aria-label={describedAs}
      className={`btn ${variant} btn-sm`}
      disabled={pending}
      type="submit"
    >
      {pending ? pendingLabel : label}
    </button>
  );
}

export function RewardDecision({
  rewardId,
  affiliateId,
  affiliateName,
  points,
  canManage,
  reasonId,
}: {
  rewardId: string;
  affiliateId: string;
  affiliateName: string;
  points: number;
  canManage: boolean;
  /** The element that says why the controls are off, for a manager. */
  reasonId?: string;
}) {
  const [approveState, approve] = useActionState(
    approveAffiliateRewardAction,
    IDLE,
  );
  const [cancelState, cancel] = useActionState(cancelAffiliateRewardAction, IDLE);
  const [confirming, setConfirming] = useState(false);

  if (!canManage) {
    // Real disabled buttons rather than hidden ones: the manager can see what
    // the owner would do here, and the reason is one element away.
    return (
      <span className="row-action">
        <button
          aria-describedby={reasonId}
          className="btn btn-outline btn-sm"
          disabled
          type="button"
        >
          Aprovar
        </button>
        <button
          aria-describedby={reasonId}
          className="btn btn-outline btn-sm"
          disabled
          type="button"
        >
          Cancelar
        </button>
      </span>
    );
  }

  if (approveState.status === 'ok') {
    return (
      <span className="micro" role="status">
        ✓ Aprovada
      </span>
    );
  }
  if (cancelState.status === 'ok') {
    return (
      <span className="micro" role="status">
        ✓ Cancelada
      </span>
    );
  }

  if (confirming) {
    return (
      <form action={cancel} className="row-action">
        <input name="reward_id" type="hidden" value={rewardId} />
        <input name="affiliate_id" type="hidden" value={affiliateId} />
        <input name="confirm" type="hidden" value="true" />
        <span className="micro" role="alert">
          Cancelar {points} pontos de {affiliateName}? Não volta atrás.
        </span>
        <Submit
          describedAs={`Confirmar o cancelamento da recompensa de ${affiliateName}`}
          label="Confirmar"
          pendingLabel="A cancelar…"
          variant="btn-outline"
        />
        <button
          className="btn btn-outline btn-sm"
          onClick={() => setConfirming(false)}
          type="button"
        >
          Voltar
        </button>
        {cancelState.status === 'error' ? (
          <span className="micro row-action__error" role="alert">
            {cancelState.message}
          </span>
        ) : null}
      </form>
    );
  }

  return (
    <span className="row-action">
      <form action={approve} className="row-action">
        <input name="reward_id" type="hidden" value={rewardId} />
        <input name="affiliate_id" type="hidden" value={affiliateId} />
        <Submit
          describedAs={`Aprovar a recompensa de ${affiliateName}`}
          label="Aprovar"
          pendingLabel="A aprovar…"
          variant="btn-navy"
        />
        {approveState.status === 'error' ? (
          <span className="micro row-action__error" role="alert">
            {approveState.message}
          </span>
        ) : null}
      </form>
      <button
        className="btn btn-outline btn-sm"
        onClick={() => setConfirming(true)}
        type="button"
      >
        Cancelar
        <span className="sr-only"> a recompensa de {affiliateName}</span>
      </button>
    </span>
  );
}
