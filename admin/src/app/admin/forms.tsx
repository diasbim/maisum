'use client';

import { useActionState } from 'react';
import { useFormStatus } from 'react-dom';

import { IDLE, type ActionState } from '@/lib/action-state';

/**
 * Form primitives for every mutation surface.
 *
 * The server action is passed in as a prop. Nothing here calls the admin API
 * directly, so the ID token stays in the httpOnly cookie and never reaches the
 * browser — the same rule the read surfaces follow.
 */

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
    <button className={`btn ${variant}`} type="submit" disabled={pending}>
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
      // rather than silently appearing below the fold.
      role="status"
      aria-live="polite"
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

  return (
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

      <div style={{ marginTop: 14 }}>
        <Notice state={state} />
        {state.result ? (
          <pre className="output" tabIndex={0}>
            {JSON.stringify(state.result, null, 2)}
          </pre>
        ) : null}
      </div>
    </form>
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
  return (
    <div className="field">
      <label htmlFor={name}>{label}</label>
      <input className="input" id={name} name={name} {...rest} />
      {hint ? <p className="field__hint">{hint}</p> : null}
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
  return (
    <div className="field" style={{ gridColumn: '1 / -1' }}>
      <label htmlFor={name}>{label}</label>
      <textarea className="input" id={name} name={name} {...rest} />
      {hint ? <p className="field__hint">{hint}</p> : null}
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
  return (
    <div className="field">
      <label htmlFor={name}>{label}</label>
      <select
        className="input"
        id={name}
        name={name}
        defaultValue={defaultValue}
      >
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
      {hint ? <p className="field__hint">{hint}</p> : null}
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
  return (
    <label className={`check${danger ? ' check--danger' : ''}`}>
      <input type="checkbox" name={name} defaultChecked={defaultChecked} />
      <span>
        {label}
        {hint ? <em>{hint}</em> : null}
      </span>
    </label>
  );
}
