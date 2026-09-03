"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const strict_1 = __importDefault(require("node:assert/strict"));
const node_fs_1 = require("node:fs");
const node_os_1 = require("node:os");
const node_path_1 = __importDefault(require("node:path"));
const node_test_1 = __importDefault(require("node:test"));
const plan_policy_codegen_1 = require("./plan_policy_codegen");
// __dirname is functions/lib once compiled.
const FUNCTIONS = node_path_1.default.join(__dirname, '..');
const REPO = node_path_1.default.join(FUNCTIONS, '..');
const lf = (value) => value.replace(/\r\n/g, '\n');
/* ------------------------------------------------------ against the real app */
(0, node_test_1.default)('the committed file is what the app currently says', () => {
    // The one that matters. `firebase deploy` uploads only functions/, so the
    // generated file has to be committed; this is what stops a committed copy
    // from outliving the Dart it was rendered from.
    const rendered = (0, plan_policy_codegen_1.renderPlanPolicy)((0, plan_policy_codegen_1.readAppPolicy)((0, plan_policy_codegen_1.appDomainDir)(REPO)));
    const committed = (0, node_fs_1.readFileSync)(node_path_1.default.join(FUNCTIONS, 'src', plan_policy_codegen_1.GENERATED_FILE), 'utf8');
    strict_1.default.equal(lf(committed), rendered, `src/${plan_policy_codegen_1.GENERATED_FILE} no longer matches the app — run \`npm run codegen\``);
});
(0, node_test_1.default)('the app is read, not merely parsed into nothing', () => {
    // A parser that quietly returns empty lists would satisfy the test above by
    // generating an empty file from an empty read.
    const policy = (0, plan_policy_codegen_1.readAppPolicy)((0, plan_policy_codegen_1.appDomainDir)(REPO));
    strict_1.default.ok(policy.featureKeys.length >= 9, `read only ${policy.featureKeys.length} feature keys`);
    const free = policy.plans.find((plan) => plan.code === 'free');
    strict_1.default.ok(free, 'the app declares no free plan');
    strict_1.default.ok(free.features.length > 0, 'the free plan reads as granting nothing');
    strict_1.default.ok(free.whatsappMonthlyLimit !== null, 'the free plan reads as having no limit');
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
function fixture(overrides = {}) {
    const dir = (0, node_fs_1.mkdtempSync)(node_path_1.default.join((0, node_os_1.tmpdir)(), 'plan-policy-'));
    const files = {
        'feature_keys.dart': FEATURE_KEYS_DART,
        'plan.dart': PLAN_DART,
        'plan_catalog.dart': PLAN_CATALOG_DART,
        ...overrides,
    };
    for (const [name, contents] of Object.entries(files)) {
        (0, node_fs_1.writeFileSync)(node_path_1.default.join(dir, name), contents, 'utf8');
    }
    return dir;
}
(0, node_test_1.default)('plans come out in declaration order, with their code and name', () => {
    const policy = (0, plan_policy_codegen_1.readAppPolicy)(fixture());
    strict_1.default.deepEqual(policy.plans.map((plan) => [plan.code, plan.name]), [
        ['free', 'Free'],
        ['pro', 'Pro'],
    ]);
});
(0, node_test_1.default)('a plan with no WhatsApp limit reads as unlimited, not as zero', () => {
    const policy = (0, plan_policy_codegen_1.readAppPolicy)(fixture());
    strict_1.default.equal(policy.plans[0].whatsappMonthlyLimit, 150);
    strict_1.default.equal(policy.plans[1].whatsappMonthlyLimit, null);
});
(0, node_test_1.default)('features follow the order of `all`, not the order the plan lists them', () => {
    // Dart sets are written in whatever order reads well. Sorting them here is
    // what keeps the generated file from changing when nothing has.
    const shuffled = PLAN_CATALOG_DART.replace('FeatureKeys.alpha,\n        FeatureKeys.beta,', 'FeatureKeys.beta,\n        FeatureKeys.alpha,');
    const policy = (0, plan_policy_codegen_1.readAppPolicy)(fixture({ 'plan_catalog.dart': shuffled }));
    strict_1.default.deepEqual(policy.plans[1].features, ['alpha', 'beta']);
});
(0, node_test_1.default)('a feature key left out of `all` is refused', () => {
    const orphan = FEATURE_KEYS_DART.replace("static const String beta = 'beta';", "static const String beta = 'beta';\n  static const String gamma = 'gamma';");
    strict_1.default.throws(() => (0, plan_policy_codegen_1.readAppPolicy)(fixture({ 'feature_keys.dart': orphan })), /gamma is missing from FeatureKeys.all/);
});
(0, node_test_1.default)('a plan granting a feature that does not exist is refused', () => {
    const invented = PLAN_CATALOG_DART.replace('FeatureKeys.alpha}', 'FeatureKeys.delta}');
    strict_1.default.throws(() => (0, plan_policy_codegen_1.readAppPolicy)(fixture({ 'plan_catalog.dart': invented })), /grants FeatureKeys.delta, which does not exist/);
});
(0, node_test_1.default)('a plan with no limit declared at all is refused', () => {
    const missing = PLAN_CATALOG_DART.replace('      whatsappMonthlyLimit: 150,\n', '');
    strict_1.default.throws(() => (0, plan_policy_codegen_1.readAppPolicy)(fixture({ 'plan_catalog.dart': missing })), /declares no whatsappMonthlyLimit/);
});
(0, node_test_1.default)('a renamed getter in the enum is refused rather than guessed at', () => {
    const renamed = PLAN_DART.replace('String get displayName', 'String get label');
    strict_1.default.throws(() => (0, plan_policy_codegen_1.readAppPolicy)(fixture({ 'plan.dart': renamed })), /no longer declares the displayName getter/);
});
/* -------------------------------------------------------------- the output */
(0, node_test_1.default)('the rendered file compiles the plan codes into keys of PLANS', () => {
    const rendered = (0, plan_policy_codegen_1.renderPlanPolicy)((0, plan_policy_codegen_1.readAppPolicy)(fixture()));
    strict_1.default.match(rendered, /export const PLANS: Record<PlanCode, PlanPolicy> = \{/);
    strict_1.default.match(rendered, /\n {2}free: \{/);
    strict_1.default.match(rendered, /\n {2}pro: \{/);
    strict_1.default.match(rendered, /export type PlanCode = 'free' \| 'pro';/);
});
(0, node_test_1.default)('the rendering is stable for the same input', () => {
    const dir = fixture();
    strict_1.default.equal((0, plan_policy_codegen_1.renderPlanPolicy)((0, plan_policy_codegen_1.readAppPolicy)(dir)), (0, plan_policy_codegen_1.renderPlanPolicy)((0, plan_policy_codegen_1.readAppPolicy)(dir)));
});
