"use strict";
/**
 * Reads the app's plan definitions and writes them out as TypeScript.
 *
 * The plans, the feature keys and which plan grants what are decided in one
 * place — `lib/features/subscription/domain` — and Functions cannot import
 * Dart. It used to hold a hand-written copy, guarded by a test that compared
 * the two; that catches drift but still asks a person to make the same edit
 * twice, in two languages, and to get it right.
 *
 * So the copy is derived instead. This parses the Dart and renders
 * `plan_policy.generated.ts`, which is committed because `firebase deploy`
 * uploads only the functions directory and cannot reach the app's sources at
 * deploy time. `plan_policy_codegen.test.ts` re-renders and compares, so a
 * committed file that no longer matches the app fails the build rather than
 * being deployed.
 *
 * Regenerate with `npm run codegen` in functions/.
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.GENERATED_FILE = void 0;
exports.appDomainDir = appDomainDir;
exports.readAppPolicy = readAppPolicy;
exports.renderPlanPolicy = renderPlanPolicy;
const node_fs_1 = require("node:fs");
const node_path_1 = __importDefault(require("node:path"));
exports.GENERATED_FILE = 'plan_policy.generated.ts';
/** Where the app keeps the definitions, given the repository root. */
function appDomainDir(repoRoot) {
    return node_path_1.default.join(repoRoot, 'lib', 'features', 'subscription', 'domain');
}
/**
 * The plan policy as the app states it.
 *
 * Every failure here throws rather than falling back: a silently empty feature
 * list would generate a file that grants a new business nothing, and it would
 * look deliberate.
 */
function readAppPolicy(domainDir) {
    const read = (file) => (0, node_fs_1.readFileSync)(node_path_1.default.join(domainDir, file), 'utf8').replace(/\r\n/g, '\n');
    const featureKeys = parseFeatureKeys(read('feature_keys.dart'));
    const plans = parsePlanCatalog(read('plan_catalog.dart'), read('plan.dart'), featureKeys);
    return { featureKeys: featureKeys.order, plans };
}
function parseFeatureKeys(source) {
    const values = new Map();
    for (const match of source.matchAll(/static const String (\w+) = '([a-z_]+)';/g)) {
        values.set(match[1], match[2]);
    }
    if (values.size === 0) {
        throw new Error('feature_keys.dart declares no feature keys');
    }
    const list = /static const List<String> all = \[([\s\S]*?)\];/.exec(source);
    if (!list) {
        throw new Error('feature_keys.dart no longer declares `all`');
    }
    const names = list[1]
        .split(',')
        .map((entry) => entry.trim())
        .filter((entry) => entry !== '');
    const order = names.map((name) => {
        const value = values.get(name);
        if (value === undefined) {
            throw new Error(`FeatureKeys.all lists ${name}, which has no string value`);
        }
        return value;
    });
    // A key declared but left out of `all` would be granted by a plan and never
    // provisioned, so the business would hold an entitlement nothing wrote.
    for (const [name, value] of values) {
        if (!order.includes(value)) {
            throw new Error(`FeatureKeys.${name} is missing from FeatureKeys.all`);
        }
    }
    return { values, order };
}
function parsePlanCatalog(catalog, planEnum, featureKeys) {
    const codes = parsePlanSwitch(planEnum, 'code');
    const names = parsePlanSwitch(planEnum, 'displayName');
    const map = /_definitions = \{([\s\S]*?)\n  \};/.exec(catalog);
    if (!map) {
        throw new Error('plan_catalog.dart no longer declares `_definitions`');
    }
    const body = map[1];
    const heads = [...body.matchAll(/Plan\.(\w+): PlanDefinition\(/g)];
    if (heads.length === 0) {
        throw new Error('plan_catalog.dart declares no plans');
    }
    return heads.map((head, index) => {
        const dartName = head[1];
        const start = head.index + head[0].length;
        const next = heads[index + 1];
        const definition = body.slice(start, next ? next.index : body.length);
        const code = codes.get(dartName);
        const name = names.get(dartName);
        if (code === undefined || name === undefined) {
            throw new Error(`Plan.${dartName} has no code or display name in plan.dart`);
        }
        const features = [...definition.matchAll(/FeatureKeys\.(\w+)/g)].map((match) => {
            const value = featureKeys.values.get(match[1]);
            if (value === undefined) {
                throw new Error(`Plan.${dartName} grants FeatureKeys.${match[1]}, which does not exist`);
            }
            return value;
        });
        const limit = /whatsappMonthlyLimit:\s*(\d+|null)/.exec(definition);
        if (!limit) {
            throw new Error(`Plan.${dartName} declares no whatsappMonthlyLimit`);
        }
        return {
            code,
            name,
            // Ordered as `FeatureKeys.all` orders them, so the rendered file changes
            // only when the policy does — not when someone reshuffles a Dart set.
            features: featureKeys.order.filter((key) => features.includes(key)),
            whatsappMonthlyLimit: limit[1] === 'null' ? null : Number(limit[1]),
        };
    });
}
/** `Plan.free => 'free',` from one of the enum's switch getters. */
function parsePlanSwitch(source, getter) {
    const block = new RegExp(`String get ${getter} => switch \\(this\\) \\{([\\s\\S]*?)\\};`).exec(source);
    if (!block) {
        throw new Error(`plan.dart no longer declares the ${getter} getter`);
    }
    const entries = new Map();
    for (const match of block[1].matchAll(/Plan\.(\w+) => '([^']*)'/g)) {
        entries.set(match[1], match[2]);
    }
    if (entries.size === 0) {
        throw new Error(`plan.dart's ${getter} getter maps no plans`);
    }
    return entries;
}
/** The contents of `plan_policy.generated.ts` for this policy. */
function renderPlanPolicy(policy) {
    const lines = [];
    lines.push('/**');
    lines.push(' * Generated from the app\'s own plan definitions. Do not edit by hand.');
    lines.push(' *');
    lines.push(' * Source: lib/features/subscription/domain/{feature_keys,plan,plan_catalog}.dart');
    lines.push(' * Regenerate: npm run codegen (from functions/)');
    lines.push(' *');
    lines.push(' * Committed because `firebase deploy` uploads only this directory and');
    lines.push(' * cannot reach the app\'s sources; plan_policy_codegen.test.ts fails if what');
    lines.push(' * is committed here no longer matches them.');
    lines.push(' */');
    lines.push('');
    lines.push('/** Every feature the app knows about, in the order it declares them. */');
    lines.push('export const FEATURE_KEYS = [');
    for (const key of policy.featureKeys) {
        lines.push(`  '${key}',`);
    }
    lines.push('] as const;');
    lines.push('');
    lines.push('export type FeatureKey = (typeof FEATURE_KEYS)[number];');
    lines.push('');
    lines.push('export type PlanPolicy = {');
    lines.push('  code: string;');
    lines.push('  name: string;');
    lines.push('  features: FeatureKey[];');
    lines.push('  whatsappMonthlyLimit: number | null;');
    lines.push('};');
    lines.push('');
    lines.push('/** The plan codes stored on a business. */');
    lines.push(`export type PlanCode = ${policy.plans.map((plan) => `'${plan.code}'`).join(' | ')};`);
    lines.push('');
    lines.push('/** What each plan grants, keyed by the code stored on a business. */');
    // Annotated rather than `satisfies`: the features have to read as FeatureKey[]
    // so a caller can ask whether an arbitrary key is granted, and `satisfies`
    // would keep them at their literal types.
    lines.push('export const PLANS: Record<PlanCode, PlanPolicy> = {');
    for (const plan of policy.plans) {
        lines.push(`  ${plan.code}: {`);
        lines.push(`    code: '${plan.code}',`);
        lines.push(`    name: '${plan.name}',`);
        if (plan.features.length === 0) {
            lines.push('    features: [],');
        }
        else {
            lines.push('    features: [');
            for (const feature of plan.features) {
                lines.push(`      '${feature}',`);
            }
            lines.push('    ],');
        }
        lines.push(`    whatsappMonthlyLimit: ${plan.whatsappMonthlyLimit ?? 'null'},`);
        lines.push('  },');
    }
    lines.push('};');
    lines.push('');
    return lines.join('\n');
}
