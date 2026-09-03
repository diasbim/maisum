import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  lifecycleLabel,
  relationshipLabel,
  retentionLabel,
  staffRoleLabel,
  staffStatusLabel,
} from './merchant-labels';

test('the stored states a business sees are in Portuguese', () => {
  assert.equal(relationshipLabel('ACTIVE'), 'Ativo');
  assert.equal(relationshipLabel('BLOCKED'), 'Bloqueado');
  assert.equal(retentionLabel('AT_RISK'), 'Em risco');
  assert.equal(lifecycleLabel('ADVOCATE'), 'Embaixador');
  assert.equal(staffRoleLabel('OWNER'), 'Proprietário');
  assert.equal(staffStatusLabel('INACTIVE'), 'Inativo');
});

/**
 * A few states are the same word in both languages, and inventing a
 * Portuguese one for them would read as a mistake. They are listed rather than
 * inferred, so that a genuinely untranslated state cannot hide among them.
 */
const SAME_IN_BOTH = new Set(['VIP']);

/**
 * The states the mobile app can actually write, read from the app.
 *
 * Hard-coding the list here would only assert that this test agrees with
 * itself. The app is where these strings are decided, so the app is what this
 * reads: a stage added to `customer.dart` fails this test rather than reaching
 * a business owner as an English enum on a screen nobody re-checked.
 */
const CUSTOMER_DART = readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'lib',
    'features',
    'customers',
    'domain',
    'customer.dart',
  ),
  'utf8',
);

/** The `'VALUE'` literals a storage extension maps its enum onto. */
function storageValues(extension: string): string[] {
  const block = new RegExp(
    `extension ${extension} on \\w+ \\{([\\s\\S]*?)\\n\\}`,
  ).exec(CUSTOMER_DART);
  assert.ok(block, `${extension} is no longer in customer.dart`);
  return [...block[1].matchAll(/=>\s*'([A-Z_]+)'/g)].map((match) => match[1]);
}

/** An enum whose storage value is just its name, uppercased. */
function enumValues(name: string): string[] {
  const block = new RegExp(`enum ${name} \\{([^}]*)\\}`).exec(CUSTOMER_DART);
  assert.ok(block, `enum ${name} is no longer in customer.dart`);
  return block[1]
    .split(',')
    .map((entry) => entry.trim())
    .filter((entry) => entry !== '')
    .map((entry) => entry.toUpperCase());
}

test('every state the app can write has a translation', () => {
  const cases: Array<[string, (value: string) => string | null, string[]]> = [
    ['lifecycle stage', lifecycleLabel, storageValues('CustomerLifecycleStageStorage')],
    ['retention status', retentionLabel, storageValues('CustomerRetentionStatusStorage')],
    ['relationship status', relationshipLabel, enumValues('BusinessCustomerStatus')],
    // The app_user role and status are not modelled in customer.dart; these
    // are the values the seeded documents and the console filters use.
    ['staff role', staffRoleLabel, ['OWNER', 'MANAGER', 'STAFF']],
    ['staff status', staffStatusLabel, ['ACTIVE', 'INACTIVE', 'SUSPENDED']],
  ];

  for (const [what, label, values] of cases) {
    // Guards the guard: a parse that found nothing would pass vacuously.
    assert.ok(values.length >= 3, `${what}: found only ${values.length} values`);

    for (const value of values) {
      if (SAME_IN_BOTH.has(value)) {
        assert.equal(label(value), value, `${what} ${value} changed unexpectedly`);
        continue;
      }
      assert.notEqual(label(value), value, `${what} ${value} is untranslated`);
    }
  }
});

test('an unknown state passes through rather than becoming a dash', () => {
  // A state this file has not caught up with is still information; hiding it
  // would leave the screen silently wrong instead of visibly behind.
  assert.equal(relationshipLabel('SOMETHING_NEW'), 'SOMETHING_NEW');
  assert.equal(staffStatusLabel('PROBATION'), 'PROBATION');
});

test('the stored casing and stray spacing do not matter', () => {
  assert.equal(relationshipLabel('active'), 'Ativo');
  assert.equal(relationshipLabel('  Blocked '), 'Bloqueado');
});

test('absent is absent, so the screen can print its own dash', () => {
  assert.equal(relationshipLabel(null), null);
  assert.equal(lifecycleLabel(''), null);
});
