import assert from 'node:assert/strict';
import test from 'node:test';

import {
  bandTone,
  budgetUsedPercent,
  claimLabel,
  claimTone,
  customerWarning,
  emptyLeadsMessage,
  enrichmentEmptyMessage,
  enrichmentTone,
  relativeTime,
  statusTone,
} from './prospecting-labels';

/* ------------------------------------------------------------------ tones */

test('the two compliance stops are red, not neutral', () => {
  // They are the ones an operator must not mistake for "not started".
  assert.equal(statusTone('DO_NOT_CONTACT'), 'red');
  assert.equal(statusTone('OPTED_OUT'), 'red');
});

test('progress is green and waiting is amber', () => {
  assert.equal(statusTone('CUSTOMER'), 'green');
  assert.equal(statusTone('TRIAL'), 'green');
  assert.equal(statusTone('CONTACTED'), 'amber');
  assert.equal(statusTone('READY_TO_CONTACT'), 'amber');
});

test('an unrecognised status stays neutral rather than being coloured by accident', () => {
  assert.equal(statusTone('SOMETHING_NEW'), 'navy');
  assert.equal(statusTone('RAW'), 'navy');
});

test('the bands carry their own tones', () => {
  assert.equal(bandTone('PRIORITY'), 'green');
  assert.equal(bandTone('GOOD'), 'amber');
  assert.equal(bandTone('LOW_FIT'), 'red');
  assert.equal(bandTone(null), 'navy');
});

test('a blocked budget is amber, because nothing went wrong', () => {
  // The cap did its job. Showing it as an error would send an operator looking
  // for a fault that does not exist.
  assert.equal(enrichmentTone('BUDGET_BLOCKED'), 'amber');
  assert.equal(enrichmentTone('FAILED'), 'red');
  assert.equal(enrichmentTone('COMPLETE'), 'green');
});

/* ----------------------------------------------------------------- claims */

test('a fact and an inference are not synonyms', () => {
  assert.equal(claimLabel('FACT'), 'Observado');
  assert.equal(claimLabel('INFERENCE'), 'Dedução');
  assert.notEqual(claimLabel('FACT'), claimLabel('INFERENCE'));
  assert.equal(claimTone('FACT'), 'green');
  assert.equal(claimTone('INFERENCE'), 'amber');
});

test('anything that is neither is shown as unknown', () => {
  assert.equal(claimLabel('GUESS'), 'Desconhecido');
});

/* ---------------------------------------------------------------- empties */

test('the three empty lists say three different things', () => {
  const first = emptyLeadsMessage({ filtered: false, jobRunning: false });
  const filtered = emptyLeadsMessage({ filtered: true, jobRunning: false });
  const running = emptyLeadsMessage({ filtered: false, jobRunning: true });

  assert.notEqual(first, filtered);
  assert.notEqual(filtered, running);
  assert.ok(first.includes('procurar'));
  assert.ok(filtered.includes('filtros'));
  assert.ok(running.includes('correr'));
});

test('a running search wins over a filter, because it is the newer fact', () => {
  assert.equal(
    emptyLeadsMessage({ filtered: true, jobRunning: true }),
    emptyLeadsMessage({ filtered: false, jobRunning: true }),
  );
});

test('no decision maker is explained as normal, not as an error', () => {
  // Most small businesses in Maputo have none, and an operator who reads this
  // as a failure will keep retrying it at cost.
  const message = enrichmentEmptyMessage('NO_RESULT');
  assert.ok(message.includes('comum'));
  assert.ok(message.includes('não é um erro'));
});

test('a blocked budget says nothing was charged', () => {
  const message = enrichmentEmptyMessage('BUDGET_BLOCKED');
  assert.ok(message.includes('pausa'));
  assert.ok(message.includes('Nada foi cobrado'));
});

test('a below-threshold lead is told how to change the outcome', () => {
  assert.ok(enrichmentEmptyMessage('BELOW_THRESHOLD').includes('definições'));
});

/* ------------------------------------------------- the customer warning */

test('a confirmed customer is stated as a fact', () => {
  const warning = customerWarning({
    status: 'EXISTING_CUSTOMER',
    suspectedMerchantId: 'm1',
  });
  assert.equal(warning?.tone, 'red');
  assert.ok(warning?.text.includes('já é cliente'));
});

test('a name-only match is worded as something to confirm, not as a fact', () => {
  // `businesses` stores no city, so a name match has nothing to disambiguate
  // it — and EXISTING_CUSTOMER is terminal.
  const warning = customerWarning({ status: 'SCORED', suspectedMerchantId: 'm1' });
  assert.equal(warning?.tone, 'amber');
  assert.ok(warning?.text.includes('Confirme'));
  assert.ok(warning?.text.includes('apenas o mesmo nome'));
});

test('a lead with no match wears no warning', () => {
  assert.equal(customerWarning({ status: 'SCORED', suspectedMerchantId: null }), null);
});

/* ------------------------------------------------------------------- time */

test('relative time is coarse, which is what a timeline needs', () => {
  const now = 1_758_000_000_000;
  assert.equal(relativeTime(now, now), 'agora');
  assert.equal(relativeTime(now - 5 * 60_000, now), 'há 5 min');
  assert.equal(relativeTime(now - 3 * 3_600_000, now), 'há 3 h');
  assert.equal(relativeTime(now - 3 * 86_400_000, now), 'há 3 dias');
  assert.equal(relativeTime(now - 86_400_000, now), 'há 1 dia');
  assert.equal(relativeTime(now - 60 * 86_400_000, now), 'há 2 meses');
  assert.equal(relativeTime(null, now), '—');
});

test('a clock skew reads as now rather than as the future', () => {
  const now = 1_758_000_000_000;
  assert.equal(relativeTime(now + 60_000, now), 'agora');
});

/* ----------------------------------------------------------------- budget */

test('the budget bar never overflows its track', () => {
  assert.equal(budgetUsedPercent(25, 50), 50);
  assert.equal(budgetUsedPercent(75, 50), 100);
  assert.equal(budgetUsedPercent(0, 50), 0);
  assert.equal(budgetUsedPercent(10, 0), 0);
});
