'use server';

import { revalidatePath } from 'next/cache';

import type { ActionState } from './action-state';
import { AdminApiError } from './admin-api';
import { completeMyRecoveryTask } from './merchant-api';

/**
 * What the business side of the portal is allowed to change.
 *
 * Kept apart from `actions.ts`, which is the internal console's mutations and
 * is guarded by the admin claim. Nothing here touches money, points or
 * customer records: those happen with the customer standing at the counter and
 * belong to the app. This file exists for bookkeeping about work already done.
 *
 * Server actions rather than route handlers, for the same reason as the
 * console's: the session cookie is read on the server and the ID token never
 * reaches the browser.
 */

export async function completeRecoveryTaskAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const taskId = form.get('task_id');
  if (typeof taskId !== 'string' || taskId.trim() === '') {
    return { status: 'error', message: 'Não foi possível identificar a tarefa.' };
  }

  try {
    await completeMyRecoveryTask(taskId.trim());
  } catch (error) {
    if (error instanceof AdminApiError) {
      return { status: 'error', message: error.message };
    }
    return {
      status: 'error',
      message: 'Não foi possível concluir a tarefa. Tente de novo.',
    };
  }

  // The list is server-rendered and cached per request; without this the row
  // would still read "Pendente" until the next navigation.
  revalidatePath('/negocio/tarefas');
  revalidatePath('/negocio');
  return { status: 'ok', message: 'Tarefa concluída.' };
}
