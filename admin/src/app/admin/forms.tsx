'use client';

import { createContext, useActionState, useContext, useEffect, useState } from 'react';
import { useFormStatus } from 'react-dom';

import { IDLE, type ActionState } from '@/lib/action-state';

/**
 * Form primitives for every mutation surface.
 *
 * The server action is passed in as a prop. Nothing here calls the admin API
 * directly, so the ID token stays in the httpOnly cookie and never reaches the
 * browser — the same rule the read surfaces follow.
 */

/**
 * What the last submit sent back, read by the fields rather than threaded
 * through every caller.
 *
 * `revision` exists because React resets an uncontrolled form once its action
 * settles. A changed `defaultValue` alone does not touch an input that is
 * already mounted, so the fields key themselves on this counter and remount
 * carrying the restored value when a submit comes back with an error.
 */
type FormStateShape = {
  values: Record<string, string>;
  fieldErrors: Record<string, string>;
  revision: number;
  /** Whether a submit has come back at all, which a checkbox has to know. */
  submitted: boolean;
};

const EMPTY: FormStateShape = {
  values: {},
  fieldErrors: {},
  revision: 0,
  submitted: false,
};

const FormStateContext = createContext<FormStateShape>(EMPTY);

function useFieldState(name: string) {
  const { values, fieldErrors, revision, submitted } =
    useContext(FormStateContext);
  return {
    restored: values[name],
    error: fieldErrors[name],
    fieldKey: `${name}-${revision}`,
    submitted,
  };
}

export function SubmitButton({
  label,
  pendingLabel,
  variant = 'btn-navy',
}: {
  label: string;
  pendingLabel: string;
  variant?: string;
}) {
  // useFormStatus reads the enclosing form, so this has to be its own component
  // rather than inlined into ActionForm.
  const { pending } = useFormStatus();

  return (
    <button
      className={`btn ${variant}`}
      type="submit"
      disabled={pending}
      aria-busy={pending}
    >
      {pending ? pendingLabel : label}
    </button>
  );
}

export function Notice({ state }: { state: ActionState }) {
  if (state.status === 'idle') return null;

  const ok = state.status === 'ok';
  return (
    <div
      className={`notice ${ok ? 'notice--ok' : 'notice--error'}`}
      // Results arrive after the page has settled, so they have to be announced
      // rather than silently appearing below the fold. A failure interrupts:
      // the operator is otherwise about to act as though it worked.
      role={ok ? 'status' : 'alert'}
      aria-live={ok ? 'polite' : 'assertive'}
    >
      <span className="notice__mark" aria-hidden>
        {ok ? '✓' : '⚠'}
      </span>
      <span>{state.message}</span>
    </div>
  );
}

export function ActionForm({
  action,
  children,
  submitLabel,
  pendingLabel,
  variant,
  hint,
}: {
  action: (state: ActionState, form: FormData) => Promise<ActionState>;
  children: React.ReactNode;
  submitLabel: string;
  pendingLabel: string;
  variant?: string;
  hint?: React.ReactNode;
}) {
  const [state, formAction] = useActionState(action, IDLE);
  const [revision, setRevision] = useState(0);

  // Only a failure restores anything. A success should leave a blank form,
  // which is what React's own reset already gives.
  useEffect(() => {
    if (state.status === 'error') setRevision((n) => n + 1);
  }, [state]);

  return (
    <FormStateContext.Provider
      value={{
        values: state.values ?? {},
        fieldErrors: state.fieldErrors ?? {},
        revision,
        submitted: state.values !== undefined,
      }}
    >
      <form action={formAction}>
        {children}

        <div className="form-actions">
          <SubmitButton
            label={submitLabel}
            pendingLabel={pendingLabel}
            variant={variant}
          />
          {hint ? <span className="micro">{hint}</span> : null}
        </div>

        <div style={{ marginTop: 16 }}>
          <Notice state={state} />
          {state.result ? (
            <pre className="output" tabIndex={0}>
              {JSON.stringify(state.result, null, 2)}
            </pre>
          ) : null}
        </div>
      </form>
    </FormStateContext.Provider>
  );
}

/** The hint and error ids a field points `aria-describedby` at. */
function describedBy(name: string, hint?: string, error?: string) {
  const ids = [hint ? `${name}-hint` : null, error ? `${name}-error` : null]
    .filter(Boolean)
    .join(' ');
  return ids || undefined;
}

function FieldError({ name, error }: { name: string; error?: string }) {
  if (!error) return null;
  return (
    <p className="field__error" id={`${name}-error`}>
      <span aria-hidden>⚠</span> {error}
    </p>
  );
}

export function Field({
  name,
  label,
  hint,
  ...rest
}: {
  name: string;
  label: string;
  hint?: string;
} & React.InputHTMLAttributes<HTMLInputElement>) {
  const { restored, error, fieldKey } = useFieldState(name);

  return (
    <div className="field">
      <label htmlFor={name}>{label}</label>
      <input
        {...rest}
        key={fieldKey}
        aria-describedby={describedBy(name, hint, error)}
        aria-invalid={error ? true : undefined}
        className={`input${error ? ' input--invalid' : ''}`}
        defaultValue={restored ?? rest.defaultValue}
        id={name}
        name={name}
      />
      {hint ? (
        <p className="field__hint" id={`${name}-hint`}>
          {hint}
        </p>
      ) : null}
      <FieldError error={error} name={name} />
    </div>
  );
}

export function TextArea({
  name,
  label,
  hint,
  ...rest
}: {
  name: string;
  label: string;
  hint?: string;
} & React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  const { restored, error, fieldKey } = useFieldState(name);

  return (
    <div className="field" style={{ gridColumn: '1 / -1' }}>
      <label htmlFor={name}>{label}</label>
      <textarea
        {...rest}
        key={fieldKey}
        aria-describedby={describedBy(name, hint, error)}
        aria-invalid={error ? true : undefined}
        className={`input${error ? ' input--invalid' : ''}`}
        defaultValue={restored ?? rest.defaultValue}
        id={name}
        name={name}
      />
      {hint ? (
        <p className="field__hint" id={`${name}-hint`}>
          {hint}
        </p>
      ) : null}
      <FieldError error={error} name={name} />
    </div>
  );
}

export function Select({
  name,
  label,
  options,
  hint,
  defaultValue,
}: {
  name: string;
  label: string;
  options: Array<{ value: string; label: string }>;
  hint?: string;
  defaultValue?: string;
}) {
  const { restored, error, fieldKey } = useFieldState(name);

  return (
    <div className="field">
      <label htmlFor={name}>{label}</label>
      <select
        key={fieldKey}
        aria-describedby={describedBy(name, hint, error)}
        aria-invalid={error ? true : undefined}
        className={`input${error ? ' input--invalid' : ''}`}
        defaultValue={restored ?? defaultValue}
        id={name}
        name={name}
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {hint ? (
        <p className="field__hint" id={`${name}-hint`}>
          {hint}
        </p>
      ) : null}
      <FieldError error={error} name={name} />
    </div>
  );
}

export function Check({
  name,
  label,
  hint,
  danger,
  defaultChecked,
}: {
  name: string;
  label: string;
  hint?: string;
  danger?: boolean;
  defaultChecked?: boolean;
}) {
  const { restored, error, fieldKey, submitted } = useFieldState(name);
  // An unchecked box sends nothing at all, so once a submit has come back, a
  // missing key means "the operator had it off" rather than "no opinion" —
  // which is the difference between a dry run and one that writes.
  const wasChecked = submitted ? restored === 'on' : defaultChecked;

  return (
    <div className="field field--check">
      <label className={`check${danger ? ' check--danger' : ''}`}>
        <input
          key={fieldKey}
          defaultChecked={wasChecked}
          name={name}
          type="checkbox"
        />
        <span>
          {label}
          {hint ? <em>{hint}</em> : null}
        </span>
      </label>
      <FieldError error={error} name={name} />
    </div>
  );
}
