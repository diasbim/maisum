/**
 * The shape every mutation form reads back.
 *
 * Kept out of `actions.ts` because that file is `'use server'`, and such a file
 * may only export async functions — exporting the `IDLE` constant from there
 * fails the build. Types would survive (they are erased), but the initial value
 * has to live somewhere the client can import at runtime.
 */
export type ActionState = {
  status: 'idle' | 'ok' | 'error';
  message: string;
  /** Raw job output, kept verbatim so per-item errors stay visible. */
  result?: Record<string, unknown>;
  /**
   * What the operator had typed when the action failed.
   *
   * React resets an uncontrolled form once its action settles — including when
   * it settles with an error — so without this a rejected submit blanks every
   * field and the whole plan has to be retyped to fix one wrong code. The
   * fields read their `defaultValue` back from here.
   */
  values?: Record<string, string>;
  /**
   * Validation messages keyed by field name.
   *
   * A single message at the foot of the form does not say which of ten inputs
   * is wrong. Anything keyed here renders against its own field; the summary
   * `message` stays for failures that belong to the form as a whole.
   */
  fieldErrors?: Record<string, string>;
};

export const IDLE: ActionState = { status: 'idle', message: '' };
