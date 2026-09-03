"use strict";
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
 * Kept free of firebase-admin so the shapes can be tested directly, and
 * checked against the app's own definitions — `merchant_bootstrap.test.ts`
 * reads feature_keys.dart and plan_catalog.dart and fails if they drift.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.FREE_PLAN = exports.WHATSAPP_MESSAGES_METRIC = exports.FEATURE_KEYS = void 0;
exports.monthlyWindow = monthlyWindow;
exports.bootstrapDocuments = bootstrapDocuments;
/** Mirrors `lib/features/subscription/domain/feature_keys.dart`. */
exports.FEATURE_KEYS = [
    'whatsapp_automation',
    'campaigns',
    'analytics',
    'multi_device',
    'cloud_backup',
    'engage_view_risk',
    'engage_manage_recovery',
    'engage_manage_visits',
    'engage_manage_surveys',
];
exports.WHATSAPP_MESSAGES_METRIC = 'whatsapp_messages';
/**
 * The plan a business starts on, mirroring `PlanCatalog` for `Plan.free`.
 *
 * Only the free plan is here on purpose. Every other plan is granted by
 * someone — a person in the console, or billing — and a business that could
 * arrive on a paid plan by being created would be a way to grant one.
 */
exports.FREE_PLAN = {
    code: 'free',
    name: 'Free',
    features: ['whatsapp_automation'],
    whatsappMonthlyLimit: 150,
};
/** The calendar month `now` falls in, as the app computes it. */
function monthlyWindow(now) {
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
function bootstrapDocuments(input) {
    const { merchantId, now } = input;
    const status = input.subscriptionStatus.trim() || 'TRIAL';
    const window = monthlyWindow(new Date(now));
    const documents = [];
    documents.push({
        collection: 'subscription_state',
        id: merchantId,
        data: {
            merchant_id: merchantId,
            plan_code: exports.FREE_PLAN.code,
            plan_name: exports.FREE_PLAN.name,
            plan_version: 1,
            pricing_version: 1,
            status,
            updated_at: now,
        },
    });
    for (const featureKey of exports.FEATURE_KEYS) {
        const id = `${merchantId}_${featureKey}`;
        documents.push({
            collection: 'entitlements',
            id,
            data: {
                id,
                merchant_id: merchantId,
                feature_key: featureKey,
                is_enabled: exports.FREE_PLAN.features.includes(featureKey),
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
    const quotaId = `${merchantId}_${exports.WHATSAPP_MESSAGES_METRIC}_${window.start}`;
    documents.push({
        collection: 'usage_balances',
        id: quotaId,
        data: {
            id: quotaId,
            merchant_id: merchantId,
            metric_key: exports.WHATSAPP_MESSAGES_METRIC,
            window_start: window.start,
            window_end: window.end,
            used: 0,
            limit_value: exports.FREE_PLAN.whatsappMonthlyLimit,
            soft_limit: true,
            updated_at: now,
        },
    });
    return documents;
}
