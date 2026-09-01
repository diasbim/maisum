import assert from 'node:assert/strict';
import test from 'node:test';

import {
  projectBusinessToMerchant,
  SKIP_EXPLANATIONS,
} from './merchant_projection.js';

const NOW = 1_780_000_000_000;

test('projects a complete business onto the merchants row', () => {
  const result = projectBusinessToMerchant(
    'm-1',
    {
      id: 'm-1',
      merchant_name: '  Cafe Central  ',
      phone: ' +258840000000 ',
      city: 'Maputo',
      created_at: 1_770_000_000_000,
      updated_at: 1_775_000_000_000,
    },
    NOW,
  );

  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') return;
  assert.deepEqual(result.row, {
    id: 'm-1',
    name: 'Cafe Central',
    phone: '+258840000000',
    created_at: 1_770_000_000_000,
    updated_at: 1_775_000_000_000,
  });
});

test('reads the name from merchant_name, which is not what the column is called', () => {
  // The single most likely way to get this wrong: Firestore writes
  // `merchant_name`, the column is `name`. A straight copy yields NULL and the
  // NOT NULL constraint rejects the row.
  const result = projectBusinessToMerchant('m-2', { merchant_name: 'Salao Bela', phone: '+258841111111' }, NOW);
  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') return;
  assert.equal(result.row.name, 'Salao Bela');
});

test('falls back to name for documents written before merchant_name settled', () => {
  const result = projectBusinessToMerchant('m-3', { name: 'Antigo', phone: '+258842222222' }, NOW);
  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') return;
  assert.equal(result.row.name, 'Antigo');
});

test('refuses a business with no name instead of inventing one', () => {
  const result = projectBusinessToMerchant('m-4', { phone: '+258843333333' }, NOW);
  assert.equal(result.status, 'skipped');
  if (result.status !== 'skipped') return;
  assert.equal(result.reason, 'missing_name');
});

test('refuses a business with no phone rather than substituting a placeholder', () => {
  // merchants.phone is NOT NULL UNIQUE. Any placeholder would be claimed by
  // the first incomplete business and collide with every one after it.
  const result = projectBusinessToMerchant('m-5', { merchant_name: 'Sem telefone' }, NOW);
  assert.equal(result.status, 'skipped');
  if (result.status !== 'skipped') return;
  assert.equal(result.reason, 'missing_phone');
});

test('treats a blank string as absent, not as a value', () => {
  const result = projectBusinessToMerchant(
    'm-6',
    { merchant_name: '   ', phone: '+258844444444' },
    NOW,
  );
  assert.equal(result.status, 'skipped');
  if (result.status !== 'skipped') return;
  assert.equal(result.reason, 'missing_name');
});

test('rejects a document with no merchant id', () => {
  for (const id of ['', '   ', null, undefined, 42]) {
    const result = projectBusinessToMerchant(id, { merchant_name: 'X', phone: '+1' }, NOW);
    assert.equal(result.status, 'skipped', `id ${JSON.stringify(id)}`);
    if (result.status !== 'skipped') continue;
    assert.equal(result.reason, 'missing_merchant_id');
  }
});

test('supplies timestamps only when the document has none', () => {
  const missing = projectBusinessToMerchant(
    'm-7',
    { merchant_name: 'Novo', phone: '+258845555555' },
    NOW,
  );
  assert.equal(missing.status, 'ready');
  if (missing.status !== 'ready') return;
  assert.equal(missing.row.created_at, NOW);
  // The merchant list orders by updated_at, so a row without one still needs a
  // sortable value rather than a null.
  assert.equal(missing.row.updated_at, NOW);

  const createdOnly = projectBusinessToMerchant(
    'm-8',
    { merchant_name: 'Novo', phone: '+258846666666', created_at: 1_771_000_000_000 },
    NOW,
  );
  assert.equal(createdOnly.status, 'ready');
  if (createdOnly.status !== 'ready') return;
  assert.equal(createdOnly.row.updated_at, 1_771_000_000_000);
});

test('accepts a timestamp that arrived as a string', () => {
  const result = projectBusinessToMerchant(
    'm-9',
    { merchant_name: 'X', phone: '+258847777777', created_at: '1770000000000' },
    NOW,
  );
  assert.equal(result.status, 'ready');
  if (result.status !== 'ready') return;
  assert.equal(result.row.created_at, 1_770_000_000_000);
});

test('tolerates a missing document body', () => {
  const result = projectBusinessToMerchant('m-10', null, NOW);
  assert.equal(result.status, 'skipped');
});

test('every skip reason has an explanation for the backfill report', () => {
  const reasons = ['missing_merchant_id', 'missing_name', 'missing_phone'] as const;
  for (const reason of reasons) {
    assert.equal(typeof SKIP_EXPLANATIONS[reason], 'string');
    assert.ok(SKIP_EXPLANATIONS[reason].length > 0);
  }
});
