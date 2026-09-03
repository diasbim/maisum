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

/** Every feature the app knows about, in the order it declares them. */
export const FEATURE_KEYS = [
  'whatsapp_automation',
  'campaigns',
  'analytics',
  'multi_device',
  'cloud_backup',
  'engage_view_risk',
  'engage_manage_recovery',
  'engage_manage_visits',
  'engage_manage_surveys',
] as const;

export type FeatureKey = (typeof FEATURE_KEYS)[number];

export type PlanPolicy = {
  code: string;
  name: string;
  features: FeatureKey[];
  whatsappMonthlyLimit: number | null;
};

/** The plan codes stored on a business. */
export type PlanCode = 'launch_access' | 'free' | 'starter' | 'pro' | 'business' | 'growth';

/** What each plan grants, keyed by the code stored on a business. */
export const PLANS: Record<PlanCode, PlanPolicy> = {
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
    ],
    whatsappMonthlyLimit: 20000,
  },
  free: {
    code: 'free',
    name: 'Free',
    features: [
      'whatsapp_automation',
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
    ],
    whatsappMonthlyLimit: 6000,
  },
};
