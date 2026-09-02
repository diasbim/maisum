import { AdminApiError } from './admin-api-error';
import type { ActionState } from './action-state';

/**
 * How a mutation reports back to the form it came from.
 *
 * These live outside `actions.ts` because that file is `'use server'` and may
 * only export async functions — helpers there cannot be exported at all, so
 * they could not be tested. The behaviour they carry is the kind that fails
 * quietly: an operator retyping a form, or a dry run that silently becomes a
 * write.
 */

/**
 * Everything the operator typed, so a rejected submit can hand it straight back.
 *
 * Only string entries are kept: `File` values have no `defaultValue` to restore
 * them to, and none of these forms upload anything.
 */
export function snapshot(form: FormData): Record<string, string> {
  const values: Record<string, string> = {};
  for (const [key, value] of form.entries()) {
    if (typeof value === 'string') values[key] = value;
  }
  return values;
}

/**
 * A validation failure.
 *
 * `field` names the input at fault so the message can render against it rather
 * than only at the foot of the form. Omit it for failures that belong to the
 * submission as a whole.
 */
export function failure(
  form: FormData,
  message: string,
  field?: string,
): ActionState {
  return {
    status: 'error',
    message,
    values: snapshot(form),
    ...(field ? { fieldErrors: { [field]: message } } : {}),
  };
}

/**
 * Turns a thrown error into a state the form can render.
 *
 * `AdminApiError` carries a message the API wrote, which is often English
 * ("Plan version not found") and would land mid-sentence in a Portuguese
 * console. It is shown as a quoted detail under a Portuguese lead rather than
 * passed off as our own copy, so the operator still gets the specific reason
 * without the interface changing language on them.
 */
export function describe(caught: unknown, form: FormData): ActionState {
  if (caught instanceof AdminApiError) {
    return {
      status: 'error',
      message: `Não foi possível gravar. A API respondeu: ${caught.message}`,
      values: snapshot(form),
    };
  }
  return {
    status: 'error',
    message: 'Erro inesperado. A operação pode não ter sido aplicada.',
    values: snapshot(form),
  };
}

/**
 * Whether a checkbox should come back checked after a failed submit.
 *
 * An unchecked box sends nothing at all, so once a submit has come back a
 * missing key means "the operator had it off" rather than "no opinion". Before
 * any submit there is no snapshot to read and the field's own default stands.
 *
 * This is the difference between a job re-running as a dry run and re-running
 * as one that writes, which is why it is not inlined.
 */
export function restoredCheckbox(
  submitted: boolean,
  restored: string | undefined,
  defaultChecked: boolean | undefined,
): boolean | undefined {
  return submitted ? restored === 'on' : defaultChecked;
}
