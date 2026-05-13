class RemoteConfigKeys {
  static const trialsEnabled = 'billing.trials.enabled';
  static const trialDays = 'billing.trials.days';
  static const promotionBanner = 'billing.promotions.banner';

  static const _pricingPrefix = 'pricing.plan.';
  static const _quotaPrefix = 'quota.';

  static String pricingPlan(String planCode) =>
      '$_pricingPrefix${planCode.toLowerCase()}';

  static String quotaMetric(String metricKey) => '$_quotaPrefix$metricKey';
}
