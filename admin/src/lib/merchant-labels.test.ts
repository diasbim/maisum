import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  featureLabel,
  lifecycleLabel,
  redemptionStatusLabel,
  relationshipLabel,
  retentionLabel,
  staffRoleLabel,
  staffStatusLabel,
  subscriptionLabel,
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

/**
 * The staff states, read from where the app decides them.
 *
 * These are not modelled in `customer.dart`, and this test used to list them
 * by hand — which is exactly the thing the comment above warns against. The
 * hand-written list said `SUSPENDED`, a state nothing writes, and never
 * mentioned `INVITED`, a state the app writes on every team invitation. So the
 * table went untranslated and the suite stayed green.
 */
const APP_CONSTANTS_DART = readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'lib',
    'core',
    'constants',
    'app_constants.dart',
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

/** The subscription states, read from the enum that defines them. */
const SUBSCRIPTION_DART = readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'lib',
    'features',
    'subscription',
    'domain',
    'subscription_status.dart',
  ),
  'utf8',
);

/** The `'VALUE'` literals `SubscriptionStatus.code` maps its enum onto. */
function subscriptionCodes(): string[] {
  const block = /String get code => switch \(this\) \{([\s\S]*?)\n {6}\};/.exec(
    SUBSCRIPTION_DART,
  );
  assert.ok(block, 'SubscriptionStatus.code is no longer where it was');
  return [...block[1].matchAll(/=>\s*'([A-Z_]+)'/g)].map((match) => match[1]);
}

/**
 * The `'VALUE'` literals of every `AppConstants` field sharing a prefix.
 *
 * `[A-Z_]+` is what keeps `appUserRoleKey = 'app_user_role'` — a preferences
 * key, not a role — out of the role list.
 */
function constantValues(prefix: string): string[] {
  const pattern = new RegExp(
    `static const String ${prefix}\\w+ = '([A-Z_]+)';`,
    'g',
  );
  return [...APP_CONSTANTS_DART.matchAll(pattern)].map((match) => match[1]);
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
  // The last entry is how many values the parse must find. It is per case
  // because the app writes only two roles, and a blanket minimum would either
  // fail on that one or go slack on the rest.
  const cases: Array<
    [string, (value: string) => string | null, string[], number]
  > = [
    ['lifecycle stage', lifecycleLabel, storageValues('CustomerLifecycleStageStorage'), 7],
    ['retention status', retentionLabel, storageValues('CustomerRetentionStatusStorage'), 4],
    ['relationship status', relationshipLabel, enumValues('BusinessCustomerStatus'), 3],
    ['staff role', staffRoleLabel, constantValues('appUserRole'), 2],
    ['staff status', staffStatusLabel, constantValues('appUserStatus'), 3],
    ['subscription status', subscriptionLabel, subscriptionCodes(), 6],
  ];

  for (const [what, label, values, least] of cases) {
    // Guards the guard: a parse that found nothing would pass vacuously.
    assert.ok(
      values.length >= least,
      `${what}: found only ${values.length} values`,
    );

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

/**
 * The features a plan can switch on, read from the app's own list.
 *
 * `FeatureKeys` is the canonical set — the Functions provision exactly these —
 * so a feature added there without a Portuguese name should fail here rather
 * than reach a business as `engage_manage_recovery`.
 */
const FEATURE_KEYS_DART = readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'lib',
    'features',
    'subscription',
    'domain',
    'feature_keys.dart',
  ),
  'utf8',
);

function featureKeys(): string[] {
  return [
    ...FEATURE_KEYS_DART.matchAll(
      /static const String \w+ = '([a-z_]+)';/g,
    ),
  ].map((match) => match[1]);
}

/**
 * What `featureLabel` and `metricLabel` produce for a key they do not know.
 *
 * Both fall through to a tidied version of the key rather than hiding it, so
 * "is it translated?" cannot be asked as "did it change?" — `analytics`
 * becomes `Analytics` either way. This is the string a real translation has to
 * beat.
 */
function semTraducao(value: string): string {
  const words = value.replace(/_/g, ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

test('every feature a plan can grant has a name of its own', () => {
  const keys = featureKeys();
  assert.ok(keys.length >= 10, `found only ${keys.length} feature keys`);

  for (const key of keys) {
    assert.notEqual(
      featureLabel(key),
      semTraducao(key),
      `${key} reaches the business untranslated`,
    );
  }
});

/**
 * The redemption states, read from the contract that declares them.
 *
 * The portal used to print these raw, on the stated grounds that the app wrote
 * no fixed vocabulary for redemptions. It does, and this is where it is
 * written down.
 */
const REDEMPTION_CONTRACT_TS = readFileSync(
  path.join(
    __dirname,
    '..',
    '..',
    'functions',
    'src',
    'customer_api_contracts.ts',
  ),
  'utf8',
);

function redemptionStatuses(): string[] {
  const line = /redemption_status:\s*([^;]+);/.exec(REDEMPTION_CONTRACT_TS);
  assert.ok(line, 'redemption_status is no longer in customer_api_contracts.ts');
  return [...line[1].matchAll(/'([A-Z_]+)'/g)].map((match) => match[1]);
}

test('every redemption state has a translation', () => {
  const states = redemptionStatuses();
  assert.ok(states.length >= 3, `found only ${states.length} states`);

  for (const state of states) {
    assert.notEqual(
      redemptionStatusLabel(state),
      state,
      `${state} reaches the business untranslated`,
    );
  }
});
