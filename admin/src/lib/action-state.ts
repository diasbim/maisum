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
};

export const IDLE: ActionState = { status: 'idle', message: '' };
