import test from 'node:test';
import assert from 'node:assert/strict';

import {
  cloudAdapterFrom,
  errorFrom,
  templateParameters,
  templatePlaceholders,
  WhatsAppCloudAdapter,
  WhatsAppSendError,
} from './affiliate_whatsapp_cloud.js';
import {
  AFFILIATE_TEMPLATE,
  AFFILIATE_TEMPLATES,
  deliverAffiliateMessage,
  renderAffiliateMessage,
  type OutboxMessage,
} from './affiliate_notifications.js';

/* ---------------------------------------------------------------- fixtures */

function message(overrides: Partial<OutboxMessage> = {}): OutboxMessage {
  return {
    idempotencyKey: 'merchant-1:affiliate_new_customer:sale-9',
    merchantId: 'merchant-1',
    template: 'affiliate_new_customer',
    toPhoneE164: '+258841234567',
    body: 'rendered elsewhere',
    variables: {
      points: 1250,
      merchantName: 'Barbearia Central',
      statusText: 'a aguardar aprovação',
    },
    ...overrides,
  };
}

function okFetch(
  captured: { url?: string; init?: RequestInit } = {},
  id = 'wamid.ABC',
): typeof fetch {
  return (async (url: string | URL | Request, init?: RequestInit) => {
    captured.url = String(url);
    captured.init = init;
    return new Response(JSON.stringify({ messages: [{ id }] }), { status: 200 });
  }) as unknown as typeof fetch;
}

function failingFetch(status: number, payload: unknown): typeof fetch {
  return (async () =>
    new Response(JSON.stringify(payload), { status })) as unknown as typeof fetch;
}

const adapter = (fetchImpl: typeof fetch) =>
  new WhatsAppCloudAdapter({
    accessToken: 'token',
    phoneNumberId: '1234567890',
    fetchImpl,
  });

const body = (init: RequestInit | undefined) =>
  JSON.parse(String(init?.body ?? '{}'));

/* ------------------------------------------------- templates and parameters */

test('every local template has a parameter order read from its own text', () => {
  for (const name of AFFILIATE_TEMPLATE) {
    const placeholders = templatePlaceholders(name);
    const braces = (AFFILIATE_TEMPLATES[name].match(/\{\w+\}/g) ?? []).length;
    assert.equal(
      placeholders.length,
      braces,
      `${name}: a ordem devia cobrir todos os marcadores`,
    );
  }
});

test('the parameter order is the order the placeholders appear in', () => {
  // WhatsApp maps parameters by position. Swapping two sends a real message
  // to a real person with the point total where the name should be.
  assert.deepEqual(templatePlaceholders('affiliate_new_customer'), [
    'merchantName',
    'points',
    'statusText',
  ]);
  assert.deepEqual(templatePlaceholders('customer_referral_thanks'), ['points']);
});

test('the parameters carry the same values the body was rendered from', () => {
  const sent = message();
  const rendered = renderAffiliateMessage(sent.template, sent.variables ?? {});
  for (const value of templateParameters(sent)) {
    assert.ok(
      rendered.includes(value),
      `${value} devia aparecer no corpo renderizado: ${rendered}`,
    );
  }
});

test('points are formatted the same way in both halves', () => {
  assert.deepEqual(templateParameters(message()), [
    'Barbearia Central',
    (1250).toLocaleString('pt-PT'),
    'a aguardar aprovação',
  ]);
});

test('a missing value is a permanent failure, not an empty parameter', () => {
  // "Tem  pontos a aguardar aprovação" reads like a rounding bug to whoever
  // receives it, and no bug report ever reaches anyone.
  assert.throws(
    () => templateParameters(message({ variables: { points: 10 } })),
    (error: unknown) =>
      error instanceof WhatsAppSendError &&
      error.retryable === false &&
      /merchantName/.test(error.message),
  );
});

test('a message built before variables existed fails clearly', () => {
  assert.throws(
    () => templateParameters(message({ variables: undefined })),
    (error: unknown) => error instanceof WhatsAppSendError && !error.retryable,
  );
});

test('a newline inside a value is collapsed, not refused', () => {
  const params = templateParameters(
    message({ variables: { points: 5, merchantName: 'Barbearia\nCentral', statusText: 'aprovados' } }),
  );
  assert.equal(params[0], 'Barbearia Central');
});

/* ----------------------------------------------------------- the request */

test('the request is a template message, never free text', () => {
  const captured = {};
  return adapter(okFetch(captured))
    .send(message())
    .then(() => {
      const payload = body((captured as { init?: RequestInit }).init);
      assert.equal(payload.type, 'template');
      assert.equal(payload.template.name, 'affiliate_new_customer');
      assert.equal(payload.messaging_product, 'whatsapp');
      assert.equal(payload.to, '+258841234567');
      // The rendered body must not travel: outside the 24-hour window Meta
      // rejects it, and the rejection looks like a transient fault.
      assert.ok(!JSON.stringify(payload).includes('rendered elsewhere'));
    });
});

test('the parameters go in the body component, in order', async () => {
  const captured = {};
  await adapter(okFetch(captured)).send(message());
  const payload = body((captured as { init?: RequestInit }).init);
  assert.deepEqual(
    payload.template.components[0].parameters.map((p: { text: string }) => p.text),
    ['Barbearia Central', (1250).toLocaleString('pt-PT'), 'a aguardar aprovação'],
  );
});

test('a template with no placeholders sends no components', async () => {
  const captured = {};
  await adapter(okFetch(captured)).send(
    message({ template: 'customer_referral_thanks', variables: { points: 40 } }),
  );
  const payload = body((captured as { init?: RequestInit }).init);
  assert.equal(payload.template.components.length, 1, 'tem {points}, logo tem componente');
});

test('the token travels in the header and the url names the sending number', async () => {
  const captured: { url?: string; init?: RequestInit } = {};
  await adapter(okFetch(captured)).send(message());
  assert.ok(captured.url?.endsWith('/1234567890/messages'));
  const headers = captured.init?.headers as Record<string, string>;
  assert.equal(headers.authorization, 'Bearer token');
  // Never in the query string: a token there lands in every access log
  // between here and Meta.
  assert.ok(!captured.url?.includes('token'));
});

test('the provider message id is returned', async () => {
  const result = await adapter(okFetch({}, 'wamid.XYZ')).send(message());
  assert.equal(result.providerMessageId, 'wamid.XYZ');
});

test('a 200 with no message id is not treated as sent', async () => {
  const fetchImpl = (async () =>
    new Response(JSON.stringify({ messages: [] }), { status: 200 })) as unknown as typeof fetch;
  await assert.rejects(
    adapter(fetchImpl).send(message()),
    (error: unknown) =>
      error instanceof WhatsAppSendError &&
      // Not retried: it may well have been sent, and sending again is worse.
      error.retryable === false,
  );
});

/* ------------------------------------------------------- error classification */

test('an unapproved template is permanent', () => {
  const error = errorFrom(400, {
    error: { code: 132001, message: 'Template name does not exist' },
  });
  assert.equal(error.retryable, false);
  assert.equal(error.code, 132001);
});

test('a parameter count mismatch is permanent', () => {
  assert.equal(errorFrom(400, { error: { code: 132000 } }).retryable, false);
});

test('a recipient who is not on WhatsApp is permanent', () => {
  assert.equal(errorFrom(400, { error: { code: 131026 } }).retryable, false);
});

test('a rate limit is retryable', () => {
  assert.equal(errorFrom(400, { error: { code: 130429 } }).retryable, true);
  assert.equal(errorFrom(429, {}).retryable, true);
});

test('Meta failing on its own side is retryable', () => {
  assert.equal(errorFrom(500, {}).retryable, true);
  assert.equal(errorFrom(503, {}).retryable, true);
});

test('refused credentials are permanent, so the log line is readable', () => {
  // A queue retrying a bad token every five minutes buries the one line that
  // says the token is bad under thousands that say nothing.
  const error = errorFrom(401, { error: { message: 'Invalid OAuth access token' } });
  assert.equal(error.retryable, false);
  assert.match(error.message, /credenciais/);
});

test('an unrecognised 400 is retried rather than dropped on a guess', () => {
  assert.equal(errorFrom(400, { error: { code: 999999 } }).retryable, true);
});

test('the body is read before the status is judged', async () => {
  // A 429 carrying an unapproved-template code is the template's fault, and
  // retrying it forever would never start working.
  const error = errorFrom(429, { error: { code: 132016 } });
  assert.equal(error.retryable, false);
});

test('a network failure is retryable', async () => {
  const fetchImpl = (async () => {
    throw new Error('ECONNRESET');
  }) as unknown as typeof fetch;
  await assert.rejects(
    adapter(fetchImpl).send(message()),
    (error: unknown) => error instanceof WhatsAppSendError && error.retryable,
  );
});

/* ------------------------------------------------- the delivery boundary */

test('a permanent adapter failure is not retried by the outbox', async () => {
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: {
      send: async () => {
        throw new WhatsAppSendError({ message: 'template disabled', retryable: false });
      },
    },
    notificationsEnabled: true,
  });
  assert.equal(outcome.status, 'failed');
  assert.equal(outcome.status === 'failed' && outcome.retryable, false);
});

test('an adapter that classifies nothing still gets the retrying default', async () => {
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: {
      send: async () => {
        throw new Error('boom');
      },
    },
    notificationsEnabled: true,
  });
  assert.equal(outcome.status === 'failed' && outcome.retryable, true);
});

test('a sent message reports the provider id', async () => {
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: adapter(okFetch({}, 'wamid.OK')),
    notificationsEnabled: true,
  });
  assert.equal(outcome.status, 'sent');
  assert.equal(outcome.status === 'sent' && outcome.providerMessageId, 'wamid.OK');
});

/* --------------------------------------------------------- construction */

test('half a configuration is no configuration', () => {
  // Half-configured would throw on every row and burn the whole backlog's
  // retry budget; null keeps the outbox answering not_configured.
  assert.equal(cloudAdapterFrom({ accessToken: 'x', phoneNumberId: undefined }), null);
  assert.equal(cloudAdapterFrom({ accessToken: undefined, phoneNumberId: 'y' }), null);
  assert.equal(cloudAdapterFrom({ accessToken: '  ', phoneNumberId: 'y' }), null);
  assert.notEqual(cloudAdapterFrom({ accessToken: 'x', phoneNumberId: 'y' }), null);
});

test('an unconfigured provider still answers not_configured, not failed', async () => {
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: cloudAdapterFrom({ accessToken: undefined, phoneNumberId: undefined }),
    notificationsEnabled: true,
  });
  assert.equal(outcome.status, 'not_configured');
});

test('the template language defaults to the one the templates are written in', async () => {
  const captured = {};
  const built = cloudAdapterFrom({ accessToken: 'x', phoneNumberId: '1' });
  assert.ok(built !== null);
  await new WhatsAppCloudAdapter({
    accessToken: 'x',
    phoneNumberId: '1',
    fetchImpl: okFetch(captured),
  }).send(message());
  assert.equal(body((captured as { init?: RequestInit }).init).template.language.code, 'pt_PT');
});
