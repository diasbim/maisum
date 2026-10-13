import assert from 'node:assert/strict';
import test from 'node:test';

import {
  AFFILIATE_TEMPLATE,
  AFFILIATE_TEMPLATES,
  deliverAffiliateMessage,
  isTerminalDelivery,
  maskPhone,
  MAX_DELIVERY_ATTEMPTS,
  nextAttemptDelayMs,
  renderAffiliateMessage,
  rewardStatusText,
  type OutboxMessage,
} from './affiliate_notifications.js';

function message(overrides: Partial<OutboxMessage> = {}): OutboxMessage {
  return {
    idempotencyKey: 'aff_reward:ar_1',
    merchantId: 'merchant-1',
    template: 'affiliate_new_customer',
    toPhoneE164: '+258840000001',
    body: 'corpo',
    ...overrides,
  };
}

/* -------------------------------------------------------------- the words */

test('a pending reward is never described as approved', () => {
  // The affiliate would count on points the merchant has not agreed to, and
  // the correction is worse than the wait.
  assert.equal(rewardStatusText('PENDING'), 'a aguardar aprovação');
  assert.equal(rewardStatusText('APPROVED'), 'aprovados');
});

test('anything that is not approved reads as waiting', () => {
  for (const status of ['PENDING', 'CANCELLED', 'PAID', '', 'something new']) {
    assert.equal(rewardStatusText(status), 'a aguardar aprovação', status);
  }
});

test('the status text is matched regardless of case or padding', () => {
  assert.equal(rewardStatusText('  approved '), 'aprovados');
});

test('every template renders with no placeholder left behind', () => {
  for (const template of AFFILIATE_TEMPLATE) {
    const rendered = renderAffiliateMessage(template, {
      points: 150,
      merchantName: 'Café Central',
      statusText: rewardStatusText('PENDING'),
    });
    assert.ok(!/\{\w+\}/.test(rendered), `${template} left a placeholder`);
    assert.ok(rendered.length > 0);
  }
});

test('the affiliate message names the shop and the reward', () => {
  const rendered = renderAffiliateMessage('affiliate_new_customer', {
    points: 150,
    merchantName: 'Café Central',
    statusText: rewardStatusText('PENDING'),
  });
  assert.match(rendered, /Café Central/);
  assert.match(rendered, /150 pontos de recompensa a aguardar aprovação/);
});

test('an unknown placeholder is left visible rather than blanked', () => {
  // "Tem  pontos" looks like a rounding bug and gets ignored; "Tem {points}
  // pontos" is obviously broken and gets reported.
  const rendered = renderAffiliateMessage('affiliate_new_customer', {
    merchantName: 'Café Central',
    statusText: 'aprovados',
  });
  assert.match(rendered, /\{points\}/);
});

test('a blank shop name does not leave a gap in the sentence', () => {
  const rendered = renderAffiliateMessage('affiliate_new_customer', {
    points: 10,
    merchantName: '   ',
    statusText: 'aprovados',
  });
  assert.match(rendered, /\{merchantName\}/);
});

test('points are whole and never negative', () => {
  assert.match(
    renderAffiliateMessage('customer_referral_thanks', { points: 12.7 }),
    /12 pontos/,
  );
  assert.match(
    renderAffiliateMessage('customer_referral_thanks', { points: -5 }),
    /0 pontos/,
  );
});

test('the templates stay editable strings with braced variables', () => {
  for (const template of AFFILIATE_TEMPLATE) {
    assert.match(
      AFFILIATE_TEMPLATES[template],
      /\{\w+\}/,
      `${template} has no variables and was probably hard-coded`,
    );
  }
});

/* ----------------------------------------------------------- the delivery */

test('with no provider, nothing is sent and nothing is claimed', async () => {
  // The whole point: a stub returning success would mark every message
  // delivered and lose the lot.
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: null,
    notificationsEnabled: true,
  });
  assert.deepEqual(outcome, { status: 'not_configured' });
});

test('not configured is not a failure and does not burn a retry', () => {
  const outcome = { status: 'not_configured' } as const;
  assert.equal(isTerminalDelivery(outcome, MAX_DELIVERY_ATTEMPTS + 10), false);
});

test('a merchant who turned notifications off is not messaged', async () => {
  let called = false;
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: {
      async send() {
        called = true;
        return { providerMessageId: 'x' };
      },
    },
    notificationsEnabled: false,
  });

  assert.deepEqual(outcome, { status: 'skipped', reason: 'notifications_disabled' });
  assert.equal(called, false, 'the adapter was reached anyway');
});

test('a recipient with no number is skipped, not retried forever', async () => {
  const outcome = await deliverAffiliateMessage(message({ toPhoneE164: '  ' }), {
    adapter: { async send() { return { providerMessageId: 'x' }; } },
    notificationsEnabled: true,
  });

  assert.deepEqual(outcome, { status: 'skipped', reason: 'no_phone' });
  assert.equal(isTerminalDelivery(outcome, 1), true);
});

test('a working provider reports what it sent', async () => {
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: { async send() { return { providerMessageId: 'wamid.1' }; } },
    notificationsEnabled: true,
  });

  assert.deepEqual(outcome, { status: 'sent', providerMessageId: 'wamid.1' });
  assert.equal(isTerminalDelivery(outcome, 1), true);
});

test('a throwing provider is a failure, not a crash', async () => {
  const outcome = await deliverAffiliateMessage(message(), {
    adapter: { async send() { throw new Error('502 from provider'); } },
    notificationsEnabled: true,
  });

  assert.equal(outcome.status, 'failed');
  assert.match((outcome as { error: string }).error, /502/);
});

test('a failure retries up to the cap and then stops', () => {
  const failure = { status: 'failed', retryable: true, error: 'boom' } as const;
  for (let attempt = 1; attempt < MAX_DELIVERY_ATTEMPTS; attempt++) {
    assert.equal(isTerminalDelivery(failure, attempt), false, `attempt ${attempt}`);
  }
  assert.equal(isTerminalDelivery(failure, MAX_DELIVERY_ATTEMPTS), true);
});

/* ------------------------------------------------------------- the timing */

test('backoff grows, then stops growing', () => {
  assert.equal(nextAttemptDelayMs(1), 30_000);
  assert.equal(nextAttemptDelayMs(2), 60_000);
  assert.equal(nextAttemptDelayMs(3), 120_000);
});

test('the last retry is still the same day', () => {
  // Uncapped doubling puts it days out, by which point congratulating someone
  // on a sale is strange rather than late.
  const last = nextAttemptDelayMs(MAX_DELIVERY_ATTEMPTS);
  assert.ok(last <= 3_600_000, `${last}ms is longer than an hour`);
});

test('a nonsense attempt number does not produce a nonsense delay', () => {
  assert.ok(nextAttemptDelayMs(0) > 0);
  assert.ok(nextAttemptDelayMs(-3) > 0);
});

/* --------------------------------------------------------------- the logs */

test('a logged number identifies a recipient without reaching them', () => {
  assert.equal(maskPhone('+258840000001'), '***0001');
  assert.notEqual(maskPhone('+258840000001'), maskPhone('+258840000002'));
});

test('a number too short to mask is hidden entirely', () => {
  assert.equal(maskPhone('12'), '***');
  assert.equal(maskPhone(''), '***');
});
