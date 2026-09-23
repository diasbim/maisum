import assert from 'node:assert/strict';
import test from 'node:test';

import {
  bootstrapDocuments,
  FEATURE_KEYS,
  FREE_PLAN,
  monthlyWindow,
  WHATSAPP_MESSAGES_METRIC,
} from './merchant_bootstrap';

const MERCHANT = 'm-1';
const NOW = Date.UTC(2026, 8, 15, 12, 0, 0); // 15 September 2026

function seed(status = 'TRIAL') {
  return bootstrapDocuments({
    merchantId: MERCHANT,
    subscriptionStatus: status,
    now: NOW,
  });
}

function only(collection: string) {
  return seed().filter((doc) => doc.collection === collection);
}

/* --------------------------------------------------- agreement with the app */

/**
 * The feature keys and what each plan grants are the app's, and reach here
 * through plan_policy.generated.ts — plan_policy_codegen.test.ts is what holds
 * that file to the Dart. What is left to check here is that the seeder uses
 * them rather than deciding for itself.
 */
test('a new business starts on the free plan exactly as the app defines it', () => {
  const state = only('subscription_state')[0];
  assert.equal(state.data.plan_code, FREE_PLAN.code);
  assert.equal(state.data.plan_name, FREE_PLAN.name);
});

test('the free plan is a real subset of what exists', () => {
  // If this ever stops holding, seeding every feature would look correct.
  assert.ok(FREE_PLAN.features.length > 0, 'the free plan grants nothing');
  assert.ok(
    FREE_PLAN.features.length < FEATURE_KEYS.length,
    'the free plan grants everything the app has',
  );
});

/* ------------------------------------------------------------ what is written */

test('a new business gets exactly one subscription state', () => {
  const rows = only('subscription_state');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].id, MERCHANT);
  assert.equal(rows[0].data.plan_code, 'free');
  assert.equal(rows[0].data.status, 'TRIAL');
});

test('the status on the business document is carried through', () => {
  // A business created as ACTIVE must not be seeded as TRIAL: the app shows
  // this string, and the console reads it to decide who is paying.
  const rows = bootstrapDocuments({
    merchantId: MERCHANT,
    subscriptionStatus: 'ACTIVE',
    now: NOW,
  }).filter((doc) => doc.collection === 'subscription_state');
  assert.equal(rows[0].data.status, 'ACTIVE');
});

test('a blank status falls back rather than writing an empty one', () => {
  const rows = bootstrapDocuments({
    merchantId: MERCHANT,
    subscriptionStatus: '   ',
    now: NOW,
  }).filter((doc) => doc.collection === 'subscription_state');
  assert.equal(rows[0].data.status, 'TRIAL');
});

test('every feature key gets an entitlement and a flag', () => {
  assert.equal(only('entitlements').length, FEATURE_KEYS.length);
  assert.equal(only('feature_flags').length, FEATURE_KEYS.length);
});

test('the entitlements enabled are exactly the ones the plan grants', () => {
  const enabled = only('entitlements')
    .filter((doc) => doc.data.is_enabled === true)
    .map((doc) => doc.data.feature_key);
  assert.deepEqual(enabled, [...FREE_PLAN.features]);
});

test('a flag is on even where the plan does not grant the feature', () => {
  // The two answer different questions: the entitlement says whether the plan
  // includes it, the flag says whether it has been withdrawn from this
  // business. A new business has nothing withdrawn.
  const off = only('feature_flags').filter((doc) => doc.data.is_enabled !== true);
  assert.deepEqual(off, []);
});

test('document ids match what the app used to write', () => {
  // A business seeded by the old client path and one seeded here have to be
  // the same business; nothing downstream should be able to tell them apart.
  const entitlement = only('entitlements')[0];
  assert.equal(entitlement.id, `${MERCHANT}_whatsapp_automation`);
  assert.equal(entitlement.data.id, entitlement.id);

  const config = only('remote_config')[0];
  assert.equal(config.id, `${MERCHANT}_billing_whatsapp_price`);
});

test('the WhatsApp quota covers the current calendar month', () => {
  const quota = only('usage_balances')[0];
  const window = monthlyWindow(new Date(NOW));

  assert.equal(quota.data.metric_key, WHATSAPP_MESSAGES_METRIC);
  assert.equal(quota.data.window_start, window.start);
  assert.equal(quota.data.window_end, window.end);
  assert.equal(quota.data.used, 0);
  assert.equal(quota.data.limit_value, FREE_PLAN.whatsappMonthlyLimit);
  assert.equal(quota.id, `${MERCHANT}_${WHATSAPP_MESSAGES_METRIC}_${window.start}`);
});

test('the month window ends a millisecond before the next one begins', () => {
  const september = monthlyWindow(new Date(2026, 8, 15));
  const october = monthlyWindow(new Date(2026, 9, 1));
  assert.equal(september.end + 1, october.start);
});

test('December rolls into January rather than into month thirteen', () => {
  const december = monthlyWindow(new Date(2026, 11, 20));
  const january = monthlyWindow(new Date(2027, 0, 5));
  assert.equal(december.end + 1, january.start);
});

test('every seeded document carries the business it belongs to', () => {
  for (const doc of seed()) {
    assert.equal(
      doc.data.merchant_id,
      MERCHANT,
      `${doc.collection}/${doc.id} has no merchant_id`,
    );
    assert.equal(doc.data.updated_at, NOW);
  }
});

test('only server-owned collections are seeded', () => {
  // Nothing here may touch a collection the client is allowed to write, or the
  // trigger would be overwriting the till's own work.
  const collections = new Set(seed().map((doc) => doc.collection));
  assert.deepEqual(
    [...collections].sort(),
    [
      'entitlements',
      'feature_flags',
      'remote_config',
      'subscription_state',
      'usage_balances',
    ],
  );
});
