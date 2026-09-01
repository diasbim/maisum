import 'server-only';

import { readFile } from 'node:fs/promises';
import path from 'node:path';

/**
 * The declared catalogue: what each plan promises publicly.
 *
 * This is `docs/plans.json`, the same file `tool/check_plan_catalog.dart`
 * validates in CI. It is read from disk at request time rather than imported,
 * because importing it would bundle a copy at build time — and a stale copy of
 * the source of truth for what is being sold is worse than no copy.
 */

export type Backing = 'core' | 'feature_key' | 'inherits' | 'none';

export type Promise_ = {
  text: string;
  backing: Backing;
  featureKey?: string;
  inheritsFrom?: string;
  decision?: string;
};

export type DeclaredPlan = {
  code: string;
  publicName: string;
  advertised: boolean;
  tagline?: string;
  badge?: string;
  promises: Promise_[];
};

export type OpenDecision = {
  id: string;
  summary: string;
  affects: string[];
  options: string[];
};

export type Catalog = {
  version: number;
  currency: string;
  pricingPolicy: string;
  plans: DeclaredPlan[];
  openDecisions: OpenDecision[];
};

/**
 * Where `docs/plans.json` sits relative to the running server.
 *
 * `PLAN_CATALOG_PATH` overrides it, which is what a deployment that does not
 * ship the repo alongside the app will need.
 */
function catalogPath(): string {
  const configured = process.env.PLAN_CATALOG_PATH;
  if (configured && configured.trim() !== '') return configured.trim();
  return path.join(process.cwd(), '..', 'docs', 'plans.json');
}

export type CatalogResult =
  | { catalog: Catalog; error: null }
  | { catalog: null; error: string };

export async function readCatalog(): Promise<CatalogResult> {
  const file = catalogPath();
  let raw: string;

  try {
    // The path is deliberately outside the app root — it is the repo's own
    // docs/plans.json. Without this the bundler traces the whole project into
    // the server output on the assumption that any file might be read.
    raw = await readFile(/* turbopackIgnore: true */ file, 'utf8');
  } catch {
    return {
      catalog: null,
      // Naming the path it tried turns this into something fixable rather than
      // a mystery; the fix is usually PLAN_CATALOG_PATH.
      error: `Não foi possível ler o catálogo declarado em ${file}. Defina PLAN_CATALOG_PATH se o ficheiro estiver noutro sítio.`,
    };
  }

  try {
    return { catalog: JSON.parse(raw) as Catalog, error: null };
  } catch (caught) {
    const detail = caught instanceof Error ? caught.message : String(caught);
    return { catalog: null, error: `plans.json inválido: ${detail}` };
  }
}

/**
 * Every feature key a plan effectively promises, following `inherits` down the
 * chain.
 *
 * Inheritance is transitive — Business inherits Pro, which inherits Starter —
 * so a promise satisfied two levels down still counts. Resolving it here keeps
 * the page from reporting a gap that is really an inherited grant.
 */
export function promisedKeys(
  catalog: Catalog,
  code: string,
  seen: Set<string> = new Set(),
): Set<string> {
  const keys = new Set<string>();
  if (seen.has(code)) return keys;
  seen.add(code);

  const plan = catalog.plans.find((candidate) => candidate.code === code);
  if (!plan) return keys;

  for (const promise of plan.promises) {
    if (promise.backing === 'feature_key' && promise.featureKey) {
      keys.add(promise.featureKey);
    }
    if (promise.backing === 'inherits' && promise.inheritsFrom) {
      for (const inherited of promisedKeys(catalog, promise.inheritsFrom, seen)) {
        keys.add(inherited);
      }
    }
  }

  return keys;
}
