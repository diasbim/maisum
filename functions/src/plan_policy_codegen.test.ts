import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import {
  GENERATED_FILE,
  appDomainDir,
  readAppPolicy,
  renderPlanPolicy,
} from './plan_policy_codegen';

// __dirname is functions/lib once compiled.
const FUNCTIONS = path.join(__dirname, '..');
const REPO = path.join(FUNCTIONS, '..');

const lf = (value: string) => value.replace(/\r\n/g, '\n');

/* ------------------------------------------------------ against the real app */

test('the committed file is what the app currently says', () => {
  // The one that matters. `firebase deploy` uploads only functions/, so the
  // generated file has to be committed; this is what stops a committed copy
  // from outliving the Dart it was rendered from.
  const rendered = renderPlanPolicy(readAppPolicy(appDomainDir(REPO)));
  const committed = readFileSync(path.join(FUNCTIONS, 'src', GENERATED_FILE), 'utf8');

  assert.equal(
    lf(committed),
    rendered,
    `src/${GENERATED_FILE} no longer matches the app — run \`npm run codegen\``,
  );
});

test('the app is read, not merely parsed into nothing', () => {
  // A parser that quietly returns empty lists would satisfy the test above by
  // generating an empty file from an empty read.
  const policy = readAppPolicy(appDomainDir(REPO));
  assert.ok(policy.featureKeys.length >= 9, `read only ${policy.featureKeys.length} feature keys`);

  const free = policy.plans.find((plan) => plan.code === 'free');
  assert.ok(free, 'the app declares no free plan');
  assert.ok(free.features.length > 0, 'the free plan reads as granting nothing');
  assert.ok(free.whatsappMonthlyLimit !== null, 'the free plan reads as having no limit');
});

/* ------------------------------------------------------------- the parser */

const FEATURE_KEYS_DART = `class FeatureKeys {
  static const String alpha = 'alpha';
  static const String beta = 'beta';

  static const List<String> all = [
    alpha,
    beta,
  ];
}
`;

const PLAN_DART = `enum Plan {
  free,
  pro;

  String get code => switch (this) {
    Plan.free => 'free',
    Plan.pro => 'pro',
  };

  String get displayName => switch (this) {
    Plan.free => 'Free',
    Plan.pro => 'Pro',
  };
}
`;

const PLAN_CATALOG_DART = `class PlanCatalog {
  static const Map<Plan, PlanDefinition> _definitions = {
    Plan.free: PlanDefinition(
      plan: Plan.free,
      features: {FeatureKeys.alpha},
      whatsappMonthlyLimit: 150,
    ),
    Plan.pro: PlanDefinition(
      plan: Plan.pro,
      features: {
        FeatureKeys.alpha,
        FeatureKeys.beta,
      },
      whatsappMonthlyLimit: null,
    ),
  };
}
`;

/** A domain directory holding the three files, with any of them replaced. */
function fixture(overrides: Record<string, string> = {}): string {
  const dir = mkdtempSync(path.join(tmpdir(), 'plan-policy-'));
  const files: Record<string, string> = {
    'feature_keys.dart': FEATURE_KEYS_DART,
    'plan.dart': PLAN_DART,
    'plan_catalog.dart': PLAN_CATALOG_DART,
    ...overrides,
  };
  for (const [name, contents] of Object.entries(files)) {
    writeFileSync(path.join(dir, name), contents, 'utf8');
  }
  return dir;
}

test('plans come out in declaration order, with their code and name', () => {
  const policy = readAppPolicy(fixture());
  assert.deepEqual(
    policy.plans.map((plan) => [plan.code, plan.name]),
    [
      ['free', 'Free'],
      ['pro', 'Pro'],
    ],
  );
});

test('a plan with no WhatsApp limit reads as unlimited, not as zero', () => {
  const policy = readAppPolicy(fixture());
  assert.equal(policy.plans[0].whatsappMonthlyLimit, 150);
  assert.equal(policy.plans[1].whatsappMonthlyLimit, null);
});

test('features follow the order of `all`, not the order the plan lists them', () => {
  // Dart sets are written in whatever order reads well. Sorting them here is
  // what keeps the generated file from changing when nothing has.
  const shuffled = PLAN_CATALOG_DART.replace(
    'FeatureKeys.alpha,\n        FeatureKeys.beta,',
    'FeatureKeys.beta,\n        FeatureKeys.alpha,',
  );
  const policy = readAppPolicy(fixture({ 'plan_catalog.dart': shuffled }));
  assert.deepEqual(policy.plans[1].features, ['alpha', 'beta']);
});

test('a feature key left out of `all` is refused', () => {
  const orphan = FEATURE_KEYS_DART.replace(
    "static const String beta = 'beta';",
    "static const String beta = 'beta';\n  static const String gamma = 'gamma';",
  );
  assert.throws(
    () => readAppPolicy(fixture({ 'feature_keys.dart': orphan })),
    /gamma is missing from FeatureKeys.all/,
  );
});

test('a plan granting a feature that does not exist is refused', () => {
  const invented = PLAN_CATALOG_DART.replace('FeatureKeys.alpha}', 'FeatureKeys.delta}');
  assert.throws(
    () => readAppPolicy(fixture({ 'plan_catalog.dart': invented })),
    /grants FeatureKeys.delta, which does not exist/,
  );
});

test('a plan with no limit declared at all is refused', () => {
  const missing = PLAN_CATALOG_DART.replace('      whatsappMonthlyLimit: 150,\n', '');
  assert.throws(
    () => readAppPolicy(fixture({ 'plan_catalog.dart': missing })),
    /declares no whatsappMonthlyLimit/,
  );
});

test('a renamed getter in the enum is refused rather than guessed at', () => {
  const renamed = PLAN_DART.replace('String get displayName', 'String get label');
  assert.throws(
    () => readAppPolicy(fixture({ 'plan.dart': renamed })),
    /no longer declares the displayName getter/,
  );
});

/* -------------------------------------------------------------- the output */

test('the rendered file compiles the plan codes into keys of PLANS', () => {
  const rendered = renderPlanPolicy(readAppPolicy(fixture()));
  assert.match(rendered, /export const PLANS: Record<PlanCode, PlanPolicy> = \{/);
  assert.match(rendered, /\n {2}free: \{/);
  assert.match(rendered, /\n {2}pro: \{/);
  assert.match(rendered, /export type PlanCode = 'free' \| 'pro';/);
});

test('the rendering is stable for the same input', () => {
  const dir = fixture();
  assert.equal(renderPlanPolicy(readAppPolicy(dir)), renderPlanPolicy(readAppPolicy(dir)));
});
