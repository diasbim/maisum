import { serverConfig } from './env';

/**
 * The survey a customer opens from a link.
 *
 * The only part of the portal that serves someone who is not signed in, and
 * the only one that talks to the API with no Authorization header at all: the
 * signed token in the URL is what authorises the read, and the API verifies it.
 * Nothing here may take a business or survey id from the request — the token
 * carries both, and the server trusts only the token.
 */

export type PublicQuestion = {
  id: string;
  question_text: string;
  question_type: string;
  options: string[];
  is_required: boolean;
  sort_order: number;
};

export type PublicSurvey = {
  survey: { id: string; title: string; description: string | null };
  business_name: string | null;
  questions: PublicQuestion[];
  /** True when the link was sent to one person, so the answer is attributed. */
  named: boolean;
};

export type PublicAnswer = {
  question_id: string;
  answer_text?: string | null;
  answer_numeric?: number | null;
  answer_bool?: boolean | null;
};

/**
 * What went wrong, in words the person holding the link can act on.
 *
 * Deliberately narrow: an expired link, a closed survey and a token that was
 * never valid are all "this link no longer works", because telling them apart
 * would help someone probing tokens and helps nobody else.
 */
export type PublicSurveyFailure =
  | { kind: 'gone' }
  | { kind: 'unreachable' }
  | { kind: 'invalid'; questionIds: string[] };

export type PublicSurveyResult<T> =
  | { ok: true; value: T }
  | { ok: false; failure: PublicSurveyFailure };

type Envelope<T> = {
  success?: boolean;
  data?: T;
  code?: string;
  message?: string;
};

async function callPublic<T>(
  path: string,
  init?: RequestInit,
): Promise<PublicSurveyResult<T>> {
  const config = serverConfig();

  let response: Response;
  try {
    response = await fetch(`${config.adminApiBaseUrl}${path}`, {
      ...init,
      headers: { Accept: 'application/json', ...(init?.headers ?? {}) },
      cache: 'no-store',
    });
  } catch {
    console.error(`[public-survey] unreachable: ${path}`);
    return { ok: false, failure: { kind: 'unreachable' } };
  }

  let body: Envelope<T> | null = null;
  try {
    body = (await response.json()) as Envelope<T>;
  } catch {
    body = null;
  }

  if (!response.ok || body?.success !== true) {
    if (body?.code === 'missing_required') {
      const ids = (body as Envelope<{ question_ids?: string[] }>).data?.question_ids;
      return {
        ok: false,
        failure: { kind: 'invalid', questionIds: Array.isArray(ids) ? ids : [] },
      };
    }
    if (response.status >= 500) {
      return { ok: false, failure: { kind: 'unreachable' } };
    }
    return { ok: false, failure: { kind: 'gone' } };
  }

  return { ok: true, value: body.data as T };
}

export function fetchPublicSurvey(token: string) {
  return callPublic<PublicSurvey>(
    `/public/surveys/${encodeURIComponent(token)}`,
  );
}

export function submitPublicSurvey(token: string, answers: PublicAnswer[]) {
  return callPublic<{ response_id: string }>(
    `/public/surveys/${encodeURIComponent(token)}/responses`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ answers }),
    },
  );
}
