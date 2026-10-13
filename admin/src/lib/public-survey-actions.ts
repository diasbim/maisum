'use server';

import type { ActionState } from './action-state';
import {
  fetchPublicSurvey,
  submitPublicSurvey,
  type PublicAnswer,
  type PublicQuestion,
} from './public-survey';

/**
 * Sending a survey answer, from someone who is not signed in.
 *
 * The form posts question ids and raw strings; this turns them into the three
 * typed columns an answer can occupy. Which column depends on the question
 * type, which is read back from the API rather than trusted from the form —
 * the browser could say a rating question is free text and store a sentence
 * where a number belongs.
 */

function answerFor(
  question: PublicQuestion,
  raw: string,
): PublicAnswer | null {
  const value = raw.trim();
  if (value === '') return null;

  switch (question.question_type.toUpperCase()) {
    case 'RATING': {
      const score = Number.parseInt(value, 10);
      if (!Number.isFinite(score)) return null;
      return { question_id: question.id, answer_numeric: score };
    }
    case 'YES_NO':
      return { question_id: question.id, answer_bool: value === 'sim' };
    default:
      return { question_id: question.id, answer_text: value };
  }
}

export async function submitPublicSurveyAction(
  _state: ActionState,
  form: FormData,
): Promise<ActionState> {
  const token = form.get('token');
  if (typeof token !== 'string' || token.trim() === '') {
    return { status: 'error', message: 'Este link já não funciona.' };
  }

  // Re-read the survey rather than trusting the shape the form declares.
  const survey = await fetchPublicSurvey(token);
  if (!survey.ok) {
    return {
      status: 'error',
      message:
        survey.failure.kind === 'unreachable'
          ? 'Não conseguimos enviar agora. Tente daqui a pouco.'
          : 'Este link já não funciona.',
    };
  }

  const answers: PublicAnswer[] = [];
  const fieldErrors: Record<string, string> = {};
  const values: Record<string, string> = {};

  for (const question of survey.value.questions) {
    const raw = form.get(question.id);
    const text = typeof raw === 'string' ? raw : '';
    values[question.id] = text;

    const answer = answerFor(question, text);
    if (answer === null) {
      if (question.is_required) {
        fieldErrors[question.id] = 'Falta responder a esta pergunta.';
      }
      continue;
    }
    answers.push(answer);
  }

  if (Object.keys(fieldErrors).length > 0) {
    return {
      status: 'error',
      message: 'Falta responder a algumas perguntas.',
      fieldErrors,
      values,
    };
  }

  if (answers.length === 0) {
    return {
      status: 'error',
      message: 'Responda a pelo menos uma pergunta antes de enviar.',
      values,
    };
  }

  const sent = await submitPublicSurvey(token, answers);
  if (!sent.ok) {
    if (sent.failure.kind === 'invalid') {
      return {
        status: 'error',
        message: 'Falta responder a algumas perguntas.',
        fieldErrors: Object.fromEntries(
          sent.failure.questionIds.map((id) => [id, 'Falta responder a esta pergunta.']),
        ),
        values,
      };
    }
    return {
      status: 'error',
      message:
        sent.failure.kind === 'unreachable'
          ? 'Não conseguimos enviar agora. Tente daqui a pouco.'
          : 'Este link já não funciona.',
      values,
    };
  }

  return { status: 'ok', message: 'Resposta enviada. Obrigado!' };
}
