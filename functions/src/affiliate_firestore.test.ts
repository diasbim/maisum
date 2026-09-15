import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  allocateAffiliateCode,
  AffiliateCodeExhaustedError,
  CODE_ALLOCATION_ATTEMPTS,
} from './affiliate_firestore.js';
import { CODE_ALPHABET } from './affiliate_engine.js';

const SOURCE = readFileSync(
  path.join(__dirname, '..', 'src', 'affiliate_firestore.ts'),
  'utf8',
);

/**
 * The claim path, tested through the seam that matters.
 *
 * `allocateAffiliateCode` takes `isTaken` rather than reading Firestore itself,
 * so the retry behaviour can be pinned here without an emulator — and so the
 * production caller can pass a *transactional* read, which is the only kind
 * that makes the claim safe. These tests are about the loop; the transaction
 * around it is asserted by reading the source in affiliate_routes.test.ts.
 */

/** Cycles bytes so the generated suffixes differ from attempt to attempt. */
function byteSource(): () => number {
  let n = 0;
  return () => (n++ * 37 + 11) % 256;
}

test('a free code is taken on the first attempt', async () => {
  const allocation = await allocateAffiliateCode({
    name: 'João',
    isTaken: async () => false,
    randomByte: byteSource(),
  });

  test('production suffixes use cryptographic randomness, never the clock', () => {
    assert.match(SOURCE, /randomBytes\(1\)\.readUInt8\(0\)/);
    assert.doesNotMatch(SOURCE, /Timestamp\.now\(\)\.nanoseconds/);
  });

  assert.equal(allocation.attempts, 1);
  assert.match(allocation.code, /^AFI-JOAO-[A-Z0-9]{4}$/);
});

test('a collision is retried with a different suffix', async () => {
  const seen: string[] = [];
  const allocation = await allocateAffiliateCode({
    name: 'Ana',
    randomByte: byteSource(),
    isTaken: async (candidate) => {
      seen.push(candidate);
      return seen.length < 3;
    },
  });

  assert.equal(allocation.attempts, 3);
  assert.equal(seen.length, 3);
  assert.equal(new Set(seen).size, 3, 'the same suffix was tried twice');
});

test('the name stays put across retries; only the suffix moves', async () => {
  const seen: string[] = [];
  await allocateAffiliateCode({
    name: 'Amélia Cossa',
    randomByte: byteSource(),
    isTaken: async (candidate) => {
      seen.push(candidate);
      return seen.length < 4;
    },
  });

  for (const candidate of seen) {
    assert.match(candidate, /^AFI-AMELIA-[A-Z0-9]{4}$/, candidate);
  }
});

test('a full space fails loudly rather than widening the format', async () => {
  // Silently using five characters would produce a code the rest of the
  // product does not expect, in a place nobody would think to look.
  await assert.rejects(
    allocateAffiliateCode({
      name: 'Ana',
      randomByte: byteSource(),
      isTaken: async () => true,
      attempts: 3,
    }),
    (error: unknown) => {
      assert.ok(error instanceof AffiliateCodeExhaustedError);
      assert.match((error as Error).message, /3 attempts/);
      return true;
    },
  );
});

test('it gives up after the configured number of tries, not more', async () => {
  let calls = 0;
  await assert.rejects(
    allocateAffiliateCode({
      name: 'Ana',
      randomByte: byteSource(),
      isTaken: async () => {
        calls++;
        return true;
      },
    }),
    AffiliateCodeExhaustedError,
  );
  assert.equal(calls, CODE_ALLOCATION_ATTEMPTS);
});

test('the attempt budget is worth having', async () => {
  // One retry would make a single unlucky collision a user-visible failure;
  // a hundred would hammer Firestore inside a transaction.
  assert.ok(CODE_ALLOCATION_ATTEMPTS >= 4, 'too few to absorb a collision');
  assert.ok(CODE_ALLOCATION_ATTEMPTS <= 16, 'too many reads for one transaction');
});

test('every candidate offered is a code the product can store', async () => {
  const seen: string[] = [];
  await allocateAffiliateCode({
    name: 'Guilhermina Nhamirre',
    randomByte: byteSource(),
    isTaken: async (candidate) => {
      seen.push(candidate);
      return seen.length < 5;
    },
  });

  for (const candidate of seen) {
    const suffix = candidate.split('-')[2];
    assert.equal(suffix.length, 4);
    for (const character of suffix) {
      assert.ok(CODE_ALPHABET.includes(character), `${character} is off-alphabet`);
    }
    // The name segment is capped at eight, so the whole code stays dictatable.
    assert.ok(candidate.length <= 4 + 8 + 5, candidate);
  }
});
