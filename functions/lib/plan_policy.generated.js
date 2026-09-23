"use strict";
/**
 * Generated from the app's own plan definitions. Do not edit by hand.
 *
 * Source: lib/features/subscription/domain/{feature_keys,plan,plan_catalog}.dart
 * Regenerate: npm run codegen (from functions/)
 *
 * Committed because `firebase deploy` uploads only this directory and
 * cannot reach the app's sources; plan_policy_codegen.test.ts fails if what
 * is committed here no longer matches them.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.PLANS = exports.FEATURE_KEYS = void 0;
/** Every feature the app knows about, in the order it declares them. */
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
    'retention_core',
];
/** What each plan grants, keyed by the code stored on a business. */
exports.PLANS = {
    launch_access: {
        code: 'launch_access',
        name: 'Launch Access',
        features: [
            'whatsapp_automation',
            'campaigns',
            'analytics',
            'multi_device',
            'cloud_backup',
            'engage_view_risk',
            'engage_manage_recovery',
            'engage_manage_visits',
            'engage_manage_surveys',
            'retention_core',
        ],
        whatsappMonthlyLimit: 20000,
    },
    free: {
        code: 'free',
        name: 'Free',
        features: [
            'whatsapp_automation',
            'retention_core',
        ],
        whatsappMonthlyLimit: 150,
    },
    starter: {
        code: 'starter',
        name: 'Starter',
        features: [
            'whatsapp_automation',
            'campaigns',
            'analytics',
            'retention_core',
        ],
        whatsappMonthlyLimit: 1200,
    },
    pro: {
        code: 'pro',
        name: 'Pro',
        features: [
            'whatsapp_automation',
            'campaigns',
            'analytics',
            'engage_view_risk',
            'retention_core',
        ],
        whatsappMonthlyLimit: 3000,
    },
    business: {
        code: 'business',
        name: 'Business',
        features: [
            'whatsapp_automation',
            'campaigns',
            'analytics',
            'multi_device',
            'cloud_backup',
            'engage_view_risk',
            'engage_manage_recovery',
            'engage_manage_visits',
            'engage_manage_surveys',
            'retention_core',
        ],
        whatsappMonthlyLimit: 6000,
    },
    growth: {
        code: 'growth',
        name: 'Growth',
        features: [
            'whatsapp_automation',
            'campaigns',
            'analytics',
            'multi_device',
            'cloud_backup',
            'engage_view_risk',
            'engage_manage_recovery',
            'engage_manage_visits',
            'engage_manage_surveys',
            'retention_core',
        ],
        whatsappMonthlyLimit: 6000,
    },
};
