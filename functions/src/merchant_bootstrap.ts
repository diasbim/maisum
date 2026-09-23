/**
 * The policy documents every business starts with.
 *
 * `firestore.rules` treats these five collections as server-owned: a client
 * may read them and may not write them. The app tried to seed them anyway, on
 * the first sign-in after a business was created, and Firestore refused —
 * every new business ended up with no plan, no entitlements and no quota, and
 * the portal's plan screen had nothing to show. The refusal was correct; the
 * missing half was here.
 *
 * So this builds exactly what the app used to write, and the trigger in
 * index.ts writes it with the Admin SDK, which is the only thing entitled to.
 *
 * What the plans are and what they grant is not restated here: it is the app's
 * to decide, in lib/features/subscription/domain, and plan_policy.generated.ts
 * is rendered from those files by plan_policy_codegen.ts. This module decides
 * only which plan a new business starts on and what the documents look like.
 */

import { FEATURE_KEYS, PLANS } from './plan_policy.generated.js';

export { FEATURE_KEYS };

export const WHATSAPP_MESSAGES_METRIC = 'whatsapp_messages';

/**
 * The plan a business starts on.
 *
 * Free on purpose. Every other plan is granted by someone — a person in the
 * console, or billing — and a business that could arrive on a paid plan by
 * being created would be a way to grant one.
 */
export const FREE_PLAN = PLANS.free;

export type SeedDocument = {
  collection: string;
  id: string;
  data: Record<string, unknown>;
};

/** The calendar month `now` falls in, as the app computes it. */
export function monthlyWindow(now: Date): { start: number; end: number } {
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  return { start: start.getTime(), end: nextMonth.getTime() - 1 };
}

/**
 * Everything a newly created business needs, ready to write.
 *
 * Document ids match what the app used to produce, so a business seeded by the
 * old client path and one seeded here are the same business — nothing has to
 * know which wrote it.
 */
export function bootstrapDocuments(input: {
  merchantId: string;
  subscriptionStatus: string;
  now: number;
}): SeedDocument[] {
  const { merchantId, now } = input;
  const status = input.subscriptionStatus.trim() || 'TRIAL';
  const window = monthlyWindow(new Date(now));
  const documents: SeedDocument[] = [];

  documents.push({
    collection: 'subscription_state',
    id: merchantId,
    data: {
      merchant_id: merchantId,
      plan_code: FREE_PLAN.code,
      plan_name: FREE_PLAN.name,
      plan_version: 1,
      pricing_version: 1,
      status,
      updated_at: now,
    },
  });

  for (const featureKey of FEATURE_KEYS) {
    const id = `${merchantId}_${featureKey}`;

    documents.push({
      collection: 'entitlements',
      id,
      data: {
        id,
        merchant_id: merchantId,
        feature_key: featureKey,
        is_enabled: FREE_PLAN.features.includes(featureKey),
        updated_at: now,
      },
    });

    // The flag is on for every feature; the entitlement above is what decides
    // whether the plan grants it. Two separate switches, and this is the one
    // that says "not withdrawn from this business".
    documents.push({
      collection: 'feature_flags',
      id,
      data: {
        id,
        merchant_id: merchantId,
        flag_key: featureKey,
        is_enabled: true,
        updated_at: now,
      },
    });
  }

  const configId = `${merchantId}_billing_whatsapp_price`;
  documents.push({
    collection: 'remote_config',
    id: configId,
    data: {
      id: configId,
      merchant_id: merchantId,
      config_key: 'billing_whatsapp_price',
      payload: { currency: 'MZN', amount: 2 },
      updated_at: now,
    },
  });

  const quotaId = `${merchantId}_${WHATSAPP_MESSAGES_METRIC}_${window.start}`;
  documents.push({
    collection: 'usage_balances',
    id: quotaId,
    data: {
      id: quotaId,
      merchant_id: merchantId,
      metric_key: WHATSAPP_MESSAGES_METRIC,
      window_start: window.start,
      window_end: window.end,
      used: 0,
      limit_value: FREE_PLAN.whatsappMonthlyLimit,
      soft_limit: true,
      updated_at: now,
    },
  });

  return documents;
}
