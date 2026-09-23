import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createSurveyLinkToken,
  SURVEY_LINK_TTL_MS,
  verifySurveyLinkToken,
} from './survey_link.js';

const SECRET = 'a-secret-that-only-the-server-knows';
const NOW = 1_788_307_006_310;

function token(overrides: Partial<Parameters<typeof createSurveyLinkToken>[0]> = {}) {
  return createSurveyLinkToken({
    merchantId: 'merchant-1',
    surveyId: '9c858901-8a57-4791-81fe-4c455b099bc9',
    issuedAt: NOW,
    expiresAt: NOW + SURVEY_LINK_TTL_MS,
    secret: SECRET,
    ...overrides,
  });
}

test('a link sent to one customer answers for that customer', () => {
  const verified = verifySurveyLinkToken({
    token: token({ customerId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479' }),
    secret: SECRET,
    now: NOW + 1000,
  });

  assert.equal(verified?.merchantId, 'merchant-1');
  assert.equal(verified?.surveyId, '9c858901-8a57-4791-81fe-4c455b099bc9');
  assert.equal(verified?.customerId, 'f47ac10b-58cc-4372-a567-0e02b2c3d479');
});

test('a link with no customer is anonymous, not invalid', () => {
  // The poster-on-the-wall case. "Enviados ou preenchidos no local" means both
  // shapes are legitimate, and the difference lives in the token.
  const verified = verifySurveyLinkToken({
    token: token(),
    secret: SECRET,
    now: NOW + 1000,
  });

  assert.equal(verified?.customerId, null);
  assert.equal(verified?.surveyId, '9c858901-8a57-4791-81fe-4c455b099bc9');
});

test('the business is carried in the token, so a verified link needs no scoping', () => {
  // Without this the route would take the merchant id from somewhere the
  // caller controls, which on an unauthenticated endpoint is every caller.
  const verified = verifySurveyLinkToken({
    token: token({ merchantId: 'merchant-2' }),
    secret: SECRET,
    now: NOW + 1000,
  });
  assert.equal(verified?.merchantId, 'merchant-2');
});

test('another secret does not open the link', () => {
  assert.equal(
    verifySurveyLinkToken({
      token: token(),
      secret: 'not-the-secret',
      now: NOW + 1000,
    }),
    null,
  );
});

test('rotating the secret revokes every link already sent', () => {
  const sent = [token(), token({ customerId: 'c1' }), token({ surveyId: 'survey-2' })];
  for (const one of sent) {
    assert.equal(
      verifySurveyLinkToken({ token: one, secret: 'rotated', now: NOW + 1 }),
      null,
    );
  }
});

test('an edited payload fails even when the edit is plausible', () => {
  // Swapping the survey id for another of the same shape is the attack this
  // signature exists to stop: without it, one valid link opens every survey.
  const original = token();
  const [prefix, payload, signature] = original.split('.');
  const decoded = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
  decoded.s = 'survey-somebody-elses';
  const edited = Buffer.from(JSON.stringify(decoded), 'utf8').toString('base64url');

  assert.equal(
    verifySurveyLinkToken({
      token: `${prefix}.${edited}.${signature}`,
      secret: SECRET,
      now: NOW + 1000,
    }),
    null,
  );
});

test('an expired link is refused', () => {
  assert.equal(
    verifySurveyLinkToken({
      token: token(),
      secret: SECRET,
      now: NOW + SURVEY_LINK_TTL_MS + 1,
    }),
    null,
  );
});

test('a link is refused at the exact moment it expires', () => {
  assert.equal(
    verifySurveyLinkToken({
      token: token(),
      secret: SECRET,
      now: NOW + SURVEY_LINK_TTL_MS,
    }),
    null,
  );
  assert.ok(
    verifySurveyLinkToken({
      token: token(),
      secret: SECRET,
      now: NOW + SURVEY_LINK_TTL_MS - 1,
    }),
  );
});

test('a link from the future is refused', () => {
  assert.equal(
    verifySurveyLinkToken({ token: token(), secret: SECRET, now: NOW - 1 }),
    null,
  );
});

test('malformed tokens are refused rather than thrown on', () => {
  const junk = [
    '',
    'sl1',
    'sl1.',
    'sl1..',
    'sl1.not-base64url!.sig',
    'cq1.abc.def',
    token().replace('sl1', 'sl2'),
    token().slice(0, -3),
  ];

  for (const one of junk) {
    assert.equal(
      verifySurveyLinkToken({ token: one, secret: SECRET, now: NOW + 1 }),
      null,
      `"${one}" was accepted`,
    );
  }
});

test('a payload that is valid JSON but not ours is refused', () => {
  // Signed with our secret — so this is the case where only the field checks
  // stand between a caller and a survey read.
  const sneaky = Buffer.from(
    JSON.stringify({ v: 1, m: '', s: '../../etc', c: null, iat: NOW, exp: NOW + 1000 }),
    'utf8',
  ).toString('base64url');
  const signed = createSurveyLinkToken({
    merchantId: 'merchant-1',
    surveyId: 'survey-1',
    issuedAt: NOW,
    expiresAt: NOW + 1000,
    secret: SECRET,
  });
  const signature = signed.split('.')[2];

  assert.equal(
    verifySurveyLinkToken({
      token: `sl1.${sneaky}.${signature}`,
      secret: SECRET,
      now: NOW + 1,
    }),
    null,
  );
});
