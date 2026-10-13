#!/usr/bin/env node
/**
 * Writes functions/src/plan_policy.generated.ts from the app's plan
 * definitions in lib/features/subscription/domain.
 *
 * Run it after changing a feature key, a plan, or what a plan grants:
 *
 *   cd functions && npm run codegen
 *
 * The rendering lives in src/plan_policy_codegen.ts so it is typed and tested;
 * this only reads and writes files. `npm test` re-renders and compares, so
 * forgetting to run this fails the suite instead of shipping a stale copy.
 */

const { writeFileSync, readFileSync, existsSync } = require('node:fs');
const path = require('node:path');

const {
  GENERATED_FILE,
  appDomainDir,
  readAppPolicy,
  renderPlanPolicy,
} = require('../lib/plan_policy_codegen.js');

const functionsDir = path.join(__dirname, '..');
const repoRoot = path.join(functionsDir, '..');
const target = path.join(functionsDir, 'src', GENERATED_FILE);

const rendered = renderPlanPolicy(readAppPolicy(appDomainDir(repoRoot)));
const current = existsSync(target) ? readFileSync(target, 'utf8') : null;

if (current !== null && current.replace(/\r\n/g, '\n') === rendered) {
  console.log(`${GENERATED_FILE} is already up to date.`);
  process.exit(0);
}

writeFileSync(target, rendered, 'utf8');
console.log(`${current === null ? 'Created' : 'Updated'} src/${GENERATED_FILE}.`);
