class FeatureKeys {
  static const String whatsappAutomation = 'whatsapp_automation';
  static const String campaigns = 'campaigns';
  static const String analytics = 'analytics';
  static const String multiDevice = 'multi_device';
  static const String cloudBackup = 'cloud_backup';
  static const String engageViewRisk = 'engage_view_risk';
  static const String engageManageRecovery = 'engage_manage_recovery';
  static const String engageManageVisits = 'engage_manage_visits';
  static const String engageManageSurveys = 'engage_manage_surveys';

  /// The Retention Engine's P0 automations (Bónus de Regresso, Near Reward,
  /// Re-engagement, Win-back). Free on every plan by design: unlike Engage's
  /// manual recovery queue/dashboard, these are core loyalty behaviour, not a
  /// paid upsell.
  static const String retentionCore = 'retention_core';

  static const List<String> all = [
    whatsappAutomation,
    campaigns,
    analytics,
    multiDevice,
    cloudBackup,
    engageViewRisk,
    engageManageRecovery,
    engageManageVisits,
    engageManageSurveys,
    retentionCore,
  ];
}
