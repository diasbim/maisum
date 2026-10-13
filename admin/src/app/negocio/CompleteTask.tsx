'use client';

import { useActionState } from 'react';
import { useFormStatus } from 'react-dom';

import { IDLE } from '@/lib/action-state';
import { completeRecoveryTaskAction } from '@/lib/merchant-actions';

/**
 * Closing one task, from the row it belongs to.
 *
 * A row-level action rather than a form at the top of the page: "concluir a
 * tarefa" only means anything next to the name of the customer it is about.
 *
 * useFormStatus reads the enclosing form, so the button has to be its own
 * component — the same reason SubmitButton exists in the console's forms.
 */
function Button({ describedAs }: { describedAs: string }) {
  const { pending } = useFormStatus();
  return (
    <button
      className="btn btn-outline btn-sm"
      type="submit"
      disabled={pending}
      aria-busy={pending}
      // The visible word stays short, but a column of identical "Concluir"
      // buttons tells a screen reader nothing about which row it is on.
      aria-label={describedAs}
    >
      {pending ? 'A concluir…' : 'Concluir'}
    </button>
  );
}

export function CompleteTask({
  taskId,
  customerName,
}: {
  taskId: string;
  customerName: string | null;
}) {
  const [state, formAction] = useActionState(completeRecoveryTaskAction, IDLE);

  if (state.status === 'ok') {
    return (
      <span className="micro" role="status">
        ✓ Concluída
      </span>
    );
  }

  return (
    <form action={formAction} className="row-action">
      <input type="hidden" name="task_id" value={taskId} />
      <Button
        describedAs={
          customerName === null
            ? 'Concluir esta tarefa'
            : `Concluir a tarefa de ${customerName}`
        }
      />
      {state.status === 'error' ? (
        <span className="micro row-action__error" role="alert">
          {state.message}
        </span>
      ) : null}
    </form>
  );
}
