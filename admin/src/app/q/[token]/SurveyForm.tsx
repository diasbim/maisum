'use client';

import { useActionState, useState } from 'react';
import { useFormStatus } from 'react-dom';

import { IDLE } from '@/lib/action-state';
import { submitPublicSurveyAction } from '@/lib/public-survey-actions';
import type { PublicQuestion } from '@/lib/public-survey';

/**
 * The form a customer fills in on their phone.
 *
 * Every control is a real one — radios for a rating, radios for yes/no, a
 * select for a fixed set of options — rather than a text box with instructions
 * above it. Someone answering a survey on the street has one hand free.
 */

function Send() {
  const { pending } = useFormStatus();
  return (
    <button className="q-send" type="submit" disabled={pending} aria-busy={pending}>
      {pending ? 'A enviar…' : 'Enviar resposta'}
    </button>
  );
}

function Rating({
  question,
  error,
}: {
  question: PublicQuestion;
  error?: string;
}) {
  const [picked, setPicked] = useState<number | null>(null);

  return (
    <fieldset className="q-field" aria-describedby={error ? `${question.id}-err` : undefined}>
      <legend className="q-label">
        {question.question_text}
        {question.is_required ? <span aria-hidden> *</span> : null}
      </legend>
      <div className="q-scale" role="radiogroup" aria-label={question.question_text}>
        {[1, 2, 3, 4, 5].map((score) => (
          <label key={score} className={`q-score${picked === score ? ' is-picked' : ''}`}>
            <input
              type="radio"
              name={question.id}
              value={score}
              checked={picked === score}
              onChange={() => setPicked(score)}
            />
            <span>{score}</span>
          </label>
        ))}
      </div>
      <p className="q-hint">1 é muito mau, 5 é muito bom.</p>
      {error ? (
        <p className="q-error" id={`${question.id}-err`} role="alert">
          {error}
        </p>
      ) : null}
    </fieldset>
  );
}

function YesNo({ question, error }: { question: PublicQuestion; error?: string }) {
  return (
    <fieldset className="q-field">
      <legend className="q-label">
        {question.question_text}
        {question.is_required ? <span aria-hidden> *</span> : null}
      </legend>
      <div className="q-choices">
        {[
          { value: 'sim', label: 'Sim' },
          { value: 'nao', label: 'Não' },
        ].map((option) => (
          <label key={option.value} className="q-choice">
            <input type="radio" name={question.id} value={option.value} />
            <span>{option.label}</span>
          </label>
        ))}
      </div>
      {error ? (
        <p className="q-error" role="alert">
          {error}
        </p>
      ) : null}
    </fieldset>
  );
}

function Question({
  question,
  error,
  value,
}: {
  question: PublicQuestion;
  error?: string;
  value?: string;
}) {
  const type = question.question_type.toUpperCase();
  if (type === 'RATING') return <Rating question={question} error={error} />;
  if (type === 'YES_NO') return <YesNo question={question} error={error} />;

  if (type === 'MULTIPLE_CHOICE' && question.options.length > 0) {
    return (
      <div className="q-field">
        <label className="q-label" htmlFor={question.id}>
          {question.question_text}
          {question.is_required ? <span aria-hidden> *</span> : null}
        </label>
        <select id={question.id} name={question.id} defaultValue={value ?? ''}>
          <option value="">Escolha uma opção</option>
          {question.options.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
        {error ? (
          <p className="q-error" role="alert">
            {error}
          </p>
        ) : null}
      </div>
    );
  }

  return (
    <div className="q-field">
      <label className="q-label" htmlFor={question.id}>
        {question.question_text}
        {question.is_required ? <span aria-hidden> *</span> : null}
      </label>
      <textarea
        id={question.id}
        name={question.id}
        rows={3}
        defaultValue={value ?? ''}
        placeholder="Escreva aqui"
      />
      {error ? (
        <p className="q-error" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}

export function SurveyForm({
  token,
  questions,
}: {
  token: string;
  questions: PublicQuestion[];
}) {
  const [state, formAction] = useActionState(submitPublicSurveyAction, IDLE);

  if (state.status === 'ok') {
    return (
      <div className="q-done" role="status">
        <p className="q-done__mark" aria-hidden>
          ✓
        </p>
        <h2>Obrigado!</h2>
        <p>A sua resposta foi enviada. Já pode fechar esta página.</p>
      </div>
    );
  }

  return (
    <form action={formAction} className="q-form">
      <input type="hidden" name="token" value={token} />
      {questions.map((question) => (
        <Question
          key={question.id}
          question={question}
          error={state.fieldErrors?.[question.id]}
          value={state.values?.[question.id]}
        />
      ))}
      {state.status === 'error' ? (
        <p className="q-error q-error--form" role="alert">
          {state.message}
        </p>
      ) : null}
      <Send />
    </form>
  );
}
