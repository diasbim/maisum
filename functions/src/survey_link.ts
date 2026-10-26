import { createHmac, timingSafeEqual } from 'crypto';

/**
 * The link a customer opens to answer a survey.
 *
 * Signed rather than stored, for the same reason the customer QR token is: a
 * link the server can verify without a lookup needs no column, no migration
 * and no sync path, and the app can hand one out while offline. Rotating the
 * secret revokes every link at once.
 *
 * The token carries who it was issued to, when that is known. A survey answered
 * through a link sent to one customer is attributed to them, which is what lets
 * the answer feed recovery; a link printed on a poster carries no customer and
 * the answer is anonymous. Both are legitimate — "enviados ou preenchidos no
 * local" — and the difference is in the token, not in a separate endpoint.
 */

type SurveyLinkPayload = {
  v: 1;
  /** The business, so a verified token needs no further scoping. */
  m: string;
  s: string;
  /** The customer it was sent to, or null for a link anyone may open. */
  c: string | null;
  iat: number;
  exp: number;
};

export type VerifiedSurveyLink = {
  merchantId: string;
  surveyId: string;
  customerId: string | null;
  issuedAt: number;
  expiresAt: number;
};

/** Long enough to survive a slow reply, short enough that a leaked link dies. */
export const SURVEY_LINK_TTL_MS = 30 * 24 * 60 * 60 * 1000;

function sign(encodedPayload: string, secret: string): string {
  return createHmac('sha256', secret)
    .update(`survey-link-v1.${encodedPayload}`)
    .digest('base64url');
}

/** Ids are uuids as the app writes them; anything else is not ours. */
const ID = /^[A-Za-z0-9_-]{8,128}$/;

export function createSurveyLinkToken(input: {
  merchantId: string;
  surveyId: string;
  customerId?: string | null;
  issuedAt: number;
  expiresAt: number;
  secret: string;
}): string {
  const payload: SurveyLinkPayload = {
    v: 1,
    m: input.merchantId,
    s: input.surveyId,
    c: input.customerId ?? null,
    iat: input.issuedAt,
    exp: input.expiresAt,
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload), 'utf8').toString(
    'base64url',
  );
  return `sl1.${encodedPayload}.${sign(encodedPayload, input.secret)}`;
}

export function verifySurveyLinkToken(input: {
  token: string;
  secret: string;
  now: number;
}): VerifiedSurveyLink | null {
  const parts = input.token.split('.');
  if (parts.length !== 3 || parts[0] !== 'sl1' || !parts[1] || !parts[2]) {
    return null;
  }

  // Signature before parse: an unsigned payload is never JSON we deserialize.
  const expected = Buffer.from(sign(parts[1], input.secret));
  const received = Buffer.from(parts[2]);
  if (
    expected.length !== received.length ||
    !timingSafeEqual(expected, received)
  ) {
    return null;
  }

  let payload: SurveyLinkPayload;
  try {
    payload = JSON.parse(
      Buffer.from(parts[1], 'base64url').toString('utf8'),
    ) as SurveyLinkPayload;
  } catch {
    return null;
  }

  if (
    payload.v !== 1 ||
    typeof payload.m !== 'string' ||
    typeof payload.s !== 'string' ||
    !ID.test(payload.m) ||
    !ID.test(payload.s) ||
    (payload.c !== null && (typeof payload.c !== 'string' || !ID.test(payload.c))) ||
    !Number.isSafeInteger(payload.iat) ||
    !Number.isSafeInteger(payload.exp) ||
    payload.iat > input.now ||
    payload.exp <= input.now ||
    payload.exp <= payload.iat
  ) {
    return null;
  }

  return {
    merchantId: payload.m,
    surveyId: payload.s,
    customerId: payload.c,
    issuedAt: payload.iat,
    expiresAt: payload.exp,
  };
}
